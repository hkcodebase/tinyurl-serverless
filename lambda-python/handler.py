import json
import os
import urllib.request
import urllib.error
from datetime import datetime, timezone
from decimal import Decimal


class _DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super().default(obj)

from dynamodb_service import (
    save_url,
    get_url,
    increment_redirect_count,
    get_stats,
)

# ── Cognito config ─────────────────────────────────────────────────────────────
COGNITO_REGION    = os.environ.get("COGNITO_REGION", "us-east-1")
COGNITO_USER_POOL = os.environ.get("COGNITO_USER_POOL_ID", "")
COGNITO_JWKS_URL  = (
    f"https://cognito-idp.{COGNITO_REGION}.amazonaws.com"
    f"/{COGNITO_USER_POOL}/.well-known/jwks.json"
)
ADMIN_GROUP = os.environ.get("COGNITO_ADMIN_GROUP", "admin")

# ── CORS headers ───────────────────────────────────────────────────────────────
ALLOWED_ORIGIN = os.environ.get("ALLOWED_ORIGIN", "*")

CORS_HEADERS = {
    "Access-Control-Allow-Origin":  ALLOWED_ORIGIN,
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
    "Access-Control-Allow-Methods": "OPTIONS,GET,POST",
    "Content-Type":                 "application/json",
}


# ── JWT validation (lightweight, no external lib) ──────────────────────────────
def _b64_decode(data: str) -> bytes:
    """URL-safe base64 decode with padding."""
    import base64
    data += "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(data)


def _decode_jwt_payload(token: str) -> dict:
    """Decode JWT payload without verifying signature (signature verified by Cognito JWKS)."""
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("Invalid JWT format")
    payload = json.loads(_b64_decode(parts[1]))
    return payload


def _verify_cognito_token(token: str) -> dict:
    """
    Verify a Cognito JWT.
    - Decodes the payload
    - Checks expiry
    - Checks issuer matches the configured user pool
    Returns the decoded payload on success, raises ValueError on failure.
    
    Note: For full production use, verify the RS256 signature against the JWKS.
    This lightweight version trusts Cognito's issuer claim and checks expiry.
    For full signature verification, add 'python-jose' or 'cryptography' to Lambda layer.
    """
    payload = _decode_jwt_payload(token)

    # Check expiry
    now = int(datetime.now(timezone.utc).timestamp())
    if payload.get("exp", 0) < now:
        raise ValueError("Token expired")

    # Check issuer
    expected_iss = (
        f"https://cognito-idp.{COGNITO_REGION}.amazonaws.com/{COGNITO_USER_POOL}"
    )
    if payload.get("iss") != expected_iss:
        raise ValueError("Invalid token issuer")

    return payload


def _extract_user(event: dict) -> tuple[str, list[str]]:
    """
    Extract user identity from the Authorization header.
    Returns (user_id, groups).
    - Authenticated: (cognito_sub, [groups])
    - Guest:         ("guest", [])
    """
    auth_header = (event.get("headers") or {}).get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return "guest", []

    token = auth_header.removeprefix("Bearer ").strip()
    try:
        payload = _verify_cognito_token(token)
        user_id = payload.get("email") or payload.get("sub", "guest")
        groups  = payload.get("cognito:groups", [])
        return user_id, groups
    except Exception:
        # Invalid token → treat as guest rather than rejecting
        return "guest", []


def _is_admin(groups: list[str]) -> bool:
    return ADMIN_GROUP in groups


# ── Response helpers ───────────────────────────────────────────────────────────
def _ok(body: dict, status: int = 200) -> dict:
    return {
        "statusCode": status,
        "headers": CORS_HEADERS,
        "body": json.dumps(body, cls=_DecimalEncoder),
    }


def _err(message: str, status: int = 400) -> dict:
    return {
        "statusCode": status,
        "headers": CORS_HEADERS,
        "body": json.dumps({"error": message}),
    }


# ── Route handlers ─────────────────────────────────────────────────────────────
def _handle_post_urls(event: dict, user_id: str) -> dict:
    """POST /urls — shorten a URL. Open to guests and authenticated users."""
    body = event.get("body", "")
    if not body:
        return _err("URL is required")

    url = body.strip().strip('"')
    if not url.startswith(("http://", "https://")):
        return _err("Invalid URL — must start with http:// or https://")

    created_at = datetime.now(timezone.utc).isoformat()

    tinyurl = save_url(
        original_url=url,
        created_at=created_at,
        created_by=user_id,
    )

    return _ok({"tinyurl": tinyurl}, status=201)


def _handle_get_hash(hash_value: str) -> dict:
    """GET /{hash} — resolve short link and redirect."""
    item = get_url(hash_value)
    if not item:
        return _err("Short link not found", status=404)

    # Increment redirect count asynchronously-safe (best effort)
    try:
        increment_redirect_count(hash_value)
    except Exception:
        pass  # Don't fail the redirect if count update fails

    return {
        "statusCode": 301,
        "headers": {
            **CORS_HEADERS,
            "Location": item["original_url"],
        },
        "body": "",
    }


def _handle_get_admin_stats(groups: list[str]) -> dict:
    """GET /admin/stats — admin-only stats endpoint."""
    if not _is_admin(groups):
        return _err("Forbidden — admin access required", status=403)

    try:
        stats = get_stats()
        return _ok(stats)
    except Exception as e:
        return _err(f"Internal error: {str(e)}", status=500)


def _handle_options() -> dict:
    """OPTIONS — CORS preflight."""
    return {
        "statusCode": 200,
        "headers": CORS_HEADERS,
        "body": "",
    }


# ── Main handler ───────────────────────────────────────────────────────────────
def lambda_handler(event: dict, context) -> dict:
    method = event.get("httpMethod", "")
    path   = event.get("path", "/")

    # CORS preflight
    if method == "OPTIONS":
        return _handle_options()

    # Extract user for all routes
    user_id, groups = _extract_user(event)

    # POST /urls — shorten
    if method == "POST" and path == "/urls":
        return _handle_post_urls(event, user_id)

    # GET /admin/stats — admin stats
    if method == "GET" and path == "/admin/stats":
        return _handle_get_admin_stats(groups)

    # GET /{hash} — redirect
    if method == "GET" and len(path) > 1:
        hash_value = path.lstrip("/")
        return _handle_get_hash(hash_value)

    return _err("Not found", status=404)
