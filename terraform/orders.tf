# =============================================================================
# Order Service + Notifications — Carrito (M4), Pedidos (M5), SES vía EventBridge
# =============================================================================

locals {
  order_service_name = "${local.name_prefix}-order-service"
  notifications_name = "${local.name_prefix}-notifications"
}

# --- Empaquetado ---
resource "null_resource" "stage_order_service" {
  triggers = {
    handler     = filemd5("${path.module}/../src/order_service/handler.py")
    repository  = filemd5("${path.module}/../src/order_service/repository.py")
    permissions = filemd5("${path.module}/../src/order_service/permissions.py")
    shared_err  = filemd5("${path.module}/../src/shared/errors.py")
    shared_resp = filemd5("${path.module}/../src/shared/response.py")
    script      = filemd5(local.stage_script)
  }

  provisioner "local-exec" {
    working_dir = local.stage_working_dir
    command     = "python scripts/stage_lambda.py order_service"
  }
}

resource "null_resource" "stage_notifications" {
  triggers = {
    handler = filemd5("${path.module}/../src/notifications/handler.py")
    script  = filemd5(local.stage_script)
  }

  provisioner "local-exec" {
    working_dir = local.stage_working_dir
    command     = "python scripts/stage_lambda.py notifications"
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
  source_dir  = "${path.module}/.build/notifications"
  output_path = "${path.module}/.build/notifications.zip"
  depends_on  = [null_resource.stage_notifications]
}

# --- IAM Order Service ---
resource "aws_iam_role" "order_service" {
  name               = "${local.order_service_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "order_service_basic" {
  role       = aws_iam_role.order_service.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "order_service" {
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

  statement {
    sid       = "ProductsStock"
    actions   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.products.arn]
  }

  statement {
    sid       = "AuditWrite"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.audit_logs.arn]
  }

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

# --- IAM Notifications ---
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
    resources = [aws_dynamodb_table.audit_logs.arn]
  }
}

resource "aws_iam_role_policy" "notifications" {
  name   = "${local.notifications_name}-policy"
  role   = aws_iam_role.notifications.id
  policy = data.aws_iam_policy_document.notifications.json
}

# --- Lambdas ---
resource "aws_cloudwatch_log_group" "order_service" {
  name              = "/aws/lambda/${local.order_service_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "notifications" {
  name              = "/aws/lambda/${local.notifications_name}"
  retention_in_days = var.log_retention_days
}

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
      PRODUCTS_TABLE   = aws_dynamodb_table.products.name
      AUDIT_LOGS_TABLE = aws_dynamodb_table.audit_logs.name
      EVENT_BUS_NAME   = aws_cloudwatch_event_bus.cloudshop.name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.order_service,
    aws_iam_role_policy.order_service,
  ]
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
      AUDIT_LOGS_TABLE       = aws_dynamodb_table.audit_logs.name
      SES_SENDER             = var.ses_sender_email
      SES_FALLBACK_RECIPIENT = var.ses_sender_email
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.notifications,
    aws_iam_role_policy.notifications,
  ]
}

resource "aws_lambda_permission" "apigw_order_service" {
  statement_id  = "AllowAPIGatewayInvokeOrders"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.order_service.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# --- API: /cart y /orders ---
resource "aws_api_gateway_resource" "cart" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "cart"
}

resource "aws_api_gateway_resource" "cart_proxy" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.cart.id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "orders"
}

resource "aws_api_gateway_resource" "orders_proxy" {
  rest_api_id = aws_api_gateway_rest_api.main.id
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

resource "aws_api_gateway_method" "orders_any" {
  for_each      = local.order_api_resources
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = each.value
  http_method   = "ANY"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.jwt.id
}

resource "aws_api_gateway_integration" "orders_any" {
  for_each                = local.order_api_resources
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = each.value
  http_method             = aws_api_gateway_method.orders_any[each.key].http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.order_service.invoke_arn
}

resource "aws_api_gateway_method" "orders_options" {
  for_each      = local.order_api_resources
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = each.value
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "orders_options" {
  for_each    = local.order_api_resources
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = each.value
  http_method = aws_api_gateway_method.orders_options[each.key].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "orders_options" {
  for_each    = local.order_api_resources
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = each.value
  http_method = aws_api_gateway_method.orders_options[each.key].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "orders_options" {
  for_each    = local.order_api_resources
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = each.value
  http_method = aws_api_gateway_method.orders_options[each.key].http_method
  status_code = aws_api_gateway_method_response.orders_options[each.key].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,PATCH,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.orders_options]
}
