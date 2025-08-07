CI/CD for a Containerized Application on AWS

Project Overview 🚀
This project establishes a comprehensive, production-grade Continuous Integration/Continuous Deployment (CI/CD) pipeline for a containerized web application on AWS. The entire infrastructure is defined as Infrastructure as Code (IaC) using Terraform, ensuring a consistent, version-controlled, and fully automated environment.

The core objective is to showcase a robust DevOps workflow that automatically builds, tests, and deploys application updates with high availability and reliability. The architecture is engineered to be fault-tolerant, scalable, and easily manageable.

Key Architectural Principles
High Availability & Reliability: The infrastructure is deployed across multiple Availability Zones (AZs). The Application Load Balancer (ALB) and Auto Scaling Group (ASG) ensure that the application remains available even if an entire AZ or an individual instance fails.

Automation: The CI/CD pipeline, orchestrated by AWS CodePipeline, is fully automated. A single git push triggers the entire workflow, from code build to deployment, eliminating manual intervention and human error.

Observability: The project is instrumented with CloudWatch Alarms that proactively monitor critical application metrics (e.g., 5xx errors, unhealthy hosts). Container logs are centralized in CloudWatch Log Groups, providing a unified view for troubleshooting.

Idempotency: All deployment scripts are written to be idempotent, meaning they can be run multiple times without causing unintended side effects. For example, docker stop hello-app || true ensures the script continues even if the container doesn't exist.

Infrastructure as Code (IaC): Terraform manages every aspect of the infrastructure, from the VPC to the IAM roles. This provides a single source of truth for the entire environment, making it easy to replicate, modify, and audit.

Prerequisites 🛠️
To set up this production-ready environment, you will need the following:

AWS Account: An account with an IAM user configured with administrative access keys.

AWS CLI: The AWS Command Line Interface must be installed and configured.

GitHub Account: A repository containing the application code, Dockerfile, appspec.yml, and all necessary scripts.

AWS CodeStar Connection: A pre-configured connection to your GitHub repository. The Connection ARN is a required variable.

Terraform CLI: Version 1.7.0 or newer is installed on your local machine to manage the infrastructure.

SSH Key Pair: An EC2 key pair named sandy in the us-west-2 region.

Setup Instructions
1. Clone the Repository
Bash

git clone https://github.com/Vishwasoratur/AutoRABIT-Terraform-and-CICD-Project.git
cd AutoRABIT-Terraform-and-CICD-Project

2. Configure Terraform Backend
Create a terraform-backend directory, create a backend.tf file. This file configures the remote state and state locking, which is essential for a production environment to prevent concurrent state modifications.

Terraform

# terraform/backend.tf
terraform {
  backend "s3" {
    bucket         = "vishwa-devops-project-terraform-state-2025-us-west-2"
    key            = "devops-project/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "vishwa-devops-project-terraform-locks"
    encrypt        = true
  }
}
3. Initialize Terraform
Bash

terraform init
4. Define Project Variables
Create a terraform.tfvars file to pass custom values to your Terraform configuration.

project_name          = "devops-project"
aws_region            = "us-west-2"
github_owner          = "<Your-GitHub-Username>"
github_repo_name      = "<Your-Repository-Name>"
github_branch         = "main"
github_connection_arn = "<Your-CodeStar-Connection-ARN>"
5. Deploy the Infrastructure
Bash

terraform plan
terraform apply --auto-approve
This will provision all the necessary AWS resources, setting up the entire CI/CD pipeline and application environment.

The Deployment Workflow: From Commit to Production
The pipeline is triggered automatically by a git push to the main branch, following these stages:

Source: AWS CodePipeline detects the code change in your GitHub repository and pulls the latest version.

Build: AWS CodeBuild executes the buildspec.yml file. This stage builds the Docker image, pushes it to ECR, and then runs Terraform to update the infrastructure, specifically by updating the aws_launch_template.

Deploy: AWS CodeDeploy takes over. The deployment group targets instances in the ASG using a specific tag (codedeploy-group). It executes the appspec.yml hooks to deploy the new image.

Rollback Strategy 🔄
This project incorporates a robust and automated rollback mechanism, a fundamental principle of reliable deployments.

Automated Rollback
Our pipeline is configured for a zero-touch rollback in case of failure. This is managed by the CodeDeploy Deployment Group. The ValidateService hook is critical here.

Trigger: The validate_service.sh script performs a health check on the newly deployed container. If this script fails (exits with a non-zero status), it signals a deployment failure.

Action: CodeDeploy, configured with auto_rollback_configuration, automatically detects this failure and immediately stops the deployment. It then reverts all changes on the instances, restoring them to the last known working version of the application.

Manual Rollback
For more complex issues, a manual rollback can be performed:

Navigate to the AWS CodeDeploy service in the console.

Select the Deployment Group.

From the deployment history, select a previous, successful deployment.

Initiate a Redeploy action to revert the application to that specific version.

This two-pronged approach ensures that a faulty deployment can never take the application offline for an extended period.
