#!/bin/sh
set -e  # Exit immediately if a command exits with a non-zero status

# Function to capture command output and optionally save to S3
run_and_capture() {
  cmd_name="$1"
  shift
  output_file="/tmp/terraform_${cmd_name}_output.txt"

  # Run command, capture output to file while still printing to stdout
  set +e
  "$@" > "$output_file" 2>&1
  cmd_exit_code=$?
  set -e

  # Print output to stdout (for CloudWatch)
  cat "$output_file"

  # Upload to S3 if configured
  if [ "$SAVE_OUTPUT_TO_S3" = "true" ] && [ -n "$S3_BUCKET_NAME" ]; then
    s3_key="${S3_KEY_PREFIX}/${REQUEST_ID}/${cmd_name}.txt"
    echo "📤 Uploading ${cmd_name} output to s3://${S3_BUCKET_NAME}/${s3_key}"
    aws s3 cp "$output_file" "s3://${S3_BUCKET_NAME}/${s3_key}" --quiet || echo "⚠️ Failed to upload output to S3"
  fi

  rm -f "$output_file"
  return $cmd_exit_code
}

# Function to upload a file (e.g., binary tfplan) to S3
upload_to_s3() {
  local_path="$1"
  s3_filename="$2"
  if [ "$SAVE_OUTPUT_TO_S3" = "true" ] && [ -n "$S3_BUCKET_NAME" ] && [ -f "$local_path" ]; then
    s3_key="${S3_KEY_PREFIX}/${REQUEST_ID}/${s3_filename}"
    echo "📤 Uploading ${s3_filename} to s3://${S3_BUCKET_NAME}/${s3_key}"
    aws s3 cp "$local_path" "s3://${S3_BUCKET_NAME}/${s3_key}" --quiet || echo "⚠️ Failed to upload ${s3_filename} to S3"
  fi
}

echo "🚀 Starting Terraform execution custom runtime inside AWS Lambda..."

while true; do
  echo "🔄 Polling for the next invocation event..."
  # Poll for the next invocation from the Lambda Runtime API
  RESPONSE=$(curl -s -D - "http://${AWS_LAMBDA_RUNTIME_API}/2018-06-01/runtime/invocation/next")

  # Extract the Request ID from the response headers
  REQUEST_ID=$(echo "$RESPONSE" | grep -Fi "Lambda-Runtime-Aws-Request-Id:" | awk '{print $2}' | tr -d '\r')

  # Extract the event payload from the response body
  # The body starts after the first blank line
  EVENT=$(echo "$RESPONSE" | sed -n '/^\r$/,$p' | sed '1d')

  if [ -z "$EVENT" ]; then
    echo "❌ No event payload received."
    exit 1
  fi

  # Extract values from JSON event using `jq`
  BASE64_BACKEND_HCL=$(echo "$EVENT" | jq -r '.backend')
  TF_COMMAND=$(echo "$EVENT" | jq -r '.command')
  DEBUG_LEVEL=$(echo "$EVENT" | jq -r '.debug // empty')

  # Validate required arguments
  if [ -z "$BASE64_BACKEND_HCL" ] || [ -z "$TF_COMMAND" ]; then
    echo "❌ ERROR: Missing required arguments."
    echo "Usage: Pass JSON payload with tf_code and command."
    exit 1
  fi

  # Extract AWS Credentials from the JSON event (optional)
  AWS_ACCESS_KEY_ID=$(echo "$EVENT" | jq -r '.aws_access_key // empty')
  AWS_SECRET_ACCESS_KEY=$(echo "$EVENT" | jq -r '.aws_secret_key // empty')
  AWS_SESSION_TOKEN=$(echo "$EVENT" | jq -r '.aws_session_token // empty')

  # Set AWS Credentials ONLY if they exist in the payload
  if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "🔑 Setting AWS Credentials from payload..."
    export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
    export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
    export AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN}"
  else
    echo "🔒 No AWS credentials provided."
  fi

  # Extract optional Terraform variables in base64 format (optional)
  BASE64_ENVS=$(echo "$EVENT" | jq -r '.envs // empty')
  BASE64_TFCONFIG=$(echo "$EVENT" | jq -r '.tfconfig // empty')
  BASE64_TFVARS=$(echo "$EVENT" | jq -r '.tfvars // empty')

  # Decode the Base64 encoded environment variables
  if [ -n "$BASE64_ENVS" ]; then
      echo "🔧 Decoding and setting environment variables..."
      echo "$BASE64_ENVS" | base64 -d > /tmp/envs.sh
      

      # Read each line from the decoded env file
      while IFS= read -r line; do
          # Ignore empty lines
          [ -z "$line" ] && continue

          # Extract key and value
          key=$(echo "$line" | cut -d '=' -f1)
          value=$(echo "$line" | cut -d '=' -f2-)

          # Replace invalid characters (.:) with underscores (_) for shell export
          safe_key=$(echo "$key" | sed 's/[^a-zA-Z0-9_]/_/g')

          # Export the valid shell variable
          export "$safe_key"="$value"

          # # Store the original key-value mapping for Terraform
          # ENV_MAPPING+=" \"$key=$value\""
      done < /tmp/envs.sh

      if [ "$DEBUG_LEVEL" = "true" ]; then
        echo "🔧 Environment variables: $(cat /tmp/envs.sh)"
        printenv
      fi

      # Cleanup
      rm -f /tmp/envs.sh
  fi

  # Decode the Base64 encoded Terraform configuration
  if [ -n "$BASE64_TFCONFIG" ]; then
      echo "🔧 Decoding and setting Terraform configuration..."
      mkdir -p /tmp/.terraform.d/
      echo "$BASE64_TFCONFIG" | base64 -d > /tmp/.terraform.d/tfconfig.json
      export TF_CLI_CONFIG_FILE="/tmp/.terraform.d/tfconfig.json"
      if [ "$DEBUG_LEVEL" = "true" ]; then
        echo "🔧 Terraform configuration: $(cat /tmp/.terraform.d/tfconfig.json)"
      fi
  fi

  # Prepare the workspace in /tmp
  WORKING_DIR="/tmp/terraform.d/"
  mkdir -p "$WORKING_DIR"
  cd "$WORKING_DIR"

  # Decode and store Terraform variables (if provided)
  if [ -n "$BASE64_TFVARS" ]; then
    echo "🔧 Decoding Terraform variables..."
    echo "$BASE64_TFVARS" | base64 -d > /tmp/terraform.d/terraform.tfvars
    if [ "$DEBUG_LEVEL" = "true" ]; then
      echo "🔧 Terraform variables: $(cat /tmp/terraform.d/terraform.tfvars)"
    fi
  fi

  # Decode and extract Terraform code
  BASE64_ZIPPED_TF_CODE=$(echo "$EVENT" | jq -r '.tf_code // empty')
  if [ -n "$BASE64_ZIPPED_TF_CODE" ]; then
    echo "📦 Cleaning up existing Terraform code..."
    rm -rf ./*
    echo "📦 Decoding and extracting Terraform code..."
    echo "$BASE64_ZIPPED_TF_CODE" | base64 -d > terraform.zip
    unzip -o terraform.zip
    rm -f terraform.zip
  else 
    # Copy the existing Terraform code from the Lambda layer
    echo "📦 Copying existing Terraform code from Lambda layer..."
    cp -r /usr/local/src/terraform.d/* .
  fi

  # Decode and store backend configuration
  echo "📝 Decoding backend configuration..."
  echo "$BASE64_BACKEND_HCL" | base64 -d > backend.hcl
  if [ "$DEBUG_LEVEL" = "true" ]; then
    echo "📝 Backend configuration: $(cat backend.hcl)"
  fi

  # Debugging: List files in the working directory
  if [ "$DEBUG_LEVEL" = "true" ]; then
    echo "🔍 Debugging: Listing files in the working directory..."
    ls -la /tmp/terraform.d/  # List files for debugging
  fi

  # Execute Terraform command
  echo "⚙️ Executing Terraform command: terraform $TF_COMMAND"
  case "$TF_COMMAND" in
    "init")
      echo "🔄 Running Terraform init..."
      run_and_capture "init" terraform init -backend-config=backend.hcl
      ;;
    "plan")
      echo "🔄 Running Terraform init..."
      run_and_capture "init" terraform init -backend-config=backend.hcl
      echo "🔄 Running Terraform plan..."
      run_and_capture "plan" terraform plan -out=tfplan
      upload_to_s3 "/tmp/terraform.d/tfplan" "tfplan"
      ;;
    "apply")
      echo "🔄 Running Terraform init..."
      run_and_capture "init" terraform init -backend-config=backend.hcl
      echo "🔄 Running Terraform apply..."
      run_and_capture "plan" terraform plan -out=tfplan
      upload_to_s3 "/tmp/terraform.d/tfplan" "tfplan"
      run_and_capture "apply" terraform apply -auto-approve tfplan
      ;;
    "destroy")
      echo "🔄 Running Terraform init..."
      run_and_capture "init" terraform init -backend-config=backend.hcl
      echo "🔄 Running Terraform destroy..."
      run_and_capture "destroy" terraform destroy -auto-approve
      ;;
    "validate")
      echo "🔄 Running Terraform init..."
      run_and_capture "init" terraform init -backend-config=backend.hcl
      echo "🔄 Running Terraform validate..."
      run_and_capture "validate" terraform validate
      ;;
    *)
      echo "❌ ERROR: Invalid Terraform command: $TF_COMMAND"
      exit 1
      ;;
  esac

  echo "✅ Terraform execution completed successfully!"

  # Prepare a response payload
  if [ "$SAVE_OUTPUT_TO_S3" = "true" ] && [ -n "$S3_BUCKET_NAME" ]; then
    RESPONSE_PAYLOAD="{\"status\": \"success\", \"output_s3_bucket\": \"${S3_BUCKET_NAME}\", \"output_s3_prefix\": \"${S3_KEY_PREFIX}/${REQUEST_ID}/\"}"
  else
    RESPONSE_PAYLOAD='{"status": "success"}'
  fi

  # Send the response back to Lambda
  echo "📤 Sending response for Request ID: $REQUEST_ID"
  curl -s -X POST "http://${AWS_LAMBDA_RUNTIME_API}/2018-06-01/runtime/invocation/${REQUEST_ID}/response" \
       -d "$RESPONSE_PAYLOAD"

done
