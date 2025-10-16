locals {
  function_name   = var.extractor_lambda
  tags            = var.tags
  bedrockregion   = "us-east-1"
  contexts3region = "us-east-1"
  accountid       = data.aws_caller_identity.current.account_id
}
