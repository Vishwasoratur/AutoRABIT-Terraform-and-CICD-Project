#!/bin/bash

# Define the ECR repository URI directly
# Replace this with your actual ECR URI, which is provided in the CodeBuild environment variable
ECR_REPO_URI="058264310461.dkr.ecr.us-west-2.amazonaws.com/devops-project-repo"

# Login to ECR
# This command is crucial for pulling images from a private ECR repository.
# It uses the IAM role permissions on the EC2 instance to get a temporary token.
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin $ECR_REPO_URI

# Stop and remove old containers to ensure idempotency
docker stop hello-app || true
docker rm hello-app || true

# Pull the latest image from ECR
docker pull $ECR_REPO_URI:latest

# Run the new container
# The -d flag runs the container in detached mode.
# The -p flag maps port 80 on the host to port 80 in the container.
# The --name flag gives the container a friendly name.
docker run -d -p 80:80 --name hello-app $ECR_REPO_URI:latest