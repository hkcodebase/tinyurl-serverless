"""
Unit tests for dynamodb_service.py.
Uses moto to intercept boto3 calls — no real AWS needed.
"""

import pytest
import boto3
from moto import mock_aws

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../.."))


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def aws_credentials(monkeypatch):
    """Prevent any accidental real AWS calls by setting dummy credentials."""
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_SECURITY_TOKEN", "testing")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")


@pytest.fixture
def dynamodb_table():
    """
    Spin up a mocked DynamoDB table before each test and tear it down after.
    The table schema must match what dynamodb_service.py expects:
      - Table name : "Url"
      - Partition key: "hash" (String)
    """
    with mock_aws():
        client = boto3.client("dynamodb", region_name="us-east-1")
        client.create_table(
            TableName="Url",
            KeySchema=[{"AttributeName": "hash", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "hash", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )

        # Re-import the module INSIDE the mock context so its module-level
        # boto3.resource() call is intercepted by moto.
        import importlib
        import dynamodb_service
        importlib.reload(dynamodb_service)

        yield dynamodb_service


# ---------------------------------------------------------------------------
# _generate_hash (pure function — no AWS needed)
# ---------------------------------------------------------------------------

class TestGenerateHash:
    def test_known_url_produces_expected_hash(self):
        # SHA-256("https://example.com")[:8] == "a379a6f6"
        import dynamodb_service as ds
        assert ds._generate_hash("https://example.com") == "a379a6f6"

    def test_same_url_always_same_hash(self):
        import dynamodb_service as ds
        h1 = ds._generate_hash("https://example.com")
        h2 = ds._generate_hash("https://example.com")
        assert h1 == h2

    def test_different_urls_different_hashes(self):
        import dynamodb_service as ds
        assert ds._generate_hash("https://a.com") != ds._generate_hash("https://b.com")

    def test_hash_is_8_chars(self):
        import dynamodb_service as ds
        assert len(ds._generate_hash("https://example.com")) == 8


# ---------------------------------------------------------------------------
# create_url
# ---------------------------------------------------------------------------

class TestCreateUrl:
    def test_returns_hash(self, dynamodb_table):
        hash_key = dynamodb_table.create_url("https://example.com")
        assert hash_key == "a379a6f6"

    def test_item_stored_in_table(self, dynamodb_table):
        dynamodb_table.create_url("https://example.com")

        # Read back directly via boto3 to confirm the item is really there
        resource = boto3.resource("dynamodb", region_name="us-east-1")
        table = resource.Table("Url")
        item = table.get_item(Key={"hash": "a379a6f6"}).get("Item")

        assert item is not None
        assert item["redirect_url"] == "https://example.com"

    def test_overwrite_same_url(self, dynamodb_table):
        # Calling create_url twice with the same URL should not raise
        h1 = dynamodb_table.create_url("https://example.com")
        h2 = dynamodb_table.create_url("https://example.com")
        assert h1 == h2


# ---------------------------------------------------------------------------
# get_redirect_url
# ---------------------------------------------------------------------------

class TestGetRedirectUrl:
    def test_returns_url_for_known_hash(self, dynamodb_table):
        dynamodb_table.create_url("https://example.com")
        result = dynamodb_table.get_redirect_url("a379a6f6")
        assert result == "https://example.com"

    def test_returns_empty_string_for_unknown_hash(self, dynamodb_table):
        result = dynamodb_table.get_redirect_url("deadbeef")
        assert result == ""

    def test_round_trip(self, dynamodb_table):
        """create_url then get_redirect_url should return the original URL."""
        url = "https://openai.com/blog/chatgpt"
        hash_key = dynamodb_table.create_url(url)
        assert dynamodb_table.get_redirect_url(hash_key) == url
