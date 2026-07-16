locals {
  name_prefix = "${var.project}-${var.stage_name}"

  order_service_name = "${local.name_prefix}-order-service"
  notifications_name = "${local.name_prefix}-notifications"

  ses_identity_arn = "arn:aws:ses:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:identity/${var.ses_sender_email}"
}

# ===========================================================================
# DynamoDB - Carrito y Pedidos (Datos)
# ===========================================================================
resource "aws_dynamodb_table" "carts" {
  name         = "${local.name_prefix}-carts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }
}

resource "aws_dynamodb_table" "orders" {
  name         = "${local.name_prefix}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "orderId"

  attribute {
    name = "orderId"
    type = "S"
  }
  attribute {
    name = "userId"
    type = "S"
  }
  attribute {
    name = "status"
    type = "S"
  }

  # Consultar pedidos de un cliente (Cliente: "consultar pedidos propios")
  global_secondary_index {
    name            = "userId-index"
    hash_key        = "userId"
    projection_type = "ALL"
  }

  # Dashboard ejecutivo: "pedidos por estado"
  global_secondary_index {
    name            = "status-index"
    hash_key        = "status"
    projection_type = "ALL"
  }
}

# ===========================================================================
# EventBridge (Arquitectura basada en eventos - PDF sección 6)
# ===========================================================================
resource "aws_cloudwatch_event_bus" "cloudshop" {
  name = "${local.name_prefix}-events"
}

resource "aws_cloudwatch_event_rule" "order_created" {
  name           = "${local.name_prefix}-order-created"
  description    = "Dispara notificaciones cuando se crea un pedido"
  event_bus_name = aws_cloudwatch_event_bus.cloudshop.name

  event_pattern = jsonencode({
    "source"      = ["cloudshop.orders"]
    "detail-type" = ["OrderCreated"]
  })
}

resource "aws_cloudwatch_event_target" "order_created_to_notifications" {
  rule           = aws_cloudwatch_event_rule.order_created.name
  event_bus_name = aws_cloudwatch_event_bus.cloudshop.name
  target_id      = "notifications"
  arn            = aws_lambda_function.notifications.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notifications.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.order_created.arn
}

# ===========================================================================
# Empaquetado de Lambdas (boto3 ya viene en el runtime -> no requiere pip)
# ===========================================================================
# order_service necesita el paquete compartido shared/, se hace staging.
resource "null_resource" "stage_order_service" {
  triggers = {
    handler     = filemd5("${path.module}/../src/order_service/handler.py")
    repository  = filemd5("${path.module}/../src/order_service/repository.py")
    permissions = filemd5("${path.module}/../src/order_service/permissions.py")
    shared_err  = filemd5("${path.module}/../src/shared/errors.py")
    shared_resp = filemd5("${path.module}/../src/shared/response.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      DST="${path.module}/.build/order_service"
      rm -rf "$DST" && mkdir -p "$DST"
      cp ${path.module}/../src/order_service/*.py "$DST/"
      cp -R ${path.module}/../src/shared "$DST/shared"
    EOT
  }
}

data "archive_file" "order_service" {
  type        = "zip"
  source_dir  = "${path.module}/.build/order_service"
  output_path = "${path.module}/.build/order_service.zip"
  depends_on  = [null_resource.stage_order_service]
}

data "archive_file" "notifications" {
  type        = "zip"
  source_dir  = "${path.module}/../src/notifications"
  output_path = "${path.module}/.build/notifications.zip"
}

# ===========================================================================
# IAM - Order Service (principio de mínimo privilegio - PDF sección 5)
# ===========================================================================
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "order_service" {
  name               = "${local.order_service_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "order_service_basic" {
  role       = aws_iam_role.order_service.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "order_service" {
  # Carrito: acceso total al ítem del propio servicio
  statement {
    sid = "CartsTable"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
    ]
    resources = [aws_dynamodb_table.carts.arn]
  }

  # Pedidos: lectura/escritura + consulta por índices
  statement {
    sid = "OrdersTable"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
      "dynamodb:Scan",
    ]
    resources = [
      aws_dynamodb_table.orders.arn,
      "${aws_dynamodb_table.orders.arn}/index/*",
    ]
  }

  # Productos: solo leer y ajustar stock (NO crear/borrar productos)
  statement {
    sid       = "ProductsStock"
    actions   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
    resources = [var.products_table_arn]
  }

  # Auditoría: solo escribir
  statement {
    sid       = "AuditWrite"
    actions   = ["dynamodb:PutItem"]
    resources = [var.audit_table_arn]
  }

  # EventBridge: publicar el evento OrderCreated
  statement {
    sid       = "PublishEvents"
    actions   = ["events:PutEvents"]
    resources = [aws_cloudwatch_event_bus.cloudshop.arn]
  }
}

resource "aws_iam_role_policy" "order_service" {
  name   = "${local.order_service_name}-policy"
  role   = aws_iam_role.order_service.id
  policy = data.aws_iam_policy_document.order_service.json
}

# ===========================================================================
# IAM - Notifications
# ===========================================================================
resource "aws_iam_role" "notifications" {
  name               = "${local.notifications_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "notifications_basic" {
  role       = aws_iam_role.notifications.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "notifications" {
  statement {
    sid       = "SendEmail"
    actions   = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = [local.ses_identity_arn]
  }
  statement {
    sid       = "AuditWrite"
    actions   = ["dynamodb:PutItem"]
    resources = [var.audit_table_arn]
  }
}

resource "aws_iam_role_policy" "notifications" {
  name   = "${local.notifications_name}-policy"
  role   = aws_iam_role.notifications.id
  policy = data.aws_iam_policy_document.notifications.json
}

# ===========================================================================
# Lambdas
# ===========================================================================
resource "aws_lambda_function" "order_service" {
  function_name    = local.order_service_name
  role             = aws_iam_role.order_service.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.order_service.output_path
  source_code_hash = data.archive_file.order_service.output_base64sha256
  timeout          = 15
  memory_size      = 256

  environment {
    variables = {
      STAGE            = var.stage_name
      CARTS_TABLE      = aws_dynamodb_table.carts.name
      ORDERS_TABLE     = aws_dynamodb_table.orders.name
      PRODUCTS_TABLE   = var.products_table_name
      AUDIT_LOGS_TABLE = var.audit_table_name
      EVENT_BUS_NAME   = aws_cloudwatch_event_bus.cloudshop.name
    }
  }
}

resource "aws_lambda_function" "notifications" {
  function_name    = local.notifications_name
  role             = aws_iam_role.notifications.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.notifications.output_path
  source_code_hash = data.archive_file.notifications.output_base64sha256
  timeout          = 15
  memory_size      = 128

  environment {
    variables = {
      AUDIT_LOGS_TABLE       = var.audit_table_name
      SES_SENDER             = var.ses_sender_email
      SES_FALLBACK_RECIPIENT = var.ses_sender_email
    }
  }
}

# ===========================================================================
# CloudWatch (Monitoreo - PDF sección 8)
# ===========================================================================
resource "aws_cloudwatch_log_group" "order_service" {
  name              = "/aws/lambda/${local.order_service_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "notifications" {
  name              = "/aws/lambda/${local.notifications_name}"
  retention_in_days = var.log_retention_days
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
  alarm_description   = "Errores en el Order Service Lambda"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.order_service.function_name
  }
}

# ===========================================================================
# SES (Notificaciones - PDF sección) : verificación del remitente
# ===========================================================================
resource "aws_ses_email_identity" "sender" {
  count = var.ses_verify_sender ? 1 : 0
  email = var.ses_sender_email
}

# ===========================================================================
# API Gateway - Rutas de Carrito y Pedidos sobre el REST API compartido
# Se usan recursos base + proxy: el enrutamiento fino lo hace el handler.
# ===========================================================================
resource "aws_api_gateway_resource" "cart" {
  rest_api_id = var.rest_api_id
  parent_id   = var.rest_api_root_resource_id
  path_part   = "cart"
}

resource "aws_api_gateway_resource" "cart_proxy" {
  rest_api_id = var.rest_api_id
  parent_id   = aws_api_gateway_resource.cart.id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_resource" "orders" {
  rest_api_id = var.rest_api_id
  parent_id   = var.rest_api_root_resource_id
  path_part   = "orders"
}

resource "aws_api_gateway_resource" "orders_proxy" {
  rest_api_id = var.rest_api_id
  parent_id   = aws_api_gateway_resource.orders.id
  path_part   = "{proxy+}"
}

locals {
  order_api_resources = {
    cart         = aws_api_gateway_resource.cart.id
    cart_proxy   = aws_api_gateway_resource.cart_proxy.id
    orders       = aws_api_gateway_resource.orders.id
    orders_proxy = aws_api_gateway_resource.orders_proxy.id
  }
}

# --- Métodos ANY protegidos por el Lambda Authorizer (JWT) ---
resource "aws_api_gateway_method" "any" {
  for_each      = local.order_api_resources
  rest_api_id   = var.rest_api_id
  resource_id   = each.value
  http_method   = "ANY"
  authorization = "CUSTOM"
  authorizer_id = var.authorizer_id
}

resource "aws_api_gateway_integration" "any" {
  for_each                = local.order_api_resources
  rest_api_id             = var.rest_api_id
  resource_id             = each.value
  http_method             = aws_api_gateway_method.any[each.key].http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.order_service.invoke_arn
}

# --- CORS: OPTIONS (MOCK, sin autorización) para el preflight del navegador ---
resource "aws_api_gateway_method" "options" {
  for_each      = local.order_api_resources
  rest_api_id   = var.rest_api_id
  resource_id   = each.value
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options" {
  for_each    = local.order_api_resources
  rest_api_id = var.rest_api_id
  resource_id = each.value
  http_method = aws_api_gateway_method.options[each.key].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options" {
  for_each    = local.order_api_resources
  rest_api_id = var.rest_api_id
  resource_id = each.value
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options" {
  for_each    = local.order_api_resources
  rest_api_id = var.rest_api_id
  resource_id = each.value
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = aws_api_gateway_method_response.options[each.key].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,PATCH,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.options]
}

resource "aws_lambda_permission" "apigw_order_service" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.order_service.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.rest_api_execution_arn}/*/*"
}

# --- Redespliegue del stage para activar las nuevas rutas ---
resource "aws_api_gateway_deployment" "orders" {
  rest_api_id = var.rest_api_id

  triggers = {
    redeploy = sha1(jsonencode([
      values(local.order_api_resources),
      [for m in aws_api_gateway_method.any : m.id],
      [for i in aws_api_gateway_integration.any : i.id],
      [for i in aws_api_gateway_integration.options : i.id],
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.any,
    aws_api_gateway_integration.options,
  ]
}
