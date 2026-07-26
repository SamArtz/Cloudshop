# =============================================================================
# CloudWatch — Alarmas de Lambdas core (PDF sección 8)
# El dashboard unificado vive en reports.tf (Caso 3).
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "auth_errors" {
  alarm_name          = "${local.auth_service_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Errores en Auth Service"
  treat_missing_data  = "notBreaching"
  dimensions = {
    FunctionName = aws_lambda_function.auth_service.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "order_service_errors" {
  alarm_name          = "${local.order_service_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Errores en Order Service"
  treat_missing_data  = "notBreaching"
  dimensions = {
    FunctionName = aws_lambda_function.order_service.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "notifications_errors" {
  alarm_name          = "${local.notifications_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Errores en Notifications (SES/EventBridge)"
  treat_missing_data  = "notBreaching"
  dimensions = {
    FunctionName = aws_lambda_function.notifications.function_name
  }
}
