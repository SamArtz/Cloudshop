# CloudShop Enterprise — Providers (stack unificado)

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project = "CloudShop"
      IaC     = "Terraform"
      Stage   = var.stage_name
    }
  }
}

# WAF asociado a CloudFront debe vivir en us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project = "CloudShop"
      IaC     = "Terraform"
      Stage   = var.stage_name
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
