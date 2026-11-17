variable "region" {
  type    = string
  default = "us-east-2"
}

variable "aws_profile" {
  description = "AWS CLI profile with admin rights, used only for this one-time bootstrap."
  type        = string
  default     = "default"
}

variable "github_owner" {
  type    = string
  default = "ArchitectKeita"
}

variable "github_repo" {
  type    = string
  default = "aws-cicd-pipeline"
}

variable "service_name" {
  description = "Name prefix of everything the pipeline is allowed to deploy. The apply role can touch nothing else."
  type        = string
  default     = "cicd-demo"
}

variable "create_oidc_provider" {
  description = "An account can hold only one GitHub OIDC provider. Set false if another project already created it."
  type        = bool
  default     = true
}
