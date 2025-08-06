#!/bin/bash

# Define the ECR repository URI directly
ECR_REPO_URI="058264310461.dkr.ecr.us-west-2.amazonaws.com/devops-project-repo"

# Stop and remove old containers to ensure idempotency
docker stop hello-app || true
docker rm hello-app || true

# Get the latest image from ECR
docker pull $ECR_REPO_URI:latest

# Run the new container
docker run -d --name hello-app -p 80:80 $ECR_REPO_URI:latest