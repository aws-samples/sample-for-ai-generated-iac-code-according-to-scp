terraform {
  backend "s3" {
    bucket       = "<S3 bucket to save terraform state file>"
    key          = "terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # Enable S3 native locking
  }
}
