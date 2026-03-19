output "lambda_function_name" {
  description = "The name of the Lambda function"
  value       = module.this__lambda_function.lambda_function_name
}

output "s3_bucket_name" {
  description = "The S3 bucket used for Terraform output"
  value       = local.save_to_s3 ? local.s3_bucket_name : null
}