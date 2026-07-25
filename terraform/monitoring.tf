# =============================================================================
# CloudWatch — Monitoreo (PDF sección 8)
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

resource "aws_cloudwatch_dashboard" "cloudshop" {
  dashboard_name = "${local.name_prefix}-monitoring"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Errors"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.auth_service.function_name],
            [".", ".", ".", aws_lambda_function.catalog_service.function_name],
            [".", ".", ".", aws_lambda_function.order_service.function_name],
            [".", ".", ".", aws_lambda_function.notifications.function_name],
          ]
          view    = "timeSeries"
          stacked = false
          period  = 60
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "API Gateway Latency / 4XX / 5XX"
          region = var.aws_region
          metrics = [
            ["AWS/ApiGateway", "Latency", "ApiName", aws_api_gateway_rest_api.main.name, "Stage", var.stage_name],
            [".", "4XXError", ".", ".", ".", "."],
            [".", "5XXError", ".", ".", ".", "."],
          ]
          view   = "timeSeries"
          period = 60
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "EventBridge Invocations (OrderCreated)"
          region = var.aws_region
          metrics = [
            ["AWS/Events", "TriggeredRules", "RuleName", aws_cloudwatch_event_rule.order_created.name],
            [".", "Invocations", "RuleName", aws_cloudwatch_event_rule.order_created.name],
            [".", "FailedInvocations", "RuleName", aws_cloudwatch_event_rule.order_created.name],
          ]
          view   = "timeSeries"
          period = 60
        }
      }
    ]
  })
}
