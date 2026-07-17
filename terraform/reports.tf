locals {
  report_service_name       = "${local.name_prefix}-report-service"
  monitoring_dashboard_name = "${local.name_prefix}-monitoring"
}

# ===========================================================================
# Empaquetado - Report Service
# ===========================================================================
resource "null_resource" "stage_report_service" {
  triggers = {
    handler     = filemd5("${path.module}/../src/report_service/handler.py")
    repository  = filemd5("${path.module}/../src/report_service/repository.py")
    analytics   = filemd5("${path.module}/../src/report_service/analytics.py")
    permissions = filemd5("${path.module}/../src/report_service/permissions.py")
    shared_err  = filemd5("${path.module}/../src/shared/errors.py")
    shared_resp = filemd5("${path.module}/../src/shared/response.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      DST="${path.module}/.build/report_service"
      rm -rf "$DST" && mkdir -p "$DST"
      cp ${path.module}/../src/report_service/*.py "$DST/"
      cp -R ${path.module}/../src/shared "$DST/shared"
    EOT
  }
}

data "archive_file" "report_service" {
  type        = "zip"
  source_dir  = "${path.module}/.build/report_service"
  output_path = "${path.module}/.build/report_service.zip"
  depends_on  = [null_resource.stage_report_service]
}

# ===========================================================================
# IAM - Report Service (solo lectura y mínimo privilegio)
# ===========================================================================
resource "aws_iam_role" "report_service" {
  name               = "${local.report_service_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "report_service_basic" {
  role       = aws_iam_role.report_service.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "report_service" {
  statement {
    sid     = "ReadOrders"
    actions = ["dynamodb:Scan", "dynamodb:Query", "dynamodb:GetItem"]
    resources = [
      aws_dynamodb_table.orders.arn,
      "${aws_dynamodb_table.orders.arn}/index/*",
    ]
  }

  statement {
    sid       = "ReadProducts"
    actions   = ["dynamodb:Scan", "dynamodb:GetItem"]
    resources = [var.products_table_arn]
  }

  statement {
    sid       = "ReadStores"
    actions   = ["dynamodb:Scan", "dynamodb:GetItem"]
    resources = [var.stores_table_arn]
  }
}

resource "aws_iam_role_policy" "report_service" {
  name   = "${local.report_service_name}-policy"
  role   = aws_iam_role.report_service.id
  policy = data.aws_iam_policy_document.report_service.json
}

# ===========================================================================
# CloudWatch Logs + Lambda Report Service
# ===========================================================================
resource "aws_cloudwatch_log_group" "report_service" {
  name              = "/aws/lambda/${local.report_service_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "report_service" {
  function_name    = local.report_service_name
  role             = aws_iam_role.report_service.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.report_service.output_path
  source_code_hash = data.archive_file.report_service.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      STAGE          = var.stage_name
      ORDERS_TABLE   = aws_dynamodb_table.orders.name
      PRODUCTS_TABLE = var.products_table_name
      STORES_TABLE   = var.stores_table_name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.report_service,
    aws_iam_role_policy_attachment.report_service_basic,
    aws_iam_role_policy.report_service,
  ]
}

# ===========================================================================
# API Gateway - GET /reports/dashboard
# ===========================================================================
resource "aws_api_gateway_resource" "reports" {
  rest_api_id = var.rest_api_id
  parent_id   = var.rest_api_root_resource_id
  path_part   = "reports"
}

resource "aws_api_gateway_resource" "reports_dashboard" {
  rest_api_id = var.rest_api_id
  parent_id   = aws_api_gateway_resource.reports.id
  path_part   = "dashboard"
}

resource "aws_api_gateway_method" "reports_dashboard_get" {
  rest_api_id   = var.rest_api_id
  resource_id   = aws_api_gateway_resource.reports_dashboard.id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = var.authorizer_id
}

resource "aws_api_gateway_integration" "reports_dashboard_get" {
  rest_api_id             = var.rest_api_id
  resource_id             = aws_api_gateway_resource.reports_dashboard.id
  http_method             = aws_api_gateway_method.reports_dashboard_get.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.report_service.invoke_arn
}

resource "aws_api_gateway_method" "reports_dashboard_options" {
  rest_api_id   = var.rest_api_id
  resource_id   = aws_api_gateway_resource.reports_dashboard.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "reports_dashboard_options" {
  rest_api_id = var.rest_api_id
  resource_id = aws_api_gateway_resource.reports_dashboard.id
  http_method = aws_api_gateway_method.reports_dashboard_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "reports_dashboard_options" {
  rest_api_id = var.rest_api_id
  resource_id = aws_api_gateway_resource.reports_dashboard.id
  http_method = aws_api_gateway_method.reports_dashboard_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "reports_dashboard_options" {
  rest_api_id = var.rest_api_id
  resource_id = aws_api_gateway_resource.reports_dashboard.id
  http_method = aws_api_gateway_method.reports_dashboard_options.http_method
  status_code = aws_api_gateway_method_response.reports_dashboard_options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.reports_dashboard_options]
}

resource "aws_lambda_permission" "apigw_report_service" {
  statement_id  = "AllowAPIGatewayInvokeReportService"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.report_service.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.rest_api_execution_arn}/*/GET/reports/dashboard"
}

# Activa métricas detalladas en todos los métodos del stage compartido.
resource "aws_api_gateway_method_settings" "cloudwatch_metrics" {
  count       = var.enable_api_gateway_method_metrics ? 1 : 0
  rest_api_id = var.rest_api_id
  stage_name  = var.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
  }
}

# Deployment independiente del módulo. El stage final puede ser administrado por
# el main.tf integrador de la persona 6.
resource "aws_api_gateway_deployment" "reports" {
  rest_api_id = var.rest_api_id

  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_resource.reports.id,
      aws_api_gateway_resource.reports_dashboard.id,
      aws_api_gateway_method.reports_dashboard_get.id,
      aws_api_gateway_integration.reports_dashboard_get.id,
      aws_api_gateway_integration.reports_dashboard_options.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.reports_dashboard_get,
    aws_api_gateway_integration.reports_dashboard_options,
  ]
}

# ===========================================================================
# CloudWatch - métricas, filtros, alarmas y dashboard (Caso de prueba 3)
# ===========================================================================
resource "aws_cloudwatch_log_metric_filter" "authorizer_errors" {
  count          = var.authorizer_log_group_name == "" ? 0 : 1
  name           = "${local.name_prefix}-authentication-errors"
  pattern        = "\"Authorizer deny/unauthorized\""
  log_group_name = var.authorizer_log_group_name

  metric_transformation {
    name      = "AuthenticationErrors"
    namespace = "CloudShop/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "report_service_errors" {
  alarm_name          = "${local.report_service_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Detecta errores de ejecución en Report Service"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.report_service.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "report_latency" {
  alarm_name          = "${local.report_service_name}-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DashboardLatency"
  namespace           = "CloudShop/ReportService"
  period              = 300
  statistic           = "Average"
  threshold           = var.report_latency_alarm_ms
  alarm_description   = "Latencia promedio alta al generar el dashboard ejecutivo"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Service = "ReportService"
    Stage   = var.stage_name
  }
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx" {
  alarm_name          = "${local.name_prefix}-api-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Errores 5XX detectados en API Gateway"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = var.api_gateway_name
    Stage   = var.stage_name
  }
}

resource "aws_cloudwatch_dashboard" "cloudshop_monitoring" {
  dashboard_name = local.monitoring_dashboard_name

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# CloudShop Enterprise — Monitoreo\nMétricas de Report Service, Lambda, API Gateway y seguridad."
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Solicitudes del dashboard"
          region = var.aws_region
          view   = "timeSeries"
          period = 300
          stat   = "Sum"
          metrics = [
            ["CloudShop/ReportService", "DashboardRequests", "Service", "ReportService", "Stage", var.stage_name]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Latencia promedio del dashboard (ms)"
          region = var.aws_region
          view   = "timeSeries"
          period = 300
          stat   = "Average"
          metrics = [
            ["CloudShop/ReportService", "DashboardLatency", "Service", "ReportService", "Stage", var.stage_name]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Errores y accesos denegados"
          region = var.aws_region
          view   = "timeSeries"
          period = 300
          stat   = "Sum"
          metrics = [
            ["CloudShop/ReportService", "ApplicationErrors", "Service", "ReportService", "Stage", var.stage_name],
            ["CloudShop/ReportService", "AuthorizationDenied", "Service", "ReportService", "Stage", var.stage_name],
            ["CloudShop/Security", "AuthenticationErrors"]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "Report Service Lambda"
          region = var.aws_region
          view   = "timeSeries"
          period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", local.report_service_name, { stat = "Sum" }],
            ["AWS/Lambda", "Errors", "FunctionName", local.report_service_name, { stat = "Sum" }],
            ["AWS/Lambda", "Duration", "FunctionName", local.report_service_name, { stat = "Average", yAxis = "right" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "API Gateway — tráfico, latencia y errores"
          region = var.aws_region
          view   = "timeSeries"
          period = 300
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiName", var.api_gateway_name, "Stage", var.stage_name, { stat = "Sum" }],
            ["AWS/ApiGateway", "Latency", "ApiName", var.api_gateway_name, "Stage", var.stage_name, { stat = "Average", yAxis = "right" }],
            ["AWS/ApiGateway", "4XXError", "ApiName", var.api_gateway_name, "Stage", var.stage_name, { stat = "Sum" }],
            ["AWS/ApiGateway", "5XXError", "ApiName", var.api_gateway_name, "Stage", var.stage_name, { stat = "Sum" }]
          ]
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 14
        width  = 24
        height = 6
        properties = {
          title  = "Logs recientes de Report Service"
          region = var.aws_region
          view   = "table"
          query  = "SOURCE '/aws/lambda/${local.report_service_name}'\n| fields @timestamp, level, message, statusCode, errorType\n| sort @timestamp desc\n| limit 20"
        }
      }
    ]
  })
}
