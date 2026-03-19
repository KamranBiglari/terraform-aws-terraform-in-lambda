# This Dockerfile sets up a Docker image for running Terraform with AWS CLI, jq, and zip installed.
# 
# This argument allows specifying the version of Terraform to use.
ARG TERRAFORM_VERSION=1.14
ARG TFPLAN2MD_VERSION=1.40.0
ARG TERRAFORM_CODE_DESTINATION_PATH=terraform.d/
# Uses the specified version of the official HashiCorp Terraform image as the base image.
FROM hashicorp/terraform:${TERRAFORM_VERSION}
#
# Updates the package list in the Alpine Linux base image.
# Installs AWS CLI, jq (a lightweight and flexible command-line JSON processor), and zip (a compression utility).
RUN apk update
RUN apk add aws-cli jq zip unzip curl

# Download and install tfplan2md for converting Terraform plans to markdown
RUN wget -q "https://github.com/oocx/tfplan2md/releases/download/v${TFPLAN2MD_VERSION}/tfplan2md_${TFPLAN2MD_VERSION}_linux-musl-x64.tar.gz" -O /tmp/tfplan2md.tar.gz && \
    tar -xzf /tmp/tfplan2md.tar.gz -C /usr/local/bin/ && \
    chmod +x /usr/local/bin/tfplan2md && \
    rm -f /tmp/tfplan2md.tar.gz

# Creates the /app directory if it does not already exist.
# Sets the working directory to /app.
RUN mkdir -p /app
WORKDIR /app

# Copies the terraform directory from the local machine to the /app directory in the container.
COPY ${TERRAFORM_CODE_DESTINATION_PATH} /usr/local/src/
# Copies the entrypoint.sh script from the local machine to the /app directory in the container.
# Makes the entrypoint.sh script executable.
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh
RUN apk add dos2unix && dos2unix /app/entrypoint.sh


# Sets the entrypoint of the container to the entrypoint.sh script.
ENTRYPOINT ["/app/entrypoint.sh"]
