variable "aws_region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefijo de nombres de recursos"
  type        = string
  default     = "cloudshop"
}

variable "stage_name" {
  description = "Stage de API Gateway (debe coincidir con el del stack compartido)"
  type        = string
  default     = "dev"
}

# ---------------------------------------------------------------------------
# Recursos COMPARTIDOS creados por otros módulos (auth / catalog).
# Se pasan por variables para no duplicarlos. Ver terraform.tfvars.example.
# ---------------------------------------------------------------------------
variable "rest_api_id" {
  description = "ID del REST API de API Gateway compartido"
  type        = string
}

variable "rest_api_root_resource_id" {
  description = "ID del recurso raíz (/) del REST API compartido"
  type        = string
}

variable "rest_api_execution_arn" {
  description = "execution_arn del REST API compartido (para permisos de invocación Lambda)"
  type        = string
}

variable "authorizer_id" {
  description = "ID del Lambda Authorizer (JWT) compartido"
  type        = string
}

variable "products_table_name" {
  description = "Nombre de la tabla DynamoDB de productos (creada por catalog)"
  type        = string
}

variable "products_table_arn" {
  description = "ARN de la tabla DynamoDB de productos (para IAM de mínimo privilegio)"
  type        = string
}

variable "audit_table_name" {
  description = "Nombre de la tabla DynamoDB de auditoría (creada por auth)"
  type        = string
}

variable "audit_table_arn" {
  description = "ARN de la tabla DynamoDB de auditoría"
  type        = string
}

# ---------------------------------------------------------------------------
# SES
# ---------------------------------------------------------------------------
variable "ses_sender_email" {
  description = "Correo remitente verificado en SES"
  type        = string
}

variable "ses_verify_sender" {
  description = "Si Terraform debe crear la verificación de identidad SES del remitente"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Retención de logs en CloudWatch"
  type        = number
  default     = 14
}

# ---------------------------------------------------------------------------
# Report Service y CloudWatch (Módulo 6)
# ---------------------------------------------------------------------------
variable "stores_table_name" {
  description = "Nombre de la tabla DynamoDB de tiendas (creada por catalog)"
  type        = string
}

variable "stores_table_arn" {
  description = "ARN de la tabla DynamoDB de tiendas"
  type        = string
}

variable "api_gateway_name" {
  description = "Nombre del REST API; se usa como dimensión de CloudWatch"
  type        = string
  default     = "cloudshop-api"
}

variable "authorizer_log_group_name" {
  description = "Log group de la Lambda Authorizer para contar errores de autenticación; vacío desactiva el filtro"
  type        = string
  default     = ""
}

variable "enable_api_gateway_method_metrics" {
  description = "Activa métricas detalladas de métodos en el stage compartido de API Gateway"
  type        = bool
  default     = true
}

variable "report_latency_alarm_ms" {
  description = "Umbral de alarma para la latencia promedio del dashboard, en milisegundos"
  type        = number
  default     = 3000
}
