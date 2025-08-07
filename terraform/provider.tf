terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.0.0"

  # UPDATED: This backend configuration points to the S3 bucket and DynamoDB table for us-west-2
  backend "s3" {
    bucket         = "vishwa-devops-project-terraform-state-2025-us-west-2" # <-- UPDATED to be unique and specific to the region
    key            = "devops-project/terraform.tfstate"
    region         = "us-west-2" # <-- CHANGED to us-west-2
    encrypt        = true
    dynamodb_table = "vishwa-devops-project-terraform" 
  }
}

provider "aws" {
  region = var.aws_region
}