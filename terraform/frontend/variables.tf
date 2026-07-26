variable "aws_region" {
  description = "Región de AWS (el bucket S3 se crea aquí; WAF/CloudFront usan us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefijo de nombres de recursos"
  type        = string
  default     = "cloudshop"
}

variable "stage_name" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "upload_frontend" {
  description = "Si true, Terraform sube los archivos de /frontend al bucket S3"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Máximo de requests por IP en 5 minutos (regla rate-based de WAF)"
  type        = number
  default     = 2000
}
