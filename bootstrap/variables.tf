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
  default = "SaintKeita"
}

variable "github_repo" {
  type    = string
  default = "aws-cicd-pipeline"
}

# GitHub now puts permanent numeric IDs in the token's "sub" claim:
#   repo:OWNER@OWNER_ID/REPO@REPO_ID:...
# They're public (github.com/api: users/OWNER and repos/OWNER/REPO), and they make the trust stronger:
# a deleted-and-recreated repo with the same name gets a new ID, so it can't take over these roles.
variable "github_owner_id" {
  type    = number
  default = 39179977
}

variable "github_repo_id" {
  type    = number
  default = 1461980926
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
