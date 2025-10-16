provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Environment = "Dev"
      Owner       = "DevSecOps"
      Project     = "SCPAI"
      Name        = "SCPAI"
    }
  }


}


provider "aws" {
  alias  = "central"
  region = var.replicationregion

  default_tags {
    tags = {
      Environment = "Dev"
      Owner       = "DevSecOps"
      Project     = "SCPAI"
      Name        = "SCPAI"
    }
  }

}


data "aws_vpc" "selected" {
  id = var.vpc_id
}


resource "aws_security_group" "lambda_security_group"{
  vpc_id = var.vpc_id
  description = "Security group for the lambda functions inside the vpc"
  revoke_rules_on_delete = true
  # Allow inbound access within VPC
  ingress {
    description = "allow inbound access within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }
  
  # DNS resolution
  egress {
    description = "DNS resolution"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }
  
  # HTTPS access to S3 VPC endpoint
  egress {
    description = "S3 VPC endpoint access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3_endpoint.prefix_list_id]  # S3 prefix list
  }
  
  # HTTPS access to Bedrock VPC endpoints
  egress {
    description = "Bedrock VPC endpoints access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]  
  }
  # DynamoDB VPC endpoint access
  egress {
    description = "DynamoDB VPC endpoint access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.dynamodb_endpoint.prefix_list_id]
  }
  
  tags = {
    Name = "lambda-security-group"
    Environment = "Dev"
    Owner = "DevSecOps"
  }

}


resource "aws_security_group" "vpc_endpoint_security_group" {
  vpc_id = var.vpc_id
  description = "Security group for VPC endpoints"
  
  # Allow HTTPS inbound from Lambda security group
  ingress {
    description = "HTTPS from Lambda"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }
  
  tags = {
    Name = "vpc-endpoint-security-group"
    Environment = "Dev"
    Owner = "DevSecOps"
  }
}

# Security group rules are now defined directly in the security groups above



resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id      = var.vpc_id
  service_name = "com.amazonaws.${var.region}.s3"
  route_table_ids = [var.route_table_id]
}

resource "aws_vpc_endpoint" "bedrock_endpoint" { 
  vpc_id          = var.vpc_id
  service_name    = "com.amazonaws.${var.region}.bedrock"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpc_endpoint_security_group.id]
  subnet_ids          = [var.pvt_subnet] 
}

# Add KMS VPC endpoint for Lambda to decrypt environment variables
resource "aws_vpc_endpoint" "kms_endpoint" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.kms"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpc_endpoint_security_group.id]
  subnet_ids          = [var.pvt_subnet]
  
  tags = {
    Name = "kms-vpc-endpoint"
  }
}


# Add Bedrock Runtime VPC endpoint (separate from Bedrock control plane)
resource "aws_vpc_endpoint" "bedrock_runtime_endpoint" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpc_endpoint_security_group.id]
  subnet_ids          = [var.pvt_subnet]
  
  tags = {
    Name = "bedrock-runtime-vpc-endpoint"
  }
}

resource "aws_cloudwatch_event_rule" "console" {
  name        = "${local.function_name}-capture-cw-logs-creation"
  description = "Capture specific log grop creation"
  force_destroy = true

  event_pattern = jsonencode({

    "detail" : {
      "eventName" : ["CreatePolicy"],
      "eventSource" : ["organizations.amazonaws.com"],
      "requestParameters" : {
        "type" : ["SERVICE_CONTROL_POLICY"]
      },
      "responseElements": {
      "policy": {
        "policySummary": {
          "type": ["SERVICE_CONTROL_POLICY"]
        }
      }
    }
    
  }
 
})
}

resource "aws_cloudwatch_event_rule" "deletepolicy" {
  name        = "delete-policy-rule"
  description = "Capture specific delete policy creation event"
  force_destroy = true

  event_pattern = jsonencode({
    "detail": {
      "eventName": ["DeletePolicy"],
      "eventSource": ["organizations.amazonaws.com"]
    }
  })
  
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.console.name
  target_id = "SendToLambda"
  arn       = aws_lambda_function.log_tag_lambda.arn
}
resource "aws_cloudwatch_event_target" "deletepol" {
  rule      = aws_cloudwatch_event_rule.deletepolicy.name
  target_id = "SendToLambda"
  arn       = aws_lambda_function.log_tag_lambda.arn
}


resource "aws_lambda_permission" "allow_eventbridge_to_call" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.log_tag_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.console.arn
}
resource "aws_lambda_permission" "allow_eventbridge_delete_policy" {
  statement_id  = "AllowExecutionFromCloudWatchDeletePolicy"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.log_tag_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.deletepolicy.arn
}
resource "aws_api_gateway_rest_api" "api" {
  name = "scp-lambda-api"
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_api_gateway_request_validator" "validator" {
  name                        = "api-validator"
  rest_api_id                 = aws_api_gateway_rest_api.api.id
  validate_request_body       = true
  validate_request_parameters = true
}
resource "aws_api_gateway_model" "request_model" {
  rest_api_id  = aws_api_gateway_rest_api.api.id
  name         = "model"
  description  = "JSON schema for API validation"
  content_type = "application/json"
  schema = jsonencode({
    type = "object"
    properties = {
      # Modify according to your API requirements
      requestData = { type = "string" }
    }
    required = ["requestData"]
  })
}

resource "aws_api_gateway_resource" "resource" {
  path_part   = "resource"
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api.id
}


# POST Method with Cognito Auth
resource "aws_api_gateway_method" "method" {
  rest_api_id          = aws_api_gateway_rest_api.api.id
  resource_id          = aws_api_gateway_resource.resource.id
  http_method          = "POST"
  authorization        = "COGNITO_USER_POOLS"
  authorizer_id        = aws_api_gateway_authorizer.cognito_authorizer.id
  request_validator_id = aws_api_gateway_request_validator.validator.id

  request_models = {
    "application/json" = aws_api_gateway_model.request_model.name
  }
}



resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.method.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.bedrock_lambda.invoke_arn
  passthrough_behavior    = "WHEN_NO_TEMPLATES"
  content_handling        = "CONVERT_TO_TEXT"
  timeout_milliseconds    = 29000  # Maximum API Gateway timeout
  depends_on = [
    aws_api_gateway_method.method
  ]
}


resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bedrock_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/${aws_api_gateway_method.method.http_method}${aws_api_gateway_resource.resource.path}"
}

resource "aws_api_gateway_client_certificate" "client_cert" {
  description = "Client certificate for API Gateway"
}
# Create IAM role for API Gateway CloudWatch logging
resource "aws_iam_role" "apigateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "api_to_cloudwatch" {
  name   = "APIGatewayPushToCloudWatchLogs"
  policy = templatefile("templates/api_to_cloudwatch.json", {})
}
# Attach the CloudWatch logging policy to the role
resource "aws_iam_role_policy_attachment" "apigateway_cloudwatch_policy" {
  role       = aws_iam_role.apigateway_cloudwatch_role.name
  policy_arn = aws_iam_policy.api_to_cloudwatch.arn
}

# Create API Gateway account settings
resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.apigateway_cloudwatch_role.arn
  depends_on = [
    aws_iam_role_policy_attachment.apigateway_cloudwatch_policy
  ]
}



resource "aws_api_gateway_stage" "stage" {

  #WAF is mentioned and enabled at line 406
  #checkov:skip=CKV2_AWS_77:"log4j is java library, we are not using any java lib, thus this check is not valid for blog's code"
  depends_on = [
    aws_api_gateway_account.main
  ]
  deployment_id         = aws_api_gateway_deployment.deployment.id
  rest_api_id           = aws_api_gateway_rest_api.api.id
  stage_name            = "prod-${formatdate("YYYYMMDD", timestamp())}"
  xray_tracing_enabled  = true
  cache_cluster_enabled = true
  cache_cluster_size    = "0.5"
  client_certificate_id = aws_api_gateway_client_certificate.client_cert.id
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
  format = jsonencode({
    httpMethod              = "$context.httpMethod"
    integrationErrorMessage = "$context.integrationErrorMessage"
    protocol                = "$context.protocol"
    requestId               = "$context.requestId"
    requestTime             = "$context.requestTime"
    resourcePath            = "$context.resourcePath"
    responseLength          = "$context.responseLength"
    routeKey                = "$context.routeKey"
    sourceIp                = "$context.identity.sourceIp"
    status                  = "$context.status"
    integrationLatency      = "$context.integrationLatency"
    responseLatency         = "$context.responseLatency"
    error                   = "$context.error.message"
    integrationStatus       = "$context.integrationStatus"
  })
  }
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "/aws/api-gateway/${aws_api_gateway_rest_api.api.name}"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn
}

resource "aws_cloudwatch_log_group" "waf_lg" {
  name              = var.cw_log_name
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn
}


resource "aws_wafv2_web_acl_logging_configuration" "waf_logging" {
  log_destination_configs = [aws_cloudwatch_log_group.waf_lg.arn]
  resource_arn            = aws_wafv2_web_acl.waf.arn
}


resource "aws_wafv2_web_acl" "waf" {
  #checkov:skip=CKV_AWS_192: "log4j is java library, we are not using any java lib, thus this check is not valid for blog's code"
 
  name  = var.waf_name
  scope = "REGIONAL"

  default_action {
    allow {}
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "metric_waf"
    sampled_requests_enabled   = true
  }
  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }
  rule {
    name     = "AWSManagedRulesAnonymousIpList"
    priority = 2
    override_action {
      count {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAnonymousIpList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesAnonymousIpList"
      sampled_requests_enabled   = true
    }
  }
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 3
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesSQLiRuleSet"
      sampled_requests_enabled   = true
    }
  }
}


# DDoS Protection WAF
resource "aws_wafv2_web_acl" "api_gw_waf" {
  #checkov:skip=CKV_AWS_192: Ensure WAF prevents message lookup in Log4j2. [The code is not java code this there is no Log4j]
  name  = "${var.waf_name}-waf-protection"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "DDoSRateLimitRule"
    priority = 1
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "DDoSRateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "ddos_protection_waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "api_gw_waf" {
  log_destination_configs = [aws_cloudwatch_log_group.waf_lg.arn]
  resource_arn            = aws_wafv2_web_acl.api_gw_waf.arn
}

resource "aws_wafv2_web_acl_association" "api_gw_waf" {
  resource_arn = aws_api_gateway_stage.stage.arn
  web_acl_arn  = aws_wafv2_web_acl.api_gw_waf.arn
  depends_on = [
    aws_api_gateway_stage.stage,
    aws_wafv2_web_acl.api_gw_waf
  ]
}

resource "aws_api_gateway_method_settings" "api_gw_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.stage.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled      = true
    logging_level        = "INFO"
    data_trace_enabled   = true
    caching_enabled      = true
    cache_data_encrypted = true
  }
}

resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.method.http_method
  status_code = "200"
  
  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.method.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code
  selection_pattern = ""  # Match any response from Lambda
  
  # Transform the Lambda response to the API response
  response_templates = {
    "application/json" = ""  # Passthrough the Lambda response
  }
  
  depends_on = [
    aws_api_gateway_method.method,
    aws_api_gateway_integration.integration,
    aws_api_gateway_method_response.response_200
  ]
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.integration,
    aws_api_gateway_integration_response.integration_response
  ]

  rest_api_id = aws_api_gateway_rest_api.api.id
  lifecycle {
    create_before_destroy = true
  }
}
