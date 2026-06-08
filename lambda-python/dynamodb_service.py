import os
import string
import random
import boto3
from boto3.dynamodb.conditions import Attr
from decimal import Decimal

# ── DynamoDB setup ─────────────────────────────────────────────────────────────
_ENDPOINT = os.environ.get("DYNAMODB_ENDPOINT")  # set for local dev only
_REGION   = os.environ.get("AWS_REGION", "us-east-1")
_TABLE    = os.environ.get("DYNAMODB_TABLE", "Url")

_dynamodb = boto3.resource(
    "dynamodb",
    region_name=_REGION,
    **({"endpoint_url": _ENDPOINT} if _ENDPOINT else {}),
)
_table = _dynamodb.Table(_TABLE)

# ── Hash generation ────────────────────────────────────────────────────────────
_ALPHABET  = string.ascii_letters + string.digits  # a-z A-Z 0-9
_HASH_LEN  = 6
_MAX_RETRY = 5


def _generate_hash() -> str:
    return "".join(random.choices(_ALPHABET, k=_HASH_LEN))


# ── Write ──────────────────────────────────────────────────────────────────────
def save_url(original_url: str, created_at: str, created_by: str) -> str:
    """
    Save a URL mapping and return the generated short hash.
    Retries up to _MAX_RETRY times on hash collision.

    Schema:
        hash           (S) — partition key, short code e.g. "x7k2p"
        original_url   (S) — the full URL
        created_at     (S) — ISO 8601 timestamp in UTC
        created_by     (S) — Cognito sub or "guest"
        redirect_count (N) — number of times this link has been followed
    """
    for _ in range(_MAX_RETRY):
        hash_val = _generate_hash()
        try:
            _table.put_item(
                Item={
                    "hash":           hash_val,
                    "original_url":   original_url,
                    "created_at":     created_at,
                    "created_by":     created_by,
                    "redirect_count": 0,
                },
                # Only write if hash doesn't already exist
                ConditionExpression=Attr("hash").not_exists(),
            )
            return hash_val
        except _dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
            continue  # hash collision — retry

    raise RuntimeError("Failed to generate a unique hash after retries")


# ── Read ───────────────────────────────────────────────────────────────────────
def get_url(hash_val: str) -> dict | None:
    """
    Look up a short hash and return the item, or None if not found.
    """
    response = _table.get_item(Key={"hash": hash_val})
    return response.get("Item")


# ── Redirect count ─────────────────────────────────────────────────────────────
def increment_redirect_count(hash_val: str) -> None:
    """
    Atomically increment redirect_count for a given hash.
    """
    _table.update_item(
        Key={"hash": hash_val},
        UpdateExpression="ADD redirect_count :inc",
        ExpressionAttributeValues={":inc": 1},
    )


# ── Admin stats ────────────────────────────────────────────────────────────────
def get_stats() -> dict:
    """
    Scan the table and return aggregate stats.
    Returns:
        total_urls       — total number of short links created
        total_redirects  — sum of all redirect_count values
        guest_urls       — links created by guests
        user_urls        — links created by authenticated users
        top_links        — top 10 links by redirect_count
        urls_by_user     — count of links per created_by value
    """
    items = []
    response = _table.scan()
    items.extend(response.get("Items", []))

    # Handle pagination
    while "LastEvaluatedKey" in response:
        response = _table.scan(ExclusiveStartKey=response["LastEvaluatedKey"])
        items.extend(response.get("Items", []))

    total_urls      = len(items)
    total_redirects = sum(int(i.get("redirect_count", 0)) for i in items)
    guest_urls      = sum(1 for i in items if i.get("created_by") == "guest")
    user_urls       = total_urls - guest_urls

    # Top 10 by redirect count
    top_links = sorted(
        [
            {
                "hash":           i.get("hash", ""),
                "original_url":   i.get("original_url", ""),
                "redirect_count": int(i.get("redirect_count", 0)),
                "created_at":     i.get("created_at", ""),
                "created_by":     i.get("created_by", "guest"),
            }
            for i in items
            if i.get("hash") and i.get("original_url")
        ],
        key=lambda x: x["redirect_count"],
        reverse=True,
    )[:10]

    # URLs per user (group by created_by)
    urls_by_user: dict[str, int] = {}
    for item in items:
        creator = item.get("created_by", "guest")
        urls_by_user[creator] = urls_by_user.get(creator, 0) + 1

    return {
        "total_urls":      total_urls,
        "total_redirects": total_redirects,
        "guest_urls":      guest_urls,
        "user_urls":       user_urls,
        "top_links":       top_links,
        "urls_by_user":    urls_by_user,
    }
