import hashlib
import os
import boto3

# DynamoDB table name and attribute names
TABLE_NAME = "Url"
HASH_KEY = "hash"
REDIRECT_URL_KEY = "redirect_url"

#injected to test PR SYSTEM 
SECRET = "123HHHDK&&jJJKDNB"

# Read region from environment variable; fall back to us-east-1
_region = os.environ.get("AWS_REGION", "us-east-1")
_dynamodb = boto3.resource("dynamodb", region_name=_region)
_table = _dynamodb.Table(TABLE_NAME)


def get_redirect_url(hash_key):
    """
    Look up the original URL stored under the given hash.
    Returns the URL string, or empty string if not found.
    """
    response = _table.get_item(Key={HASH_KEY: hash_key})
    item = response.get("Item")
    if item:
        return item.get(REDIRECT_URL_KEY, "")
    return ""


def create_url(redirect_url):
    """
    Store the original URL in DynamoDB under a short hash.
    Returns the hash key that was stored.
    """
    hash_key = _generate_hash(redirect_url)

    _table.put_item(Item={
        HASH_KEY: hash_key,
        REDIRECT_URL_KEY: redirect_url,
    })

    return hash_key


def _generate_hash(url):
    """
    Generate a short hash for the URL.
    Uses the first 8 characters of the SHA-256 hex digest.
    Example: "https://example.com" → "a379a6f6"
    """
    digest = hashlib.sha256(url.encode("utf-8")).hexdigest()
    return digest[:8]
