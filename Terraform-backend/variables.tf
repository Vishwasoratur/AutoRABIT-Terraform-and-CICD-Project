variable "aws_region" {
  description = "The AWS region for the backend resources."
  type        = string
  default     = "us-east-1"
}

variable "s3_bucket_name" {
  description = "The unique name for the S3 bucket."
  type        = string
}

variable "dynamodb_table_name" {
  description = "The name for the DynamoDB lock table."
  type        = string
}