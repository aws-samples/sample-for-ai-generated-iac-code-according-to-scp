variable "region" {
  type        = string
  description = "AWS Region"
  default     = "us-east-1"
}

variable "replicationregion" {
  type        = string
  description = "AWS Region"
  default     = "us-west-1"
}


variable "env" {
  type        = string
  default     = "dev"
  description = "Name of the environment, will be used as prefix in resources names"
}

variable "project_name" {
  type        = string
  description = "Name of the project, will be used as prefix in resources names"
  default     = "hackathon"
}

variable "tags" {
  type        = map(any)
  description = "Tags for infrastructure resources."
  default     = { "test1" : "value1", "test2" : "value2" }
}

variable "cw_log_name" {
  type        = string
  description = "cloud watch group name for waf logging"
  default     = "aws-waf-logs-waf-logging"
}

variable "waf_name" {
  type        = string
  description = "waf name"
  default     = "web-acl-association-scp-api"
}

variable "vpc_id" {
  type        = string
  description = "VPC id"

}

variable "pvt_subnet" {
  type        = string
  description = "private subnet for vpc"

}
variable "route_table_id" {
  type        = string
  description = "route table id for private subnet"

}

variable "kms_key_arn" {
  description = "ARN of KMS key for CloudWatch Log Group encryption"
  type        = string
 
}
variable "key" {
  description = "s3 key"
  type        = string

}
variable "s3_bucket" {
  description = "s3 bucket"
  type        = string

}

variable "name_of_lambda" {
  type        = string
  default     = "bedrock_main"
  description = "Name of the lambda for bedrock connect"
}


variable "extractor_lambda" {
  type        = string
  default     = "scp_lambda_extractor"
  description = "Name of the lambda for the context generation"
}

variable "lambdarole" {
  type        = string
  default     = "scp_lambda_role_extractor"
  description = "Custom name for lambda role"
}

variable "policyforendpoint" {
  type        = string
  default     = "scp_lambda_policy_ex"
  description = "EC2 end point policy custom name"
}
variable "policyfornova" {
  type        = string
  default     = "nova_lambda_policy"
  description = "Nova policy for lambda"
}

variable "contexts3" {
  description = "s3 bucket where the context of scp would be saved"
  type        = string
}

