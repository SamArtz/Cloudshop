# =============================================================================
# CloudShop Enterprise — Stack raíz (integración final)
#
# Caso de prueba 4: despliegue completo mediante Terraform.
#
# Este archivo orquesta el stack. Los recursos viven en:
#   dynamodb.tf  → tablas (Users, AuditLogs, Products, Stores, Carts, Orders)
#   api.tf       → API Gateway REST + Authorizer JWT + stage
#   auth.tf      → Auth Service + Secrets Manager + IAM + rutas /auth /users
#   catalog.tf   → Catalog Service + rutas /products /stores
#   orders.tf    → Order Service + Notifications + rutas /cart /orders
#   events.tf    → EventBridge (bus, reglas OrderCreated / OrderCancelled)
#   ses.tf       → Amazon SES (identidad remitente)
#   frontend.tf  → S3 + CloudFront + WAF
#   monitoring.tf→ CloudWatch (logs + alarmas)
# =============================================================================

locals {
  name_prefix = "${var.project}-${var.stage_name}"

  common_tags = {
    Project = "CloudShop"
    Stage   = var.stage_name
    IaC     = "Terraform"
  }

  # Empaquetado de Lambdas (scripts/stage_lambda.py → terraform/.build/)
  # Ruta solo para filemd5; el local-exec usa working_dir + comando relativo
  # para evitar fallos en Windows cuando el path tiene espacios (ej. "proyecto final").
  stage_script     = "${path.module}/../scripts/stage_lambda.py"
  stage_working_dir = "${path.module}/.."
}
