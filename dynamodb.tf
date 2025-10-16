resource "aws_dynamodb_table" "policy_mapping" {
  name           = "SCPPolicyMapping"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "policy_id"

  attribute {
    name = "policy_id"
    type = "S"
  }

  server_side_encryption {
    enabled = true
    kms_key_arn  = var.kms_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }


}
resource "aws_vpc_endpoint" "dynamodb_endpoint" {
  vpc_id          = var.vpc_id
  service_name    = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [var.route_table_id]
  
  tags = {
    Name = "dynamodb-vpc-endpoint"
  }
}