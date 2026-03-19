locals {
  current_time                = formatdate("YYYYMMDDHHmmss", timestamp())
  terraform_code_source_files = var.terraform_code_source_path != null ? fileset(var.terraform_code_source_path, "**") : []
  save_to_s3                  = var.create_save_terraform_output_to_s3 || var.s3_bucket_name != ""
  s3_bucket_name              = var.create_save_terraform_output_to_s3 ? aws_s3_bucket.terraform_output[0].id : var.s3_bucket_name
}