terraform {
  required_version = ">= 1.5.0"
  required_providers { 
    aws = { 
        source = "hashicorp/aws" 
        version = "~> 5.0" 
        } 
    }
}

provider "aws" { 
    region = var.aws_region 
}

resource "random_id" "suffix" { 
    byte_length = 4 
}

# S3 bucket for remote state
resource "aws_s3_bucket" "tf_state" {
  bucket = "${var.project}-tf-state"
  force_destroy = false
  tags = { 
    Name = "${var.project}-tf-state" 
    }
}

resource "aws_s3_bucket_versioning" "v" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration { 
    status = "Enabled" 
    }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "enc" {
  bucket = aws_s3_bucket.tf_state.id
  rule { 
    apply_server_side_encryption_by_default { 
        sse_algorithm = "AES256" 
        } 
    }
}

resource "aws_s3_bucket_public_access_block" "pab" {
  bucket = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "lc" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    id     = "noncurrent-retention"
    status = "Enabled"
    noncurrent_version_transition { 
        noncurrent_days = 30 
        storage_class = "STANDARD_IA" 
        }
    noncurrent_version_expiration { 
        noncurrent_days = 90 
        }
  }
}

# DynamoDB lock table
resource "aws_dynamodb_table" "tf_lock" {
  name         = "${var.project}-tf-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute { 
    name = "LockID" 
    type = "S" 
    }
  tags = { 
    Name = "${var.project}-tf-locks" 
    }
}
