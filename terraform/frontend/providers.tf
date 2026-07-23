# CloudShop Enterprise - Parte 5: Frontend & Entrada
# S3 + CloudFront + AWS WAF (stack independiente)

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project = "CloudShop"
      Module  = "Frontend"
      IaC     = "Terraform"
      Stage   = var.stage_name
    }
  }
}

# WAF para CloudFront DEBE crearse en us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project = "CloudShop"
      Module  = "Frontend"
      IaC     = "Terraform"
      Stage   = var.stage_name
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
