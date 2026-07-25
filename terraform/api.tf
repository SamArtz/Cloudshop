# =============================================================================
# API Gateway REST — punto de entrada único del backend
# =============================================================================

resource "aws_api_gateway_rest_api" "main" {
  name        = "${local.name_prefix}-api"
  description = "CloudShop Enterprise REST API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-api" })
}

# --- JWT Authorizer (TOKEN) ---
resource "aws_api_gateway_authorizer" "jwt" {
  name                             = "${local.name_prefix}-jwt-authorizer"
  rest_api_id                      = aws_api_gateway_rest_api.main.id
  authorizer_uri                   = aws_lambda_function.authorizer.invoke_arn
  type                             = "TOKEN"
  identity_source                  = "method.request.header.Authorization"
  authorizer_result_ttl_in_seconds = 60
}

resource "aws_lambda_permission" "apigw_authorizer" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/authorizers/${aws_api_gateway_authorizer.jwt.id}"
}

# --- Deployment + Stage (redespliega cuando cambian integraciones) ---
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeploy = sha1(jsonencode([
      # Auth
      aws_api_gateway_integration.auth_public,
      aws_api_gateway_integration.auth_public_options,
      aws_api_gateway_integration.users_any,
      aws_api_gateway_integration.users_options,
      aws_api_gateway_integration.users_proxy_any,
      aws_api_gateway_integration.users_proxy_options,
      # Catalog
      aws_api_gateway_integration.catalog_any,
      aws_api_gateway_integration.catalog_options,
      # Orders
      aws_api_gateway_integration.orders_any,
      aws_api_gateway_integration.orders_options,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.auth_public,
    aws_api_gateway_integration.auth_public_options,
    aws_api_gateway_integration.users_any,
    aws_api_gateway_integration.users_options,
    aws_api_gateway_integration.users_proxy_any,
    aws_api_gateway_integration.users_proxy_options,
    aws_api_gateway_integration.catalog_any,
    aws_api_gateway_integration.catalog_options,
    aws_api_gateway_integration.orders_any,
    aws_api_gateway_integration.orders_options,
  ]
}

resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.stage_name

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      latency        = "$context.responseLatency"
      authorizer     = "$context.authorizer.error"
    })
  }

  xray_tracing_enabled = false

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-${var.stage_name}" })

  depends_on = [aws_api_gateway_account.main]
}

# CloudWatch role para API Gateway (logs de acceso / métricas)
resource "aws_iam_role" "apigw_cloudwatch" {
  name = "${local.name_prefix}-apigw-cw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "apigw_cloudwatch" {
  role       = aws_iam_role.apigw_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.apigw_cloudwatch.arn
}

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/${local.name_prefix}"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------------------
# Helper local: métodos CORS MOCK reutilizables vía módulos implícitos
# (definidos junto a cada recurso en auth/catalog/orders)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}
