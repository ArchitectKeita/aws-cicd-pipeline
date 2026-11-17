variable "region" {
  type    = string
  default = "us-east-2"
}

variable "service_name" {
  description = "Must match the bootstrap's service_name: the pipeline's roles can only touch resources with this prefix."
  type        = string
  default     = "cicd-demo"
}

variable "boundary_arn" {
  description = "The permissions boundary from the bootstrap. Every role this layer creates must carry it."
  type        = string
}

variable "commit_sha" {
  description = "Set by the pipeline to the commit being deployed."
  type        = string
  default     = "local"
}

variable "app_version" {
  type    = string
  default = "1.0.0"
}

variable "simulate_bad_deploy" {
  description = "Auto-rollback demo: true ships a build whose /health returns 503, so the smoke test fails and the pipeline rolls back."
  type        = bool
  default     = false
}
