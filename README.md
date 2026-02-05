# Terraform-in-Lambda — Run Terraform Inside AWS Lambda

[![Terraform Registry](https://img.shields.io/badge/Terraform%20Registry-KamranBiglari%2Fterraform--in--lambda-blue)](https://registry.terraform.io/modules/KamranBiglari/terraform-in-lambda/aws/latest)
[![GitHub](https://img.shields.io/badge/GitHub-KamranBiglari%2Fterraform--aws--terraform--in--lambda-black)](https://github.com/KamranBiglari/terraform-aws-terraform-in-lambda)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](https://github.com/KamranBiglari/terraform-aws-terraform-in-lambda/blob/main/LICENSE)
![Terraform](https://img.shields.io/badge/Terraform-%3E%3D%201.0.11-purple)
![AWS](https://img.shields.io/badge/AWS-Lambda%20%7C%20ECR-orange)

> A production-ready Terraform module that packages and deploys a Docker-based AWS Lambda function capable of executing Terraform commands (`plan`, `apply`, `destroy`, `validate`) on-demand — turning AWS Lambda into a serverless Terraform runner.

---

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
  - [Architecture Diagram](#architecture-diagram)
  - [Component Breakdown](#component-breakdown)
  - [Execution Flow](#execution-flow)
- [Design Decisions](#design-decisions)
- [Module Structure](#module-structure)
  - [File-by-File Reference](#file-by-file-reference)
- [Requirements](#requirements)
- [Input Variables](#input-variables)
- [Outputs](#outputs)
- [Use Cases](#use-cases)
- [Examples](#examples)
  - [Minimal Example](#1-minimal-example)
  - [Bundled Terraform Code at Build Time](#2-bundled-terraform-code-at-build-time)
  - [Dynamic Terraform Code at Invocation Time](#3-dynamic-terraform-code-at-invocation-time)
  - [With VPC and Custom Credentials](#4-with-vpc-and-custom-credentials)
  - [With Terraform Variables and Environment Variables](#5-with-terraform-variables-and-environment-variables)
  - [Multi-Environment Deployment Pipeline](#6-multi-environment-deployment-pipeline)
  - [Scheduled Infrastructure Reconciliation](#7-scheduled-infrastructure-reconciliation)
- [Lambda Invocation Payload Reference](#lambda-invocation-payload-reference)
- [Supported Terraform Commands](#supported-terraform-commands)
- [Security Considerations](#security-considerations)
- [Limitations & Caveats](#limitations--caveats)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

This module solves a specific and powerful problem: **how to run Terraform operations programmatically from within AWS without maintaining persistent infrastructure like EC2 instances or CI/CD runners.**

It creates an AWS Lambda function backed by a Docker container image. The image contains the Terraform binary, AWS CLI, and a custom shell-based runtime (`entrypoint.sh`) that implements the [AWS Lambda Runtime API](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html). When invoked, the Lambda function receives a JSON payload containing Terraform code (optionally), backend configuration, AWS credentials, and a command to execute. It then runs the specified Terraform operation and reports success or failure.

### Key Features

- **Serverless Terraform execution** — no servers, no CI runners, no build agents to maintain.
- **Docker container–based Lambda** — runs full Terraform binary with AWS CLI, jq, zip, and curl pre-installed.
- **Flexible code delivery** — bundle Terraform code at build time OR send it dynamically at invocation via base64-encoded zip.
- **Full backend support** — accepts base64-encoded backend configuration for S3, DynamoDB, or any Terraform backend.
- **Custom credentials** — optionally pass AWS access key, secret key, and session token per invocation.
- **Environment variable injection** — pass base64-encoded environment variables (including `TF_VAR_*`) at runtime.
- **Terraform CLI configuration** — inject custom `.terraformrc` / CLI config at runtime (e.g., for private registries).
- **`tfvars` support** — pass base64-encoded `terraform.tfvars` content at runtime.
- **Debug mode** — enable verbose output by setting `debug: true` in the payload.
- **VPC support** — deploy the Lambda inside a VPC with auto-created security groups.
- **Configurable resources** — set memory (up to 10 GB), timeout (up to 15 min), and ephemeral storage (up to 10 GB).
- **Automated ECR + Docker build pipeline** — creates ECR repository, builds the Docker image, and pushes it using the `kreuzwerker/docker` provider.

---

## How It Works

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         DEPLOYMENT TIME (terraform apply)              │
│                                                                        │
│  ┌──────────────┐    ┌───────────────┐    ┌──────────────────────────┐ │
│  │  Your .tf    │───▶│ local_file    │───▶│ Docker Image Build       │ │
│  │  source code │    │ (copy to      │    │ (hashicorp/terraform +   │ │
│  │  (optional)  │    │  terraform.d) │    │  aws-cli + entrypoint)   │ │
│  └──────────────┘    └───────────────┘    └────────────┬─────────────┘ │
│                                                         │               │
│  ┌──────────────┐                          ┌───────────▼─────────────┐ │
│  │ ECR          │◀─────────────────────────│ docker_registry_image   │ │
│  │ Repository   │    (push image)          │ (push to ECR)           │ │
│  └──────┬───────┘                          └─────────────────────────┘ │
│         │                                                               │
│         │    ┌───────────────────────────────────────────┐             │
│         └───▶│ Lambda Function (container image from ECR)│             │
│              │ + IAM Role + CloudWatch Logs + optional VPC│             │
│              └───────────────────────────────────────────┘             │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                        INVOCATION TIME (aws lambda invoke)             │
│                                                                        │
│  ┌─────────────────┐     ┌──────────────────────────────────────────┐ │
│  │  JSON Payload    │────▶│  entrypoint.sh (custom Lambda runtime)  │ │
│  │                  │     │                                          │ │
│  │  • backend (b64) │     │  1. Poll Lambda Runtime API for event   │ │
│  │  • command       │     │  2. Extract payload fields               │ │
│  │  • tf_code (b64) │     │  3. Set AWS credentials (if provided)   │ │
│  │  • aws_*         │     │  4. Decode envs, tfconfig, tfvars       │ │
│  │  • envs (b64)    │     │  5. Extract or copy Terraform code      │ │
│  │  • tfvars (b64)  │     │  6. Write backend.hcl                   │ │
│  │  • tfconfig(b64) │     │  7. terraform init -backend-config=...  │ │
│  │  • debug         │     │  8. terraform <command>                  │ │
│  └─────────────────┘     │  9. POST response to Runtime API        │ │
│                           └──────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Breakdown

| Component | Technology | Purpose |
|---|---|---|
| **Base Image** | `hashicorp/terraform:<version>` (Alpine) | Provides the Terraform binary |
| **Installed Tools** | `aws-cli`, `jq`, `zip`, `unzip`, `curl`, `dos2unix` | JSON parsing, AWS operations, file handling |
| **Custom Runtime** | `entrypoint.sh` (Shell) | Implements the Lambda Runtime API contract |
| **Container Registry** | AWS ECR | Stores the Docker image for Lambda |
| **Lambda Function** | `terraform-aws-modules/lambda/aws` | Manages the Lambda resource with IAM, VPC, CloudWatch |
| **Security Group** | `terraform-aws-modules/security-group/aws` | Optional egress-only SG for VPC-deployed Lambdas |
| **Docker Provider** | `kreuzwerker/docker` | Builds and pushes Docker images from Terraform |

### Execution Flow

1. **Polling** — the `entrypoint.sh` script enters an infinite loop, polling the Lambda Runtime API at `http://${AWS_LAMBDA_RUNTIME_API}/2018-06-01/runtime/invocation/next` for the next invocation event.
2. **Parsing** — it extracts the `REQUEST_ID` from response headers and the JSON payload from the response body using `jq`.
3. **Credentials** — if `aws_access_key`, `aws_secret_key`, and `aws_session_token` are present in the payload, they are exported as environment variables; otherwise, the Lambda execution role's credentials are used.
4. **Environment Variables** — if `envs` is provided (base64-encoded key=value pairs), they are decoded and exported. Invalid shell characters in keys are sanitized to underscores.
5. **Terraform CLI Config** — if `tfconfig` is provided (base64-encoded JSON), it is written to `/tmp/.terraform.d/tfconfig.json` and `TF_CLI_CONFIG_FILE` is set.
6. **Workspace Setup** — `/tmp/terraform.d/` is created as the working directory. Terraform code is either extracted from `tf_code` (base64-encoded zip) or copied from the bundled `/usr/local/src/terraform.d/` path.
7. **Variables** — if `tfvars` is provided (base64-encoded), it is written to `terraform.tfvars` in the working directory.
8. **Backend** — the `backend` field (base64-encoded) is decoded and written to `backend.hcl`.
9. **Execution** — `terraform init -backend-config=backend.hcl` runs, followed by the requested command (`plan`, `apply`, `destroy`, `validate`, or `init`).
10. **Response** — on success, `{"status": "success"}` is POSTed to the Runtime API. On failure (via `set -e`), the script exits and Lambda reports the error.

---

## Design Decisions

### Why Docker-based Lambda?

Standard zip-based Lambda functions don't support arbitrary binaries like Terraform. Docker container images allow packaging the full Terraform binary, plugins, and dependencies into a Lambda-compatible runtime. The `hashicorp/terraform` Alpine image is lightweight (~80 MB compressed) and provides a solid foundation.

### Why a Custom Runtime?

AWS Lambda's built-in runtimes (Python, Node.js, etc.) aren't suitable for running shell-based tools like Terraform. The module uses the `provided` runtime pattern, implementing the Lambda Runtime API directly in a shell script. This gives full control over the execution lifecycle, error handling, and response formatting.

### Why `kreuzwerker/docker` Provider?

The module uses the Docker Terraform provider to build and push images directly during `terraform apply`. This eliminates the need for separate CI/CD image build pipelines — the entire deployment (ECR repo creation, Docker build, image push, Lambda creation) happens in a single Terraform run.

### Why Bundle Code at Build Time?

The module supports copying your Terraform code into the Docker image at build time via `terraform_code_source_path`. This means the Lambda doesn't need to receive code at every invocation, which is ideal for scheduled or event-driven use cases where the same infrastructure code runs repeatedly.

### Why Also Support Dynamic Code?

For scenarios like self-service platforms or multi-tenant systems where different Terraform code runs per invocation, the `tf_code` payload field allows sending base64-encoded zipped Terraform code at runtime. This provides maximum flexibility.

---

## Module Structure

```
terraform-aws-terraform-in-lambda/
├── .github/
│   └── workflows/
│       └── release.yaml        # GitHub Actions workflow for versioned releases
├── terraform.d/
│   └── .dockerignore           # Excludes .terraform state from Docker builds
├── Dockerfile                  # Container image definition
├── entrypoint.sh               # Custom Lambda runtime (shell script)
├── main.tf                     # Core resources: ECR, Docker, Lambda, Security Group
├── variables.tf                # Input variable declarations
├── outputs.tf                  # Output values
├── data.tf                     # ECR authentication token data source
├── locals.tf                   # Local values (timestamp, file listing)
├── providers.tf                # Docker provider with ECR auth
├── versions.tf                 # Required Terraform and provider versions
├── LICENSE                     # Apache 2.0
└── README.md                   # Documentation
```

### File-by-File Reference

#### `main.tf` — Core Infrastructure

This file orchestrates all the resources:

- **`aws_ecr_repository.this`** — creates a private ECR repository (conditionally via `create_ecr`) with image scanning enabled and mutable tags.
- **`local_file.copy_terraform_code`** — iterates over files in `terraform_code_source_path`, copies them to `terraform.d/` (the Docker build context), respecting exclusions defined in `terraform_code_source_exclude`.
- **`docker_image.this`** — builds the Docker image using the `Dockerfile`, tagging it with the Terraform version and a timestamp (`YYYYMMDDHHmmss`) to ensure unique tags on every apply.
- **`docker_registry_image.this`** — pushes the built image to ECR.
- **`module.this__lambda_function_sg`** — optionally creates a security group with full egress (0.0.0.0/0) for VPC-deployed Lambdas.
- **`module.this__lambda_function`** — uses the popular `terraform-aws-modules/lambda/aws` module (v7.20+) to create the Lambda function with the Docker image, configuring memory, timeout, ephemeral storage, VPC, environment variables, and CloudWatch logging.

#### `variables.tf` — Configuration Knobs

| Variable | Default | Purpose |
|---|---|---|
| `terraform_version` | `"1.11"` | Terraform binary version in the Docker image |
| `create_ecr` | `true` | Whether to create an ECR repository |
| `ecr_name` | `"terraform-in-lambda-ecr"` | ECR repository name |
| `function_name` | `"terraform-lambda-function"` | Lambda function name |
| `function_timeout` | `900` (15 min) | Lambda timeout in seconds |
| `function_memory_size` | `4096` (4 GB) | Lambda memory in MB |
| `ephemeral_storage_size` | `4096` (4 GB) | Lambda /tmp storage in MB |
| `function_environment_variables` | `{}` | Static env vars baked into the function |
| `function_create_sg` | `false` | Create a security group for VPC |
| `function_vpc_id` | `""` | VPC ID for the security group |
| `function_attach_network_policy` | `false` | Attach VPC network policy |
| `function_vpc_subnet_ids` | `[]` | Subnet IDs for VPC deployment |
| `function_cloudwatch_logs_retention_in_days` | `30` | CloudWatch log retention |
| `create_role` | `true` | Whether to create an IAM execution role |
| `terraform_code_source_path` | `null` | Path to Terraform code to bundle in the image |
| `terraform_code_source_exclude` | `[]` | Files to exclude from bundling |
| `terraform_code_destination_path` | `"terraform.d"` | Destination directory in the build context |

#### `entrypoint.sh` — The Custom Lambda Runtime

This is the heart of the module — a POSIX shell script that implements the AWS Lambda custom runtime contract. It runs in an infinite loop (to support Lambda container reuse), polling the Runtime API for invocation events. Key features:

- **Graceful error handling** via `set -e` (exits on any command failure)
- **Dual code delivery**: dynamic (`tf_code` in payload) or static (bundled at build time)
- **Environment variable injection** with shell-safe key sanitization
- **Terraform CLI config override** for private registry authentication
- **Debug mode** that prints decoded configs, env vars, and directory listings

#### `Dockerfile` — Container Image Definition

Based on `hashicorp/terraform:<version>` (Alpine Linux), it installs `aws-cli`, `jq`, `zip`, `unzip`, `curl`, and `dos2unix`. The Terraform code is copied to `/usr/local/src/` and the entrypoint to `/app/`. The `dos2unix` step ensures cross-platform line ending compatibility.

#### `data.tf`, `locals.tf`, `providers.tf`, `versions.tf`

- **`data.tf`** — fetches the ECR authorization token for Docker authentication.
- **`locals.tf`** — computes a timestamp for unique image tags and lists source files for bundling.
- **`providers.tf`** — configures the `kreuzwerker/docker` provider with ECR registry credentials.
- **`versions.tf`** — requires Terraform >= 1.0.11, AWS provider >= 5.8.0, and Docker provider ~> 3.0.

---

## Requirements

| Requirement | Version |
|---|---|
| Terraform | >= 1.0.11 |
| AWS Provider | >= 5.8.0 |
| Docker Provider (`kreuzwerker/docker`) | ~> 3.0 |
| Docker Engine | Running locally (for image builds) |

**Important**: The machine running `terraform apply` must have Docker installed and running, as the module builds the container image locally before pushing to ECR.

---

## Input Variables

| Name | Type | Default | Required | Description |
|---|---|---|---|---|
| `terraform_version` | `string` | `"1.11"` | No | Terraform version to install in the Docker image |
| `create_ecr` | `bool` | `true` | No | Whether to create the ECR repository |
| `ecr_name` | `string` | `"terraform-in-lambda-ecr"` | No | Name for the ECR repository |
| `function_name` | `string` | `"terraform-lambda-function"` | No | Lambda function name |
| `function_timeout` | `number` | `900` | No | Lambda timeout (seconds, max 900) |
| `function_memory_size` | `number` | `4096` | No | Lambda memory (MB, max 10240) |
| `ephemeral_storage_size` | `number` | `4096` | No | Lambda ephemeral /tmp storage (MB, max 10240) |
| `function_environment_variables` | `map(string)` | `{}` | No | Environment variables for the Lambda |
| `function_create_sg` | `bool` | `false` | No | Create a security group for VPC mode |
| `function_vpc_id` | `string` | `""` | No | VPC ID (required if `function_create_sg = true`) |
| `function_attach_network_policy` | `bool` | `false` | No | Attach VPC network policy to the Lambda role |
| `function_vpc_subnet_ids` | `list(string)` | `[]` | No | Subnet IDs for VPC deployment |
| `function_cloudwatch_logs_retention_in_days` | `number` | `30` | No | CloudWatch Logs retention period |
| `create_role` | `bool` | `true` | No | Whether to create an IAM execution role |
| `terraform_code_source_path` | `string` | `null` | No | Local path to Terraform code to bundle |
| `terraform_code_source_exclude` | `list(string)` | `[]` | No | Files to exclude from bundling |
| `terraform_code_destination_path` | `string` | `"terraform.d"` | No | Destination path within the build context |

---

## Outputs

| Name | Description |
|---|---|
| `lambda_function_name` | The name of the created Lambda function |

---

## Use Cases

### 1. Scheduled Infrastructure Reconciliation

Run `terraform apply` on a schedule (via EventBridge/CloudWatch Events) to ensure infrastructure stays in the desired state. This catches and reverts any manual drift.

### 2. Self-Service Infrastructure Platform

Build an internal platform where developers request infrastructure through an API. The API Gateway triggers the Lambda with the appropriate Terraform code and variables, provisioning resources on-demand.

### 3. Event-Driven Infrastructure

Trigger Terraform operations in response to AWS events — for example, automatically provisioning resources when a new account is created in AWS Organizations, or scaling infrastructure based on CloudWatch alarms.

### 4. Multi-Account Terraform Execution

Pass cross-account AWS credentials in the payload to run Terraform against multiple AWS accounts from a single Lambda function, centralizing your infrastructure management.

### 5. GitOps Without CI/CD Runners

Eliminate the need for persistent CI/CD runners (Jenkins agents, GitHub Actions runners, etc.) for Terraform operations. The Lambda function provides a zero-maintenance compute environment.

### 6. Ephemeral Environment Management

Spin up and tear down short-lived environments (dev, staging, feature branches) by invoking the Lambda with `apply` or `destroy` commands and the appropriate Terraform code.

### 7. Compliance & Governance Enforcement

Periodically run `terraform plan` to detect configuration drift, parse the output, and alert (or auto-remediate) if resources have drifted from their declared state.

### 8. Terraform as a Microservice

Expose Terraform operations as an API endpoint (via API Gateway + Lambda) for other services to consume, enabling infrastructure-as-a-service patterns within your organization.

---

## Examples

### 1. Minimal Example

Deploy the Lambda function with defaults — no bundled code, code will be sent at invocation time:

```hcl
module "terraform_lambda" {
  source  = "KamranBiglari/terraform-in-lambda/aws"
  version = "0.3.7"

  function_name     = "my-terraform-runner"
  terraform_version = "1.11"
}
```

Invoke it:

```bash
# Prepare your Terraform code
cd my-terraform-project/
zip -r /tmp/tf-code.zip *.tf

# Prepare the backend config
echo 'bucket = "my-tf-state"
key    = "lambda-managed/terraform.tfstate"
region = "eu-west-2"' > /tmp/backend.hcl

# Invoke the Lambda
aws lambda invoke \
  --function-name my-terraform-runner \
  --cli-binary-format raw-in-base64-out \
  --payload "$(jq -n \
    --arg tf_code "$(base64 -w0 /tmp/tf-code.zip)" \
    --arg backend "$(base64 -w0 /tmp/backend.hcl)" \
    --arg command "plan" \
    '{tf_code: $tf_code, backend: $backend, command: $command}'
  )" \
  /tmp/response.json

cat /tmp/response.json
```

### 2. Bundled Terraform Code at Build Time

Bundle your Terraform code into the Docker image so it doesn't need to be sent with each invocation:

```hcl
module "terraform_lambda" {
  source  = "KamranBiglari/terraform-in-lambda/aws"
  version = "0.3.7"

  function_name     = "infra-reconciler"
  terraform_version = "1.11"

  # Bundle code from a local directory
  terraform_code_source_path    = "${path.module}/my-infrastructure"
  terraform_code_source_exclude = [
    ".terraform",
    ".terraform.lock.hcl",
    "*.tfstate",
    "*.tfstate.*"
  ]
}
```

Invoke without `tf_code`:

```bash
aws lambda invoke \
  --function-name infra-reconciler \
  --cli-binary-format raw-in-base64-out \
  --payload "$(jq -n \
    --arg backend "$(echo -n 'bucket="my-state"\nkey="infra/terraform.tfstate"\nregion="eu-west-2"' | base64 -w0)" \
    --arg command "apply" \
    '{backend: $backend, command: $command}'
  )" \
  /tmp/response.json
```

### 3. Dynamic Terraform Code at Invocation Time

Send different Terraform code with each invocation — useful for multi-tenant or self-service platforms:

```bash
# Create a simple S3 bucket
cat > /tmp/main.tf << 'EOF'
terraform {
  backend "s3" {}
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "eu-west-2"
}

variable "bucket_name" {}

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
}
EOF

cd /tmp && zip tf-code.zip main.tf

# Invoke with the code and variables
aws lambda invoke \
  --function-name terraform-lambda-function \
  --cli-binary-format raw-in-base64-out \
  --payload "$(jq -n \
    --arg tf_code "$(base64 -w0 /tmp/tf-code.zip)" \
    --arg backend "$(echo -n 'bucket="state-bucket"\nkey="dynamic/terraform.tfstate"\nregion="eu-west-2"' | base64 -w0)" \
    --arg tfvars "$(echo -n 'bucket_name = "my-new-bucket-12345"' | base64 -w0)" \
    --arg command "apply" \
    '{tf_code: $tf_code, backend: $backend, tfvars: $tfvars, command: $command}'
  )" \
  /tmp/response.json
```

### 4. With VPC and Custom Credentials

Deploy the Lambda inside a VPC and pass cross-account credentials at invocation:

```hcl
module "terraform_lambda" {
  source  = "KamranBiglari/terraform-in-lambda/aws"
  version = "0.3.7"

  function_name     = "cross-account-deployer"
  terraform_version = "1.11"

  # VPC Configuration
  function_create_sg             = true
  function_vpc_id                = "vpc-0abc123def456"
  function_vpc_subnet_ids        = ["subnet-0aaa", "subnet-0bbb"]
  function_attach_network_policy = true

  # Resource sizing
  function_memory_size   = 8192    # 8 GB
  function_timeout       = 900     # 15 minutes
  ephemeral_storage_size = 10240   # 10 GB
}
```

Invoke with cross-account credentials (e.g., from STS AssumeRole):

```bash
# Get temporary credentials for the target account
CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::123456789012:role/TerraformRole \
  --role-session-name lambda-deploy \
  --query 'Credentials' \
  --output json)

aws lambda invoke \
  --function-name cross-account-deployer \
  --cli-binary-format raw-in-base64-out \
  --payload "$(jq -n \
    --arg ak "$(echo $CREDS | jq -r .AccessKeyId)" \
    --arg sk "$(echo $CREDS | jq -r .SecretAccessKey)" \
    --arg st "$(echo $CREDS | jq -r .SessionToken)" \
    --arg backend "$(base64 -w0 backend.hcl)" \
    --arg command "apply" \
    '{aws_access_key: $ak, aws_secret_key: $sk, aws_session_token: $st, backend: $backend, command: $command}'
  )" \
  /tmp/response.json
```

### 5. With Terraform Variables and Environment Variables

Pass `tfvars`, environment variables, and Terraform CLI config at invocation:

```bash
# Environment variables (TF_VAR_* for Terraform, or any shell vars)
cat > /tmp/envs.txt << 'EOF'
TF_VAR_environment=production
TF_VAR_instance_count=3
TF_LOG=INFO
EOF

# Terraform CLI config (e.g., for private registry auth)
cat > /tmp/tfconfig.json << 'EOF'
{
  "credentials": {
    "app.terraform.io": {
      "token": "my-tfc-token"
    }
  }
}
EOF

# terraform.tfvars
cat > /tmp/terraform.tfvars << 'EOF'
region       = "eu-west-1"
project_name = "my-app"
tags = {
  Team = "Platform"
}
EOF

aws lambda invoke \
  --function-name terraform-lambda-function \
  --cli-binary-format raw-in-base64-out \
  --payload "$(jq -n \
    --arg backend "$(base64 -w0 /tmp/backend.hcl)" \
    --arg command "apply" \
    --arg envs "$(base64 -w0 /tmp/envs.txt)" \
    --arg tfconfig "$(base64 -w0 /tmp/tfconfig.json)" \
    --arg tfvars "$(base64 -w0 /tmp/terraform.tfvars)" \
    --arg debug "true" \
    '{backend: $backend, command: $command, envs: $envs, tfconfig: $tfconfig, tfvars: $tfvars, debug: $debug}'
  )" \
  /tmp/response.json
```

### 6. Multi-Environment Deployment Pipeline

Use a Step Functions state machine or a simple script to deploy across environments:

```bash
#!/bin/bash
# deploy-all.sh — Deploy to dev, staging, and prod sequentially

ENVIRONMENTS=("dev" "staging" "prod")
TF_CODE=$(base64 -w0 /tmp/tf-code.zip)

for ENV in "${ENVIRONMENTS[@]}"; do
  echo "🚀 Deploying to $ENV..."

  BACKEND=$(echo -n "bucket=\"tf-state-${ENV}\"
key=\"app/terraform.tfstate\"
region=\"eu-west-2\"
dynamodb_table=\"tf-lock-${ENV}\"" | base64 -w0)

  TFVARS=$(echo -n "environment = \"${ENV}\"
instance_type = \"$([ "$ENV" = "prod" ] && echo "m5.large" || echo "t3.medium")\"" | base64 -w0)

  aws lambda invoke \
    --function-name terraform-lambda-function \
    --cli-binary-format raw-in-base64-out \
    --payload "$(jq -n \
      --arg tf_code "$TF_CODE" \
      --arg backend "$BACKEND" \
      --arg tfvars "$TFVARS" \
      --arg command "apply" \
      '{tf_code: $tf_code, backend: $backend, tfvars: $tfvars, command: $command}'
    )" \
    "/tmp/response-${ENV}.json"

  STATUS=$(jq -r '.status' "/tmp/response-${ENV}.json")
  if [ "$STATUS" != "success" ]; then
    echo "❌ Deployment to $ENV failed!"
    exit 1
  fi
  echo "✅ $ENV deployed successfully"
done
```

### 7. Scheduled Infrastructure Reconciliation

Combine with EventBridge to run `apply` every hour:

```hcl
module "terraform_lambda" {
  source  = "KamranBiglari/terraform-in-lambda/aws"
  version = "0.3.7"

  function_name              = "infra-reconciler"
  terraform_version          = "1.11"
  terraform_code_source_path = "${path.module}/infrastructure"
}

# Schedule the Lambda to run every hour
resource "aws_cloudwatch_event_rule" "hourly" {
  name                = "terraform-reconcile-hourly"
  schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule = aws_cloudwatch_event_rule.hourly.name
  arn  = module.terraform_lambda.lambda_function_name

  input = jsonencode({
    backend = base64encode(<<-EOT
      bucket         = "my-state-bucket"
      key            = "reconciled/terraform.tfstate"
      region         = "eu-west-2"
      dynamodb_table = "tf-lock"
    EOT
    )
    command = "apply"
  })
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = module.terraform_lambda.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.hourly.arn
}
```

---

## Lambda Invocation Payload Reference

The Lambda function accepts a JSON payload with the following fields:

| Field | Type | Required | Description |
|---|---|---|---|
| `backend` | `string` | **Yes** | Base64-encoded Terraform backend configuration (e.g., S3 bucket, key, region, DynamoDB table) |
| `command` | `string` | **Yes** | Terraform command to execute: `init`, `plan`, `apply`, `destroy`, or `validate` |
| `tf_code` | `string` | No | Base64-encoded ZIP archive containing Terraform `.tf` files. If omitted, uses code bundled at build time |
| `aws_access_key` | `string` | No | AWS access key ID for the Terraform provider |
| `aws_secret_key` | `string` | No | AWS secret access key for the Terraform provider |
| `aws_session_token` | `string` | No | AWS session token (for temporary credentials) |
| `envs` | `string` | No | Base64-encoded key=value pairs (one per line) to export as environment variables |
| `tfconfig` | `string` | No | Base64-encoded Terraform CLI configuration JSON (e.g., registry credentials) |
| `tfvars` | `string` | No | Base64-encoded `terraform.tfvars` content |
| `debug` | `string` | No | Set to `"true"` to enable verbose debug output |

### Payload Example

```json
{
  "backend": "YnVja2V0ID0gIm15LXN0YXRlLWJ1Y2tldCIKa2V5ID0gImFwcC90ZXJyYWZvcm0udGZzdGF0ZSIKcmVnaW9uID0gImV1LXdlc3QtMiI=",
  "command": "apply",
  "tf_code": "<base64-encoded-zip>",
  "aws_access_key": "AKIAIOSFODNN7EXAMPLE",
  "aws_secret_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
  "aws_session_token": "FwoGZXIvYXdzE...",
  "envs": "VEZfVkFSX2Vudmlyb25tZW50PXByb2R1Y3Rpb24=",
  "tfvars": "cmVnaW9uID0gImV1LXdlc3QtMiI=",
  "tfconfig": "eyJjcmVkZW50aWFscyI6e319",
  "debug": "true"
}
```

---

## Supported Terraform Commands

| Command | Behaviour |
|---|---|
| `init` | Runs `terraform init -backend-config=backend.hcl` |
| `plan` | Runs `init` then `terraform plan` |
| `apply` | Runs `init`, then `terraform plan -out=tfplan`, then `terraform apply -auto-approve tfplan` |
| `destroy` | Runs `init` then `terraform destroy -auto-approve` |
| `validate` | Runs `init` then `terraform validate` |

Note: `apply` uses a plan file (`-out=tfplan`) to ensure the exact planned changes are applied, preventing race conditions.

---

## Security Considerations

### IAM Role

The Lambda execution role must have permissions for:
- **Terraform state backend**: S3 read/write, DynamoDB read/write (for locking)
- **Managed resources**: whatever resources your Terraform code creates/manages
- **ECR**: pull access to the container image
- **CloudWatch Logs**: log group/stream creation and writes

Alternatively, pass explicit credentials via the `aws_access_key`/`aws_secret_key`/`aws_session_token` payload fields to operate with a different identity.

### Credential Handling

- Credentials passed in the payload are exported as environment variables within the Lambda execution context and are **not persisted** beyond the invocation.
- If no credentials are provided, the Lambda uses its execution role (recommended for same-account operations).
- For cross-account access, use STS `AssumeRole` and pass the temporary credentials.

### State Security

- Always use an encrypted S3 bucket for Terraform state.
- Enable DynamoDB state locking to prevent concurrent modifications.
- Consider enabling S3 versioning for state file recovery.

### Network Security

- Deploy in a VPC with private subnets for operations requiring access to private resources.
- The auto-created security group allows all egress (required for Terraform provider API calls) but no ingress.
- Use VPC endpoints for S3 and DynamoDB to keep state traffic off the public internet.

### Secrets in Payloads

- Avoid putting secrets directly in invocation payloads where possible.
- Use the `envs` field with references to AWS Secrets Manager or SSM Parameter Store.
- Consider encrypting the Lambda environment variables with a KMS key.

---

## Limitations & Caveats

| Limitation | Details |
|---|---|
| **15-minute timeout** | AWS Lambda has a hard limit of 900 seconds. Terraform operations that take longer will fail. For long-running operations, consider AWS CodeBuild. |
| **10 GB memory limit** | Lambda supports up to 10,240 MB. Large state files or many providers may need the upper end of this range. |
| **10 GB ephemeral storage** | Lambda `/tmp` is limited to 10,240 MB. Large provider plugins or state files may hit this limit. |
| **Read-only filesystem** | The Lambda container filesystem is read-only except `/tmp`. Terraform data directory is automatically set to `/tmp`. |
| **Cold starts** | Docker-based Lambdas can take 5–15 seconds to cold start. Use Provisioned Concurrency if latency matters. |
| **Docker required at build time** | The machine running `terraform apply` must have Docker installed and running. |
| **No streaming output** | Terraform output is only available in CloudWatch Logs after the invocation completes. You cannot watch a `plan` or `apply` in real-time. |
| **Single command per invocation** | Each invocation runs one Terraform command. Chaining (e.g., plan then apply) requires separate invocations. |
| **Image rebuilds on every apply** | The timestamp-based tag means every `terraform apply` builds and pushes a new Docker image. |
| **No `output` command** | The entrypoint only supports `init`, `plan`, `apply`, `destroy`, and `validate`. To get Terraform outputs, parse the `apply` logs. |

---

## Troubleshooting

### Lambda Reports Failure But No Error Message

Check CloudWatch Logs for the Lambda function. All stdout and stderr from Terraform are captured there. Look for the log group `/aws/lambda/<function_name>`.

### Out of Memory

Increase `function_memory_size`. Terraform's memory usage scales with the number of resources in state and the number of providers. Start with 4096 MB and increase if needed.

### Timeout

Increase `function_timeout` (max 900 seconds). If your Terraform operations consistently take more than 15 minutes, consider AWS CodeBuild instead.

### Docker Build Fails During `terraform apply`

Ensure Docker is running on the machine executing Terraform. The `kreuzwerker/docker` provider requires a working Docker daemon.

### ECR Authentication Errors

The module automatically fetches ECR credentials via `aws_ecr_authorization_token`. Ensure the AWS credentials used for `terraform apply` have `ecr:GetAuthorizationToken` and `ecr:BatchGetImage` permissions.

### "No event payload received" Error

The Lambda was invoked without a JSON payload. Ensure you're passing a valid JSON body with at least `backend` and `command` fields.

### Terraform Init Fails Inside Lambda

Check that your backend configuration is correct and the Lambda execution role has permissions to access the state bucket and lock table.

### Debug Mode

Add `"debug": "true"` to the invocation payload to see:
- Decoded environment variables
- Decoded Terraform CLI configuration
- Decoded terraform.tfvars content
- File listing of the working directory

---

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -m 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

---

## License

This module is licensed under the [Apache License 2.0](https://github.com/KamranBiglari/terraform-aws-terraform-in-lambda/blob/main/LICENSE).

---

## Author

**Kamran Biglari** — [GitHub](https://github.com/KamranBiglari)

Published on the [Terraform Registry](https://registry.terraform.io/modules/KamranBiglari/terraform-in-lambda/aws/latest).
