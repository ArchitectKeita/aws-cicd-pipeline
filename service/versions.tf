terraform {
  required_version = ">= 1.10" # S3 native state locking (use_lockfile)
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
  # Filled in by the pipeline: -backend-config="bucket=..." -backend-config="use_lockfile=true" ...
  backend "s3" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "cicd-pipeline", ManagedBy = "terraform", Layer = "service" }
  }
}
