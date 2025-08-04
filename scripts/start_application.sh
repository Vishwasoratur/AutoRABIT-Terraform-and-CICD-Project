#!/bin/bash
# Stop and remove old containers to ensure idempotency
docker stop hello-app || true
docker rm hello-app || true

# Get the latest image from ECR
ECR_REPO_URI=$(aws ecr describe-repositories --repository-names devops-project-repo --query "repositories[0].repositoryUri" --output text)
docker pull $ECR_REPO_URI:latest

# Run the new container
docker run -d --name hello-app -p 80:80 $ECR_REPO_URI:latest