locals {
  terraform_code_source_files = var.terraform_code_source_path != null ? fileset(var.terraform_code_source_path, "**") : []
}