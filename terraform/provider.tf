terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.0.0"

  # This backend configuration points to the resources created by the bootstrap
  backend "s3" {
    bucket         = "vishwa-devops-project-terraform-state-2025" # <-- UPDATE THIS to match your bucket name
    key            = "devops-project/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "vishwa-devops-project-terraform-locks" # <-- UPDATE THIS to match your table name
  }
}

provider "aws" {
  region = var.aws_region
}