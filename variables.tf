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

variable "function_cloudwatch_logs_retention_in_days" {
  description = "Specifies the number of days you want to retain log events in the specified log group. Possible values are: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, and 3653."
  default = 30
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

variable "tfplan2md_version" {
  description = "The version of tfplan2md to install in the Docker image"
  type        = string
  default     = "1.40.0"
}

variable "enable_tfplan2md" {
  description = "Enable generating markdown plan reports using tfplan2md"
  type        = bool
  default     = false
}

variable "create_save_terraform_output_to_s3" {
  description = "Create an S3 bucket for saving Terraform command output"
  type        = bool
  default     = false
}

variable "s3_bucket_name" {
  description = "Name of an existing S3 bucket for Terraform output. Used when create_save_terraform_output_to_s3 is false."
  type        = string
  default     = ""
}

variable "s3_key_prefix" {
  description = "S3 key prefix for Terraform output files"
  type        = string
  default     = "terraform-output"
}

