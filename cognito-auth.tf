# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = var.cognito_domain_name
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = var.user_pool_name

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = var.app_client_name
  user_pool_id = aws_cognito_user_pool.user_pool.id

  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = false
  
  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30
  
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  supported_identity_providers = ["COGNITO"]
  explicit_auth_flows = ["USER_PASSWORD_AUTH"]
}


# API Gateway Authorizer
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
  identity_source = "method.request.header.Authorization"
}

resource "aws_wafv2_web_acl_association" "cognito_waf" {
  resource_arn = aws_cognito_user_pool.user_pool.arn
  web_acl_arn  = aws_wafv2_web_acl.waf.arn
}



