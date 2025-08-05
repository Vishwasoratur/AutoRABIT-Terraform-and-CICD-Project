# Use a lightweight Python image as a base
FROM public.ecr.aws/docker/library/python:3.9-slim

# Set the working directory in the container
WORKDIR /app

# Copy the requirements file from the 'app' directory into the container
COPY app/requirements.txt ./

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# CORRECTED: Copy the contents of the app/ directory into the container's working directory
COPY app/. .

# Expose the port the application will run on
EXPOSE 80

# Define the command to run the application
CMD ["python", "app.py"]


