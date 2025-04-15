# This Dockerfile sets up a Docker image for running Terraform with AWS CLI, jq, and zip installed.
# 
# This argument allows specifying the version of Terraform to use.
ARG TERRAFORM_VERSION
ARG TERRAFORM_CODE_DESTINATION_PATH=terraform.d/
# Uses the specified version of the official HashiCorp Terraform image as the base image.
FROM hashicorp/terraform:${TERRAFORM_VERSION}
#
# Updates the package list in the Alpine Linux base image.
# Installs AWS CLI, jq (a lightweight and flexible command-line JSON processor), and zip (a compression utility).
RUN apk update
RUN apk add aws-cli jq zip unzip curl

# Creates the /app directory if it does not already exist.
# Sets the working directory to /app.
RUN mkdir -p /app
WORKDIR /app

# Copies the terraform directory from the local machine to the /app directory in the container.
COPY TERRAFORM_CODE_DESTINATION_PATH /usr/local/src/terraform.d/

# Copies the entrypoint.sh script from the local machine to the /app directory in the container.
# Makes the entrypoint.sh script executable.
COPY entrypoint.sh /app
RUN chmod +x entrypoint.sh

# Sets the entrypoint of the container to the entrypoint.sh script.
ENTRYPOINT [ "./entrypoint.sh" ]