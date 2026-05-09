"""
Unit tests for handler.py.
DynamoDB calls are mocked so no AWS credentials or network are needed.
"""

import json
import pytest
from unittest.mock import patch

# Add lambda-python root to path so handler/dynamodb_service can be imported
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../.."))

import handler


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_event(method="GET", path="/", body="", host="api.example.com", stage="prod"):
    """Build a minimal API Gateway proxy event."""
    return {
        "httpMethod": method,
        "path": path,
        "body": body,
        "headers": {"Host": host},
        "requestContext": {"stage": stage},
    }


# ---------------------------------------------------------------------------
# _is_valid_url
# ---------------------------------------------------------------------------

class TestIsValidUrl:
    def test_valid_https(self):
        assert handler._is_valid_url("https://example.com") is True

    def test_valid_http(self):
        assert handler._is_valid_url("http://example.com/path?q=1") is True

    def test_valid_with_path_and_query(self):
        assert handler._is_valid_url("https://example.com/a/b?x=1&y=2") is True

    def test_missing_scheme(self):
        assert handler._is_valid_url("example.com") is False

    def test_ftp_scheme_rejected(self):
        assert handler._is_valid_url("ftp://example.com") is False

    def test_empty_string(self):
        assert handler._is_valid_url("") is False

    def test_trailing_slash(self):
        # Trailing slash ends with "/" which is in the allowed set
        assert handler._is_valid_url("https://example.com/") is True


# ---------------------------------------------------------------------------
# POST — create short URL
# ---------------------------------------------------------------------------

class TestHandleCreateShortUrl:
    def test_valid_url_returns_200_with_hash(self):
        event = _make_event(method="POST", body="https://example.com")

        # Mock create_url so no DynamoDB call is made
        with patch("handler.dynamodb_service.create_url", return_value="a379a6f6"):
            response = handler.lambda_handler(event, None)

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert body["tinyurl"] == "a379a6f6"

    def test_empty_body_returns_400(self):
        event = _make_event(method="POST", body="")
        response = handler.lambda_handler(event, None)

        assert response["statusCode"] == 400
        assert "Missing URL" in response["body"]

    def test_invalid_url_returns_400(self):
        event = _make_event(method="POST", body="not-a-url")
        response = handler.lambda_handler(event, None)

        assert response["statusCode"] == 400
        assert "Invalid URL" in response["body"]

    def test_response_has_cors_headers(self):
        event = _make_event(method="POST", body="https://example.com")

        with patch("handler.dynamodb_service.create_url", return_value="a379a6f6"):
            response = handler.lambda_handler(event, None)

        assert response["headers"]["Access-Control-Allow-Origin"] == "*"

    def test_dynamodb_error_returns_500(self):
        event = _make_event(method="POST", body="https://example.com")

        with patch("handler.dynamodb_service.create_url", side_effect=Exception("DB down")):
            response = handler.lambda_handler(event, None)

        assert response["statusCode"] == 500


# ---------------------------------------------------------------------------
# GET — redirect to original URL
# ---------------------------------------------------------------------------

class TestHandleRedirect:
    def test_known_hash_returns_302(self):
        event = _make_event(method="GET", path="/a379a6f6")

        with patch("handler.dynamodb_service.get_redirect_url", return_value="https://example.com"):
            response = handler.lambda_handler(event, None)

        assert response["statusCode"] == 302
        assert response["headers"]["Location"] == "https://example.com"

    def test_unknown_hash_redirects_to_404_page(self):
        event = _make_event(method="GET", path="/deadbeef", host="api.example.com", stage="prod")

        with patch("handler.dynamodb_service.get_redirect_url", return_value=""):
            response = handler.lambda_handler(event, None)

        assert response["statusCode"] == 302
        # Location should point at the 404 page
        assert "404.html" in response["headers"]["Location"]
        assert "deadbeef" in response["headers"]["Location"]

    def test_base_url_built_correctly(self):
        # When stage is present the base_url should be "host/stage"
        event = _make_event(method="GET", path="/abc", host="api.example.com", stage="prod")

        with patch("handler.dynamodb_service.get_redirect_url", return_value=""):
            response = handler.lambda_handler(event, None)

        assert "api.example.com/prod" in response["headers"]["Location"]

    def test_base_url_without_stage(self):
        event = {
            "httpMethod": "GET",
            "path": "/abc",
            "body": "",
            "headers": {"Host": "api.example.com"},
            "requestContext": {},  # no stage key
        }

        with patch("handler.dynamodb_service.get_redirect_url", return_value=""):
            response = handler.lambda_handler(event, None)

        # base_url should just be "api.example.com" (no trailing slash or stage)
        location = response["headers"]["Location"]
        assert location.startswith("api.example.com/")


# ---------------------------------------------------------------------------
# Unsupported methods
# ---------------------------------------------------------------------------

class TestUnsupportedMethods:
    @pytest.mark.parametrize("method", ["PUT", "DELETE", "PATCH"])
    def test_returns_405(self, method):
        event = _make_event(method=method)
        response = handler.lambda_handler(event, None)
        assert response["statusCode"] == 405
