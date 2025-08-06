#!/bin/bash

# Give the application a few seconds to start up and listen on port 80
sleep 15

# Check if the application is running correctly
# The -f flag tells curl to fail silently on server errors (not necessary for this use case, but good practice)
# The -s flag makes curl silent, so it doesn't print progress bars
curl -s localhost:80 | grep "Hello from DevOps"

# If the grep command fails, the script will exit with a non-zero status.
if [ $? -eq 0 ]
then
  echo "Service validation successful."
  exit 0
else
  echo "Service validation failed. Application is not returning expected content."
  exit 1
fi