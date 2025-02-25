variable "terraform_version" {
  description = "The version of Terraform to use"
  default     = "1.10"
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

variable "function_create_sg" {
  description = "Create a Security Group for the Lambda function"
  default     = false
}

variable "function_vpc_id" {
  description = "The VPC ID for the Lambda function"
  default     = ""
}

variable "function_attach_network_policy" {
  description = "Attach a network policy to the Lambda function"
  default     = false
}

variable "function_vpc_subnet_ids" {
  description = "The VPC Subnet IDs for the Lambda function"
  default     = []
}

variable "create_role" {
  description = "Create an IAM Role"
  default     = true
}