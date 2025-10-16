


resource "aws_signer_signing_profile" "scp_profile_lambda" {
  name_prefix = "AwsLambdaCodeSigningAction"
  platform_id = "AWSLambda-SHA384-ECDSA"

  signature_validity_period {
    value = 5
    type  = "YEARS"
  }


}

# Optional: Create a Signing Profile Permission
resource "aws_signer_signing_profile_permission" "scp_profile_permission_lambda" {
  profile_name = aws_signer_signing_profile.scp_profile_lambda.name
  action       = "signer:StartSigningJob"
  principal    = aws_iam_role.lamdba_role.arn
}
resource "aws_lambda_code_signing_config" "bedrock_signing_config" {
  description = "Code signing configuration for bedrock lambda"

  allowed_publishers {
    signing_profile_version_arns = [
      aws_signer_signing_profile.scp_profile_lambda.version_arn
    ]
  }

  policies {
    untrusted_artifact_on_deployment = "Warn"
  }
}
resource "aws_lambda_code_signing_config" "extractor_signing_config" {
  description = "Code signing configuration for scp extractor lambda"

  allowed_publishers {
    signing_profile_version_arns = [
      aws_signer_signing_profile.scp_profile_lambda.version_arn
    ]
  }

  policies {
    untrusted_artifact_on_deployment = "Warn"
  }
}
resource "aws_s3_bucket" "genai" {
#checkov:skip=CKV_AWS_144: "Ensure that S3 bucket has cross-region replication enabled" CRR is enabled and s3crr.tf has the code for it
#checkov:skip=CKV2_AWS_62:"Event notifications for S3 doesn't need to enabled for the solution to work"
#checkov:skip=CKV2_AWS_61:"Lifecycle policies in S3 are not required for the solution to work"

#checkov:skip=CKV_AWS_18: "Access logging need not be enabled for our solution"
  bucket = var.contexts3
  object_lock_enabled=true
  
  
}

resource "aws_s3_bucket_public_access_block" "genai" {
  bucket = aws_s3_bucket.genai.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}



resource "aws_s3_bucket_policy" "https_only_policy" {
  bucket = aws_s3_bucket.genai.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.genai.id}",
          "arn:aws:s3:::${aws_s3_bucket.genai.id}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
resource "aws_s3_bucket_server_side_encryption_configuration" "s3_encryption" {
  #checkov:skip=CKV2_AWS_67:"Not applicable as we are taking the KMS key as a input from the user and assuming the key has rotation enabled"
  bucket = aws_s3_bucket.genai.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_object" "lambda_code" {
  bucket     = aws_s3_bucket.genai.bucket
  key        = var.key
  source     = data.archive_file.python_lambda_package.output_path
  etag       = filemd5(data.archive_file.python_lambda_package.output_path)
  depends_on = [aws_s3_bucket_versioning.bucket_versioning]
}

resource "aws_s3_object" "lambda_code_bedrock" {
  bucket     = aws_s3_bucket.genai.bucket
  key        = "lambda/bedrock_lambda.zip"
  source     = data.archive_file.python_lambda_package_bedrock.output_path
  etag       = filemd5(data.archive_file.python_lambda_package_bedrock.output_path)
  depends_on = [aws_s3_bucket_versioning.bucket_versioning]
}


resource "aws_s3_bucket_versioning" "bucket_versioning" {
  bucket = aws_s3_bucket.genai.bucket
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_signer_signing_job" "sign_lambda_code" {
  profile_name = aws_signer_signing_profile.scp_profile_lambda.name

  source {
    s3 {
      bucket  = aws_s3_bucket.genai.bucket
      key     = var.key
      version = aws_s3_object.lambda_code.version_id != "" ? aws_s3_object.lambda_code.version_id : null
    }
  }

  destination {
    s3 {
      bucket =aws_s3_bucket.genai.bucket
      prefix = "${var.key}-signed"
    }
  }
  depends_on = [aws_s3_object.lambda_code, aws_s3_bucket_versioning.bucket_versioning]
}
data "archive_file" "python_lambda_package" {
  type        = "zip"
  source_file = "lambda/scp_lambda_extractor.py"
  output_path = "lambda/scp_lambda.zip" # Updated path
}

data "archive_file" "python_lambda_package_bedrock" {
  type        = "zip"
  source_file = "lambda/bedrock.py"
  output_path = "lambda/bedrock_lambda.zip" # Updated path
}

resource "aws_iam_role" "lamdba_role" {
  name = var.lambdarole
  #managed_policy_arns = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/service-role/AWSLambdaBasicExecutionRole", aws_iam_policy.ec2_policy_for_endpoint.arn]
  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}
resource "aws_iam_policy" "lambda_basic_policy" {
  name   = "LambdaBasicExecPolicy"
  policy = templatefile("templates/LambdaBasicExecutionPolicy.json",{})
}

resource "aws_iam_role_policy_attachment" "lambda_basic_policy" {
  #count      = length(var.policy_arns)
  role       = aws_iam_role.lamdba_role.name
  policy_arn =aws_iam_policy.lambda_basic_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_basic_policy_ec2" {

  role       = aws_iam_role.lamdba_role.name
  policy_arn = aws_iam_policy.ec2_policy_for_endpoint.arn

}

resource "aws_iam_role_policy_attachment" "lambda_vpc_execution_policy" {
  role       = aws_iam_role.lamdba_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_policy" "ec2_policy_for_endpoint" {
  name   = var.policyforendpoint
  policy = templatefile("templates/lambda_policy.json", {
    contexts3    = var.contexts3
  })
}
resource "aws_iam_role_policy_attachment" "lambda_nova_policy" {

  role       = aws_iam_role.lamdba_role.name
  policy_arn = aws_iam_policy.nova_policy.arn

}

resource "aws_iam_policy" "nova_policy" {
  name   = var.policyfornova
  policy = templatefile("templates/nova_policy.json", {
    accountid = local.accountid
  })
}


resource "aws_lambda_function" "log_tag_lambda" {
  #checkov:skip=CKV_AWS_116: "Our solution doesn't require DLQ enabled in the lambda"
  # If the file is not in the current working directory you will need to include a
  # path.module in the filename.
  #checkov:skip=CKV_AWS_173: "Encryption for environment variable not needed for our solution"
  # Not required
  #filename      = "lambda.zip"
  function_name = var.extractor_lambda
  role          = aws_iam_role.lamdba_role.arn
  s3_bucket     = aws_s3_bucket.genai.bucket
  s3_key        = var.key
  handler       = "scp_lambda_extractor.lambda_handler"

  timeout = 180
  runtime = "python3.13"
  tracing_config {

    mode = "Active"
  }
  vpc_config {
    security_group_ids = [aws_security_group.lambda_security_group.id]
    subnet_ids         = [var.pvt_subnet]
  }
  code_signing_config_arn        = aws_lambda_code_signing_config.extractor_signing_config.arn
  publish                        = true
  reserved_concurrent_executions = 2
  environment {
    variables = {
      contexts3region    = local.contexts3region != "" ? local.contexts3region : data.aws_region.current.region
      s3bucketforcontext = aws_s3_bucket.genai.bucket
    }
  }
  kms_key_arn = var.kms_key_arn
  depends_on = [aws_signer_signing_job.sign_lambda_code]
}

resource "null_resource" "lambda_code_update" {
  depends_on = [
    aws_lambda_function.log_tag_lambda,
    aws_lambda_function.bedrock_lambda
  ]

  provisioner "local-exec" {
    command = <<-EOF
      aws lambda update-function-code --function-name ${aws_lambda_function.log_tag_lambda.function_name} --s3-bucket ${aws_s3_bucket.genai.bucket} --s3-key lambda/scp_lambda.zip --region ${data.aws_region.current.name}
      aws lambda update-function-code --function-name ${aws_lambda_function.bedrock_lambda.function_name} --s3-bucket ${aws_s3_bucket.genai.bucket} --s3-key lambda/bedrock_lambda.zip --region ${data.aws_region.current.name}
    EOF
  }

  lifecycle {
    replace_triggered_by = [
      aws_s3_object.lambda_code,
      aws_s3_object.lambda_code_bedrock
    ]
  }
}

# Bedrock Guardrail
resource "aws_bedrock_guardrail" "responsible_ai" {
  name                      = "responsible-ai-guardrail"
  description              = "Guardrail for responsible AI implementation"
  blocked_input_messaging  = "This input violates our responsible AI policy."
  blocked_outputs_messaging = "This output violates our responsible AI policy."

  # Content Policy Configuration
  content_policy_config {
    filters_config {
      type = "SEXUAL"
      input_strength = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type = "VIOLENCE"
      input_strength = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type = "HATE"
      input_strength = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type = "INSULTS"
      input_strength = "MEDIUM"
      output_strength = "MEDIUM"
    }
    filters_config {
      type = "MISCONDUCT"
      input_strength = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type = "PROMPT_ATTACK"
      input_strength = "HIGH"
      output_strength = "NONE"
    }
  }

  # Topic Policy Configuration
  topic_policy_config {
    topics_config {
      name = "financial-advice"
      definition = "Investment advice, financial planning, or trading recommendations"
      examples = [
        "Should I invest in cryptocurrency?",
        "What stocks should I buy?",
        "How should I manage my retirement portfolio?"
      ]
      type = "DENY"
    }
    topics_config {
      name = "medical-diagnosis"
      definition = "Medical diagnosis, treatment recommendations, or health advice"
      examples = [
        "What medication should I take?",
        "Do I have a medical condition?",
        "How should I treat my symptoms?"
      ]
      type = "DENY"
    }
  }

  # Word Policy Configuration
  word_policy_config {
    managed_word_lists_config {
      type = "PROFANITY"
    }
    words_config {
      text = "confidential"
    }
    words_config {
      text = "proprietary"
    }
  }

  # Sensitive Information Policy
  sensitive_information_policy_config {
    pii_entities_config {
      type = "EMAIL"
      action = "BLOCK"
    }
    pii_entities_config {
      type = "PHONE"
      action = "BLOCK"
    }
    pii_entities_config {
      type = "ADDRESS"
      action = "BLOCK"
    }
    pii_entities_config {
      type = "CREDIT_DEBIT_CARD_NUMBER"
      action = "BLOCK"
    }
  }

  tags = {
    Environment = "production"
    Purpose     = "responsible-ai"
    Compliance  = "required"
  }
}

# Bedrock Guardrail Version
resource "aws_bedrock_guardrail_version" "responsible_ai_v1" {
  guardrail_arn = aws_bedrock_guardrail.responsible_ai.guardrail_arn
  description         = "Version 1 of responsible AI guardrail"
}




resource "aws_lambda_function" "bedrock_lambda" {
  #checkov:skip=CKV_AWS_116: "Our solution doesn't require DLQ enabled in the lambda"
  # If the file is not in the current working directory you will need to include a
  # path.module in the filename.
  #checkov:skip=CKV_AWS_173: "Encryption for environment variable not needed for our solution"
  # Not required
  s3_bucket     = aws_s3_bucket.genai.bucket
  s3_key        = aws_s3_object.lambda_code_bedrock.key
  function_name = var.name_of_lambda
  role          = aws_iam_role.lamdba_role.arn

  handler = "bedrock.lambda_handler"

  timeout = 180  # Maximum for API Gateway integration
  runtime = "python3.13"
  memory_size = 512  # Increased for better performance
  tracing_config {
    mode = "Active"
  }
  vpc_config {
    security_group_ids = [aws_security_group.lambda_security_group.id]
    subnet_ids         = [var.pvt_subnet]
  }
  code_signing_config_arn        = aws_lambda_code_signing_config.bedrock_signing_config.arn
  reserved_concurrent_executions = 2

  environment {
    variables = {
      GUARDRAIL_ID = aws_bedrock_guardrail.responsible_ai.guardrail_id
      GUARDRAIL_VERSION = aws_bedrock_guardrail_version.responsible_ai_v1.version
      bedrockregion      = local.bedrockregion != "" ? local.bedrockregion : data.aws_region.current.name
      contexts3region    = local.contexts3region != "" ? local.contexts3region : data.aws_region.current.name
      s3bucketforcontext = aws_s3_bucket.genai.bucket
    }
  }
  kms_key_arn = var.kms_key_arn

  depends_on = [aws_s3_object.lambda_code_bedrock]
}
