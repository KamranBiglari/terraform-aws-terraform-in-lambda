#!/bin/sh

set -e  # Exit immediately if a command exits with a non-zero status

echo "🚀 Starting Terraform execution inside AWS Lambda..."

# ✅ Read JSON event from Lambda (passed via STDIN)
read EVENT

# ✅ Extract values from JSON event using `jq`
BASE64_ZIPPED_TF_CODE=$(echo "$EVENT" | jq -r '.tf_code')
BASE64_BACKEND_HCL=$(echo "$EVENT" | jq -r '.backend')
TF_COMMAND=$(echo "$EVENT" | jq -r '.command')

# ✅ Validate Required Arguments
if [ -z "$BASE64_ZIPPED_TF_CODE" ] || [ -z "$BASE64_BACKEND_HCL" ] || [ -z "$TF_COMMAND" ]; then
  echo "❌ ERROR: Missing required arguments."
  echo "Usage: Pass JSON payload with tf_code, backend, and command."
  exit 1
fi

# ✅ Extract AWS Credentials from the JSON event (optional)
AWS_ACCESS_KEY_ID=$(echo "$EVENT" | jq -r '.aws_access_key // empty')
AWS_SECRET_ACCESS_KEY=$(echo "$EVENT" | jq -r '.aws_secret_key // empty')
AWS_SESSION_TOKEN=$(echo "$EVENT" | jq -r '.aws_session_token // empty')

# ✅ Set AWS Credentials ONLY if they exist in the payload
if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
  echo "🔑 Setting AWS Credentials from payload..."
  export AWS_ACCESS_KEY_ID
  export AWS_SECRET_ACCESS_KEY
  export AWS_SESSION_TOKEN
else
  echo "🔒 No AWS credentials provided. Using IAM Role or default AWS credentials."
fi

# ✅ Prepare the workspace in /tmp
WORK_DIR="/tmp/terraform_workspace"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# ✅ Decode and extract Terraform code
echo "📦 Decoding and extracting Terraform code..."
echo "$BASE64_ZIPPED_TF_CODE" | base64 -d > terraform.zip
unzip -o terraform.zip
rm -f terraform.zip

# ✅ Decode and store backend configuration
echo "📝 Decoding backend configuration..."
echo "$BASE64_BACKEND_HCL" | base64 -d > backend.hcl

# ✅ Initialize Terraform with backend
echo "🔄 Running Terraform init..."
terraform init -backend-config=backend.hcl

# ✅ Execute Terraform command
echo "⚙️ Executing Terraform command: terraform $TF_COMMAND"

case "$TF_COMMAND" in
  "init")
    terraform init -backend-config=backend.hcl
    ;;
  "plan")
    terraform init -backend-config=backend.hcl
    terraform plan
    ;;
  "apply")
    terraform init -backend-config=backend.hcl
    terraform plan -out=tfplan
    terraform apply -auto-approve tfplan
    ;;
  "destroy")
    terraform init -backend-config=backend.hcl
    terraform destroy -auto-approve
    ;;
  *)
    echo "❌ ERROR: Invalid Terraform command: $TF_COMMAND"
    exit 1
    ;;
esac

echo "✅ Terraform execution completed successfully!"
