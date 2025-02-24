# 🚀 Create an AWS ECR Repository
resource "aws_ecr_repository" "this" {
  count                = var.create_ecr ? 1 : 0
  name                 = "terraform-in-lambda-ecr"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Define Docker Image
resource "docker_image" "this" {
  name = "${aws_ecr_repository.my_ecr.repository_url}:${var.terraform_version}"
  build {
    context    = "."
    dockerfile = "Dockerfile"
    build_arg = {
      TERRAFORM_VERSION = "${var.terraform_version}"
    }
  }
}

resource "docker_registry_image" "this" {
  name          = docker_image.this.name
  keep_remotely = true
}

module "this__lambda_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.20"

  function_name = var.function_name
  description   = "Lambda function running Terraform in a Docker container"
  create_role   = var.create_role

  # ✅ Use Docker Image from ECR
  image_uri    = docker_image.this.name
  package_type = "Image"

  # Optional - Set Memory & Timeout
  memory_size = var.function_memory_size
  timeout     = var.function_timeout

  # Environment Variables (Optional)
  environment_variables = var.function_environment_variables

  # VPC Configuration
  vpc_subnet_ids         = var.function_vpc.vpc_subnet_ids
  vpc_security_group_ids = var.function_vpc.vpc_security_group_ids
  attach_network_policy  = var.function_vpc.attach_network_policy

  attach_cloudwatch_logs_policy = true
}