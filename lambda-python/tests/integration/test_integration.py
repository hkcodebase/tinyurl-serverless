"""
Integration tests for the TinyURL Lambda.

These tests exercise the full POST → GET flow end-to-end using a mocked
DynamoDB (moto), so no real AWS account or network is needed.

Run with:
    pytest tests/integration/
"""

import json
import pytest
import boto3
import importlib
from moto import mock_aws

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../.."))


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def aws_credentials(monkeypatch):
    """Dummy credentials so boto3 never tries a real AWS call."""
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")


@pytest.fixture
def full_stack():
    """
    Creates a mocked DynamoDB table and reloads both modules inside the
    mock context, giving us a fully wired Lambda handler to call.
    """
    with mock_aws():
        # Create the table the service expects
        boto3.client("dynamodb", region_name="us-east-1").create_table(
            TableName="Url",
            KeySchema=[{"AttributeName": "hash", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "hash", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )

        # Reload modules so their module-level boto3 clients hit the mock
        import dynamodb_service
        import handler
        importlib.reload(dynamodb_service)
        importlib.reload(handler)

        yield handler


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _post_event(url, host="api.example.com", stage="prod"):
    return {
        "httpMethod": "POST",
        "path": "/urls",
        "body": url,
        "headers": {"Host": host},
        "requestContext": {"stage": stage},
    }


def _get_event(hash_key, host="api.example.com", stage="prod"):
    return {
        "httpMethod": "GET",
        "path": f"/{hash_key}",
        "body": "",
        "headers": {"Host": host},
        "requestContext": {"stage": stage},
    }


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestCreateAndRedirectFlow:
    def test_full_flow(self, full_stack):
        """POST a URL → GET the returned hash → should redirect to original URL."""
        url = "https://example.com"

        # Step 1: shorten the URL
        post_response = full_stack.lambda_handler(_post_event(url), None)
        assert post_response["statusCode"] == 200

        hash_key = json.loads(post_response["body"])["tinyurl"]
        assert len(hash_key) == 8  # SHA-256 first 8 chars

        # Step 2: use the hash to redirect
        get_response = full_stack.lambda_handler(_get_event(hash_key), None)
        assert get_response["statusCode"] == 302
        assert get_response["headers"]["Location"] == url

    def test_same_url_gives_same_hash(self, full_stack):
        """POSTing the same URL twice must return the same hash both times."""
        url = "https://example.com"

        r1 = full_stack.lambda_handler(_post_event(url), None)
        r2 = full_stack.lambda_handler(_post_event(url), None)

        h1 = json.loads(r1["body"])["tinyurl"]
        h2 = json.loads(r2["body"])["tinyurl"]
        assert h1 == h2

    def test_different_urls_give_different_hashes(self, full_stack):
        r1 = full_stack.lambda_handler(_post_event("https://a.com"), None)
        r2 = full_stack.lambda_handler(_post_event("https://b.com"), None)

        h1 = json.loads(r1["body"])["tinyurl"]
        h2 = json.loads(r2["body"])["tinyurl"]
        assert h1 != h2

    def test_unknown_hash_redirects_to_404_page(self, full_stack):
        """A hash that was never stored must land on the 404 page."""
        response = full_stack.lambda_handler(_get_event("deadbeef"), None)

        assert response["statusCode"] == 302
        assert "404.html" in response["headers"]["Location"]

    def test_multiple_urls_all_retrievable(self, full_stack):
        """Store several URLs and confirm each one redirects correctly."""
        urls = [
            "https://example.com",
            "https://openai.com",
            "https://github.com/features",
        ]

        hash_map = {}
        for url in urls:
            resp = full_stack.lambda_handler(_post_event(url), None)
            assert resp["statusCode"] == 200
            hash_map[json.loads(resp["body"])["tinyurl"]] = url

        for hash_key, expected_url in hash_map.items():
            resp = full_stack.lambda_handler(_get_event(hash_key), None)
            assert resp["statusCode"] == 302
            assert resp["headers"]["Location"] == expected_url


class TestInputValidation:
    def test_post_with_no_body_returns_400(self, full_stack):
        response = full_stack.lambda_handler(_post_event(""), None)
        assert response["statusCode"] == 400

    def test_post_with_invalid_url_returns_400(self, full_stack):
        response = full_stack.lambda_handler(_post_event("not-a-url"), None)
        assert response["statusCode"] == 400

    def test_unsupported_method_returns_405(self, full_stack):
        event = {**_post_event("https://example.com"), "httpMethod": "DELETE"}
        response = full_stack.lambda_handler(event, None)
        assert response["statusCode"] == 405
