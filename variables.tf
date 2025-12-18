variable "terraform_version" {
  description = "The version of Terraform to use"
  default     = "1.11"
}

variable "create_ecr" {
  description = "Create an ECR Repository"
  default     = true
}

variable "ecr_name" {
  description = "The name of the ECR Repository"
  default = "terraform-in-lambda-ecr"
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
  default     = 4096
}

variable "ephemeral_storage_size" {
  description = "The ephemeral storage size for the Lambda function"
  default     = 4096
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

variable "terraform_code_source_path" {
  description = "The path to the Terraform code source"
  default     = null
}

variable "terraform_code_source_exclude" {
  description = "The paths to exclude from the Terraform code source"
  default     = []
}

variable "terraform_code_destination_path" {
  description = "The path to the Terraform code destination"
  default     = "terraform.d"
}

