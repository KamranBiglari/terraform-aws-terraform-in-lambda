# Create an AWS ECR Repository
resource "aws_ecr_repository" "this" {
  count                = var.create_ecr ? 1 : 0
  name                 = var.ecr_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Copy terraform code to the terraform-workspaces directory
resource "local_file" "copy_terraform_code" {
  for_each = toset([for file in local.terraform_code_source_files : file if !contains(var.terraform_code_source_exclude, file)])
  filename       = "${path.module}/${var.terraform_code_destination_path}/${each.value}"
  content_base64 = filebase64("${var.terraform_code_source_path}/${each.value}")
}

# Define Docker Image
resource "docker_image" "this" {
  name = "${aws_ecr_repository.this[0].repository_url}:${var.terraform_version}-${local.current_time}"
  build {
    context    = "${path.module}/."
    dockerfile = "Dockerfile"
    tag = [
      "${aws_ecr_repository.this[0].repository_url}:${var.terraform_version}-${local.current_time}"
    ]
    build_args = {
      TERRAFORM_VERSION = "${var.terraform_version}"
      TERRAFORM_CODE_DESTINATION_PATH = "${path.module}/${var.terraform_code_destination_path}/"
    }
  }
  depends_on = [ local_file.copy_terraform_code ]
}

resource "docker_registry_image" "this" {
  name          = docker_image.this.name
  keep_remotely = true
}

# S3 Bucket for Terraform output (optional)
resource "aws_s3_bucket" "terraform_output" {
  count  = var.create_save_terraform_output_to_s3 ? 1 : 0
  bucket = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.function_name}-terraform-output"
}

resource "aws_s3_bucket_versioning" "terraform_output" {
  count  = var.create_save_terraform_output_to_s3 ? 1 : 0
  bucket = aws_s3_bucket.terraform_output[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_output" {
  count  = var.create_save_terraform_output_to_s3 ? 1 : 0
  bucket = aws_s3_bucket.terraform_output[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_output" {
  count  = var.create_save_terraform_output_to_s3 ? 1 : 0
  bucket = aws_s3_bucket.terraform_output[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

module "this__lambda_function_sg" {
    source  = "terraform-aws-modules/security-group/aws"
    version = "~> 5.0"
    
    count = var.function_create_sg ? 1 : 0
    
    name        = "${var.function_name}-sg"
    description = "Security Group for Lambda function"
    vpc_id      = var.function_vpc_id
    
    egress_with_cidr_blocks = [
        {
            from_port   = 0
            to_port     = 0
            protocol    = "-1"
            cidr_blocks = "0.0.0.0/0"
        }
    ]
}

module "this__lambda_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.20"

  function_name = var.function_name
  description   = "Lambda function running Terraform in a Docker container"
  create_role   = var.create_role
  create_package = false

  # Use Docker Image from ECR
  image_uri    = docker_image.this.name
  package_type = "Image"

  # Optional - Set Memory & Timeout
  memory_size = var.function_memory_size
  timeout     = var.function_timeout
  ephemeral_storage_size = var.ephemeral_storage_size
  
  # Environment Variables (Optional)
  environment_variables = merge(
    var.function_environment_variables,
    local.save_to_s3 ? {
      SAVE_OUTPUT_TO_S3 = "true"
      S3_BUCKET_NAME    = local.s3_bucket_name
      S3_KEY_PREFIX     = var.s3_key_prefix
    } : {}
  )

  # S3 Output Policy
  attach_policy_json = local.save_to_s3
  policy_json = local.save_to_s3 ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "arn:aws:s3:::${local.s3_bucket_name}/${var.s3_key_prefix}/*"
      }
    ]
  }) : null

  # VPC Configuration
  vpc_subnet_ids         = var.function_vpc_subnet_ids
  vpc_security_group_ids = var.function_create_sg ? [module.this__lambda_function_sg[0].this_security_group_id] : []
  attach_network_policy  = var.function_attach_network_policy

  attach_cloudwatch_logs_policy = true
  cloudwatch_logs_retention_in_days = var.function_cloudwatch_logs_retention_in_days

  depends_on = [ docker_registry_image.this ]
}
