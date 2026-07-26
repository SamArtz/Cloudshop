output "carts_table_name" {
  description = "Tabla DynamoDB de carritos"
  value       = aws_dynamodb_table.carts.name
}

output "orders_table_name" {
  description = "Tabla DynamoDB de pedidos"
  value       = aws_dynamodb_table.orders.name
}

output "order_service_function_name" {
  description = "Nombre de la Lambda Order Service"
  value       = aws_lambda_function.order_service.function_name
}

output "notifications_function_name" {
  description = "Nombre de la Lambda de notificaciones (SES)"
  value       = aws_lambda_function.notifications.function_name
}

output "event_bus_name" {
  description = "Bus de EventBridge de CloudShop"
  value       = aws_cloudwatch_event_bus.cloudshop.name
}

output "order_created_rule" {
  description = "Regla de EventBridge OrderCreated"
  value       = aws_cloudwatch_event_rule.order_created.name
}

output "api_deployment_id" {
  description = "ID del deployment de API Gateway (redesplegar el stage compartido si es necesario)"
  value       = aws_api_gateway_deployment.orders.id
}

output "report_service_function_name" {
  description = "Nombre de la Lambda Report Service"
  value       = aws_lambda_function.report_service.function_name
}

output "cloudwatch_dashboard_name" {
  description = "Dashboard de CloudWatch para el Caso de prueba 3"
  value       = aws_cloudwatch_dashboard.cloudshop_monitoring.dashboard_name
}

output "reports_api_deployment_id" {
  description = "Deployment de API Gateway que incluye GET /reports/dashboard"
  value       = aws_api_gateway_deployment.reports.id
}

output "reports_endpoint_path" {
  description = "Ruta del dashboard ejecutivo"
  value       = "/${var.stage_name}/reports/dashboard"
}
