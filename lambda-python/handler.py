import json
import re
import dynamodb_service

PAGE_404 = "404.html"


def lambda_handler(event, context):
    """Main Lambda entry point. Routes requests by HTTP method."""

    http_method = event.get("httpMethod", "GET")
    path = event.get("path", "/")
    body = event.get("body", "")
    headers = event.get("headers") or {}
    request_context = event.get("requestContext") or {}

    # Build the base host string used in response URLs (e.g. "abc123.execute-api.us-east-1.amazonaws.com/prod")
    host = headers.get("Host", "")
    stage = request_context.get("stage", "")
    base_url = f"{host}/{stage}" if stage else host

    if not http_method or not path:
        return _api_response(400, {"error": "Missing httpMethod or path"})

    try:
        if http_method == "POST":
            return _handle_create_short_url(body, base_url)
        elif http_method == "GET":
            return _handle_redirect(path, base_url)
        else:
            return _api_response(405, {"error": "Unsupported HTTP method"})
    except Exception as e:
        print(f"Unhandled error: {e}")
        return _api_response(500, {"error": "Unable to process the request"})


def _handle_create_short_url(url, base_url):
    """Handle POST: validate the URL, store it, return the short hash."""

    if not url:
        return _api_response(400, {"error": "Missing URL in request body"})

    if not _is_valid_url(url):
        return _api_response(400, {"error": f"Invalid URL: {url}"})

    hash_key = dynamodb_service.create_url(url)
    return _api_response(200, {"tinyurl": hash_key})


def _handle_redirect(path, base_url):
    """Handle GET: look up the hash and return a 302 redirect to the original URL."""

    # Extract the hash from the end of the path (e.g. "/abc123" → "abc123")
    hash_key = path.rsplit("/", 1)[-1]

    redirect_url = dynamodb_service.get_redirect_url(hash_key)

    if not redirect_url:
        # Hash not found — redirect to 404 page
        redirect_url = f"{base_url}/{PAGE_404}?originalUrl={base_url}{path}"

    return {
        "statusCode": 302,
        "headers": {"Location": redirect_url},
    }


def _is_valid_url(url):
    """Return True if the URL looks like a valid http/https URL."""
    pattern = re.compile(
        r"^https?://[-a-zA-Z0-9+&@#/%?=~_|!:,.;]*[-a-zA-Z0-9+&@#/%=~_|]$"
    )
    return bool(pattern.match(url))


def _api_response(status_code, body_dict):
    """Wrap a response dict with status code, CORS headers, and JSON body."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "OPTIONS,POST,GET",
        },
        "body": json.dumps(body_dict),
    }
