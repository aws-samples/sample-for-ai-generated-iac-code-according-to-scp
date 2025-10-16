resource "random_id" "bucket_suffix" {
  byte_length = 2
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}


resource "aws_iam_role" "replication" {
  name               = "tf-iam-role-replication-${random_id.bucket_suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "replication" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]

    resources = [aws_s3_bucket.genai.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]

    resources = ["${aws_s3_bucket.genai.arn}/*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]

    resources = ["${aws_s3_bucket.destination.arn}/*"]
  }
}

resource "aws_iam_policy" "replication" {
  name   = "tf-iam-role-policy-replication-${random_id.bucket_suffix.hex}"
  policy = data.aws_iam_policy_document.replication.json
}

resource "aws_iam_role_policy_attachment" "replication" {
  role       = aws_iam_role.replication.name
  policy_arn = aws_iam_policy.replication.arn
}

resource "aws_s3_bucket" "destination" {
  #checkov:skip=CKV2_AWS_62:"Event notifications for S3 doesn't need to enabled for the solution to work"
  #checkov:skip=CKV_AWS_18: "Access logging need not be enabled for our solution"
  #checkov:skip=CKV2_AWS_61:"Lifecycle policies in S3 are not required for the solution to work"
  bucket = "tf-geniai-bucket-destination-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_versioning" "destination" {
  #checkov:skip=CKV_AWS_21:"Versioning is required for cross-region replication"
  bucket = aws_s3_bucket.destination.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "dest_bucket" {
  bucket = aws_s3_bucket.destination.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "s3_encryption_dest" {
  #checkov:skip=CKV2_AWS_67:"Not applicable as we are taking the KMS key as a input from the user and assuming the key has rotation enabled"
  bucket = aws_s3_bucket.destination.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_replication_configuration" "replication" {
  # Remove the provider = aws.central line
  # Must have bucket versioning enabled first
  depends_on = [aws_s3_bucket_versioning.destination]

  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.genai.id

  rule {
    id     = "scprule"
    status = "Enabled"

    filter {
      prefix = ""
    }

    destination {
      bucket        = aws_s3_bucket.destination.arn
      storage_class = "STANDARD"
    }

    delete_marker_replication {
      status = "Enabled"
    }
  }
}