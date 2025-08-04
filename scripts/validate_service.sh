#!/bin/bash
# Check if the application is running correctly
curl localhost:80 | grep "Hello from DevOps"

# If the grep command fails, the script will exit with a non-zero status,
# and CodeDeploy will automatically roll back.
if [ $? -eq 0 ]
then
  echo "Service validation successful."
  exit 0
else
  echo "Service validation failed."
  exit 1
fi