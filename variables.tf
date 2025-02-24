variable "terraform_version" {
  description = "The version of Terraform to use"
  default     = "hashicorp/terraform:1.10"
}

variable "create_ecr" {
  description = "Create an ECR Repository"
  default     = true
}

variable "function_name" {
  description = "The name of the Lambda function"
  default     = "terraform-lambda-function"
}

variable "function_timeout" {
  description = "The timeout for the Lambda function"
  default     = 900
}

variable "function_memory_size" {
  description = "The memory size for the Lambda function"
  default     = 2048
}

variable "function_environment_variables" {
  description = "The environment variables for the Lambda function"
  default     = {}
}

variable "function_vpc" {
  description = "values for the VPC configuration"
  default = {
    vpc_subnet_ids         = []
    vpc_security_group_ids = []
    attach_network_policy  = false
  }
}

variable "create_role" {
  description = "Create an IAM Role"
  default     = false
}