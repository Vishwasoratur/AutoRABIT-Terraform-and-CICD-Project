# Define the AWS provider for this bootstrap configuration
provider "aws" {
  region = var.aws_region
}

# Resource for the S3 bucket to store Terraform state files (basic bucket creation)
resource "aws_s3_bucket" "terraform_state_bucket" {
  bucket = var.s3_bucket_name

  tags = {
    Name        = "TerraformStateBucket"
    Environment = "BackendBootstrap"
    ManagedBy   = "Terraform"
  }
}

# New: Resource to enforce bucket ownership, which disables ACLs
resource "aws_s3_bucket_ownership_controls" "terraform_state_bucket_ownership" {
  bucket = aws_s3_bucket.terraform_state_bucket.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Separate resource to enable S3 bucket versioning
resource "aws_s3_bucket_versioning" "terraform_state_bucket_versioning" {
  bucket = aws_s3_bucket.terraform_state_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Separate resource to enable S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_bucket_encryption" {
  bucket = aws_s3_bucket.terraform_state_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Resource for the DynamoDB table to handle Terraform state locking
resource "aws_dynamodb_table" "terraform_locks_table" {
  name           = var.dynamodb_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "TerraformLockTable"
    Environment = "BackendBootstrap"
    ManagedBy   = "Terraform"
  }
}