# This Dockerfile sets up a Docker image for running Terraform with AWS CLI, jq, and zip installed.
# 
# This argument allows specifying the version of Terraform to use.
ARG TERRAFORM_VERSION=1.14
ARG TERRAFORM_CODE_DESTINATION_PATH=terraform.d/
# Uses the specified version of the official HashiCorp Terraform image as the base image.
FROM hashicorp/terraform:${TERRAFORM_VERSION}

ARG TFPLAN2MD_VERSION=1.40.0

# Pinned Alpine repo + package versions for reproducible builds.
# Bump these intentionally; do not let them float.
ARG ALPINE_VERSION=3.21
ARG AWS_CLI_VERSION=2.22.10-r0
ARG JQ_VERSION=1.7.1-r0
ARG ZIP_VERSION=3.0-r13
ARG UNZIP_VERSION=6.0-r15
ARG CURL_VERSION=8.14.1-r2
ARG DOS2UNIX_VERSION=7.5.2-r0

RUN printf '%s\n' \
      "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/main" \
      "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/community" \
      > /etc/apk/repositories && \
    apk update && apk upgrade --no-cache && \
    apk add --no-cache \
      aws-cli=${AWS_CLI_VERSION} \
      jq=${JQ_VERSION} \
      zip=${ZIP_VERSION} \
      unzip=${UNZIP_VERSION} \
      curl=${CURL_VERSION} \
      dos2unix=${DOS2UNIX_VERSION}

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
RUN chmod +x /app/entrypoint.sh && dos2unix /app/entrypoint.sh


# Sets the entrypoint of the container to the entrypoint.sh script.
ENTRYPOINT ["/app/entrypoint.sh"]
