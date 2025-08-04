variable "aws_region" {
  description = "The AWS region for the backend resources."
  type        = string
  # CHANGED: The default region is now us-west-2
  default     = "us-west-2"
}

variable "s3_bucket_name" {
  description = "The unique name for the S3 bucket."
  type        = string
}

variable "dynamodb_table_name" {
  description = "The name for the DynamoDB lock table."
  type        = string
}