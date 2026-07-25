# =============================================================================
# Amazon EventBridge — Arquitectura basada en eventos (PDF sección 6)
#
# Flujo Caso 2 / integración eventos:
#   Order Service ──PutEvents──► Bus cloudshop
#                                      │
#                      OrderCreated ───┼──► Lambda notifications ──► SES + Audit
#                      OrderCancelled ─┘
# =============================================================================

resource "aws_cloudwatch_event_bus" "cloudshop" {
  name = "${local.name_prefix}-events"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-events" })
}

# Archivo de eventos (evidencia de despliegue / depuración)
resource "aws_cloudwatch_event_archive" "cloudshop" {
  count            = var.enable_event_archive ? 1 : 0
  name             = "${local.name_prefix}-events-archive"
  event_source_arn = aws_cloudwatch_event_bus.cloudshop.arn
  retention_days   = 7
  description      = "Archivo de eventos CloudShop (OrderCreated, OrderCancelled)"
}

# --- Regla: pedido creado ---
resource "aws_cloudwatch_event_rule" "order_created" {
  name           = "${local.name_prefix}-order-created"
  description    = "Dispara notificaciones SES cuando se crea un pedido"
  event_bus_name = aws_cloudwatch_event_bus.cloudshop.name

  event_pattern = jsonencode({
    source      = ["cloudshop.orders"]
    detail-type = ["OrderCreated"]
  })

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-order-created" })
}

resource "aws_cloudwatch_event_target" "order_created_to_notifications" {
  rule           = aws_cloudwatch_event_rule.order_created.name
  event_bus_name = aws_cloudwatch_event_bus.cloudshop.name
  target_id      = "notifications-created"
  arn            = aws_lambda_function.notifications.arn
}

# --- Regla: pedido cancelado ---
resource "aws_cloudwatch_event_rule" "order_cancelled" {
  name           = "${local.name_prefix}-order-cancelled"
  description    = "Notifica por SES cuando se cancela un pedido"
  event_bus_name = aws_cloudwatch_event_bus.cloudshop.name

  event_pattern = jsonencode({
    source      = ["cloudshop.orders"]
    detail-type = ["OrderCancelled"]
  })

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-order-cancelled" })
}

resource "aws_cloudwatch_event_target" "order_cancelled_to_notifications" {
  rule           = aws_cloudwatch_event_rule.order_cancelled.name
  event_bus_name = aws_cloudwatch_event_bus.cloudshop.name
  target_id      = "notifications-cancelled"
  arn            = aws_lambda_function.notifications.arn
}

resource "aws_lambda_permission" "allow_eventbridge_created" {
  statement_id  = "AllowEventBridgeOrderCreated"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notifications.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.order_created.arn
}

resource "aws_lambda_permission" "allow_eventbridge_cancelled" {
  statement_id  = "AllowEventBridgeOrderCancelled"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notifications.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.order_cancelled.arn
}
