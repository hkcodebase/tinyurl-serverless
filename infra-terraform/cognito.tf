# ─────────────────────────────────────────────────────────────────────────────
# Cognito — tinyurl-serverless
#
# Standalone Cognito setup scoped to this project only.
# Does NOT share infrastructure with snarky-squirrel.
#
# Resources:
#   - User Pool
#   - User Pool Client (for the UI)
#   - User Pool Domain (hosted UI)
#   - Admin group
# ─────────────────────────────────────────────────────────────────────────────

# ── User Pool ─────────────────────────────────────────────────────────────────
resource "aws_cognito_user_pool" "tinyurl" {
  name = "${var.project_name}-user-pool"

  # Allow users to sign in with email
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Password policy
  password_policy {
    minimum_length                   = 8
    require_uppercase                = true
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  # Email verification
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your verification code for links.hemantkumar.dev"
    email_message        = "Your verification code is {####}"
  }

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Self sign-up disabled — invite only via admin
  admin_create_user_config {
    allow_admin_create_user_only = true
    invite_message_template {
      email_subject = "Your links.hemantkumar.dev invite"
      email_message = "You have been invited to links.hemantkumar.dev. Your username is {username} and temporary password is {####}"
      sms_message   = "Your username is {username} and temporary password is {####}"
    }
  }

  tags = {
    Project = var.project_name
  }
}

# ── User Pool Client ──────────────────────────────────────────────────────────
resource "aws_cognito_user_pool_client" "tinyurl_ui" {
  name         = "${var.project_name}-ui-client"
  user_pool_id = aws_cognito_user_pool.tinyurl.id

  # No client secret — public SPA client
  generate_secret = false

  # Auth flows
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
  ]

  # Token validity
  access_token_validity  = 1   # hours
  id_token_validity      = 1   # hours
  refresh_token_validity = 30  # days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Hosted UI callback URLs
  callback_urls = [
    "https://${var.ui_domain_name}",
    "https://${var.ui_domain_name}/callback",
  ]

  logout_urls = [
    "https://${var.ui_domain_name}",
  ]

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  allowed_oauth_flows_user_pool_client = true
  supported_identity_providers         = ["COGNITO"]

  # Prevent user existence errors leaking
  prevent_user_existence_errors = "ENABLED"
}

# ── User Pool Domain (hosted UI) ──────────────────────────────────────────────
resource "aws_cognito_user_pool_domain" "tinyurl" {
  domain       = "${var.project_name}-auth"   # → <project_name>-auth.auth.us-east-1.amazoncognito.com
  user_pool_id = aws_cognito_user_pool.tinyurl.id
}

# ── Admin group ───────────────────────────────────────────────────────────────
resource "aws_cognito_user_group" "admin" {
  name         = "admin"
  user_pool_id = aws_cognito_user_pool.tinyurl.id
  description  = "Admin users — access to /admin/stats endpoint"
}

# ─────────────────────────────────────────────────────────────────────────────
# Outputs — used by Lambda env vars and GitHub Actions secrets
# ─────────────────────────────────────────────────────────────────────────────
output "cognito_user_pool_id" {
  description = "Cognito User Pool ID — set as COGNITO_USER_POOL_ID Lambda env var"
  value       = aws_cognito_user_pool.tinyurl.id
}

output "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.tinyurl.arn
}

output "cognito_client_id" {
  description = "Cognito App Client ID — used by the UI to authenticate"
  value       = aws_cognito_user_pool_client.tinyurl_ui.id
}

output "cognito_hosted_ui_url" {
  description = "Cognito Hosted UI login URL"
  value       = "https://${aws_cognito_user_pool_domain.tinyurl.domain}.auth.${var.region}.amazoncognito.com/login?client_id=${aws_cognito_user_pool_client.tinyurl_ui.id}&response_type=code&scope=email+openid+profile&redirect_uri=https://${var.ui_domain_name}/callback"
}
