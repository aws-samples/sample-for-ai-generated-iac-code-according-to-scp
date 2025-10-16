
# Outputs
output "user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "cognito_domain" {
  value = "https://${aws_cognito_user_pool_domain.user_pool_domain.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
}

output "cognito_domain_cloudfront" {
  value = aws_cognito_user_pool_domain.user_pool_domain.cloudfront_distribution_arn
}

output "api_gateway_stage_invoke_url" {

  value       = aws_api_gateway_stage.stage.invoke_url
}