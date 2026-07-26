output "api_base_url" {
  description = "URL base del API Gateway (stage)"
  value       = "https://${aws_api_gateway_rest_api.main.id}.execute-api.${var.aws_region}.amazonaws.com/${var.stage_name}"
}

output "api_id" {
  description = "ID del REST API"
  value       = aws_api_gateway_rest_api.main.id
}

output "frontend_url" {
  description = "URL HTTPS del frontend (CloudFront)"
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "frontend_bucket" {
  description = "Bucket S3 del frontend"
  value       = aws_s3_bucket.frontend.bucket
}

output "event_bus_name" {
  description = "Bus de EventBridge"
  value       = aws_cloudwatch_event_bus.cloudshop.name
}

output "order_created_rule" {
  description = "Regla EventBridge OrderCreated"
  value       = aws_cloudwatch_event_rule.order_created.name
}

output "order_cancelled_rule" {
  description = "Regla EventBridge OrderCancelled"
  value       = aws_cloudwatch_event_rule.order_cancelled.name
}

output "audit_logs_table" {
  description = "Tabla DynamoDB de auditoría"
  value       = aws_dynamodb_table.audit_logs.name
}

output "users_table" {
  value = aws_dynamodb_table.users.name
}

output "products_table" {
  value = aws_dynamodb_table.products.name
}

output "stores_table" {
  value = aws_dynamodb_table.stores.name
}

output "carts_table" {
  value = aws_dynamodb_table.carts.name
}

output "orders_table" {
  value = aws_dynamodb_table.orders.name
}

output "ses_sender_email" {
  description = "Remitente SES (debe estar verificado)"
  value       = var.ses_sender_email
}

output "cloudwatch_dashboard" {
  description = "Nombre del dashboard de CloudWatch (Caso 3)"
  value       = aws_cloudwatch_dashboard.cloudshop_monitoring.dashboard_name
}

output "lambda_functions" {
  description = "Lambdas desplegadas"
  value = {
    auth          = aws_lambda_function.auth_service.function_name
    authorizer    = aws_lambda_function.authorizer.function_name
    catalog       = aws_lambda_function.catalog_service.function_name
    orders        = aws_lambda_function.order_service.function_name
    notifications = aws_lambda_function.notifications.function_name
    reports       = aws_lambda_function.report_service.function_name
  }
}

output "report_service_function_name" {
  description = "Nombre de la Lambda Report Service"
  value       = aws_lambda_function.report_service.function_name
}

output "reports_endpoint_path" {
  description = "Ruta del dashboard ejecutivo"
  value       = "/${var.stage_name}/reports/dashboard"
}
