variable "aws_region" {
  description = "The AWS region to create resources in."
  type        = string
  # CHANGED: The default region is now us-west-2
  default     = "us-west-2"
}

variable "project_name" {
  description = "A unique name for the project to be used in resource naming."
  type        = string
  default     = "devops-project"
}

variable "github_owner" {
  description = "The owner of the GitHub repository."
  type        = string
}

variable "github_repo_name" {
  description = "The name of the GitHub repository."
  type        = string
}

variable "github_branch" {
  description = "The branch to monitor for CI/CD pipeline triggers."
  type        = string
  default     = "main"
}

variable "github_connection_arn" {
  description = "The ARN of the CodeStarSourceConnection to GitHub."
  type        = string
}