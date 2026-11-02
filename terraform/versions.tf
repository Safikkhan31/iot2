terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Recommended: keep state in an encrypted S3 bucket with a DynamoDB lock table.
  # The state file contains secrets (generated passwords), so never commit it.
  # backend "s3" {
  #   bucket         = "your-tf-state-bucket"
  #   key            = "coldchain/terraform.tfstate"
  #   region         = "ap-south-1"
  #   dynamodb_table = "your-tf-lock-table"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
