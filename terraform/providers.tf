# CloudShop Enterprise - Módulo Carrito & Pedidos (Órdenes)
# Nota: si el stack compartido del equipo ya define el provider/terraform block,
# elimina este archivo y reutiliza el del stack raíz.

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
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project = "CloudShop"
      Module  = "Orders"
      IaC     = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
