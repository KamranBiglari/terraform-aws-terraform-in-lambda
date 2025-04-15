# 🚀 Create an AWS ECR Repository
resource "aws_ecr_repository" "this" {
  count                = var.create_ecr ? 1 : 0
  name                 = "terraform-in-lambda-ecr"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Copy terraform code to the terraform-workspaces directory
resource "local_file" "copy_terraform_code" {
  for_each = local.terraform_code_source_files
  filename       = "${var.terraform_code_source_path}/${each.value}"
  content_base64 = filebase64("${path.module}/${var.terraform_code_destination_path}/${each.value}")
}

# Define Docker Image
resource "docker_image" "this" {
  name = "${aws_ecr_repository.this[0].repository_url}:${var.terraform_version}-${formatdate("YYYYMMDDHHmmss", timestamp())}"
  build {
    context    = "${path.module}/."
    dockerfile = "Dockerfile"
    tag = [
      "${aws_ecr_repository.this[0].repository_url}:${var.terraform_version}"
    ]
    build_args = {
      TERRAFORM_VERSION = "${var.terraform_version}"
      TERRAFORM_CODE_DESTINATION_PATH = "${path.module}/${var.terraform_code_destination_path}"
    }
  }
}

resource "docker_registry_image" "this" {
  name          = docker_image.this.name
  keep_remotely = true
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
            cidr_blocks = ["0.0.0.0/0"]
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

  # ✅ Use Docker Image from ECR
  image_uri    = docker_image.this.name
  package_type = "Image"

  # Optional - Set Memory & Timeout
  memory_size = var.function_memory_size
  timeout     = var.function_timeout

  # Environment Variables (Optional)
  environment_variables = var.function_environment_variables

  # VPC Configuration
  vpc_subnet_ids         = var.function_vpc_subnet_ids
  vpc_security_group_ids = [module.this__lambda_function_sg[*].this_security_group_id]
  attach_network_policy  = var.function_attach_network_policy

  attach_cloudwatch_logs_policy = true

  depends_on = [ docker_registry_image.this ]
}