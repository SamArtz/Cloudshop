variable "aws_region" {
  description = "Región de AWS para el backend (API, Lambdas, DynamoDB, SES, EventBridge)"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefijo de nombres de recursos"
  type        = string
  default     = "cloudshop"
}

variable "stage_name" {
  description = "Stage de API Gateway / ambiente (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "ses_sender_email" {
  description = "Correo remitente verificado en Amazon SES"
  type        = string
}

variable "ses_verify_sender" {
  description = "Si Terraform crea la verificación de identidad SES del remitente"
  type        = bool
  default     = true
}

variable "jwt_expiration_hours" {
  description = "Vigencia del JWT en horas"
  type        = number
  default     = 24
}

variable "log_retention_days" {
  description = "Retención de logs en CloudWatch"
  type        = number
  default     = 14
}

variable "upload_frontend" {
  description = "Si true, Terraform sube los archivos de /frontend al bucket S3"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Máximo de requests por IP en 5 minutos (WAF rate-based)"
  type        = number
  default     = 2000
}

variable "enable_event_archive" {
  description = "Si true, archiva eventos del bus EventBridge (útil para evidencias)"
  type        = bool
  default     = true
}
