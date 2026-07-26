# =============================================================================
# Catalog Service — Productos (M2) y Tiendas (M3)
# =============================================================================

locals {
  catalog_service_name = "${local.name_prefix}-catalog-service"
}

resource "null_resource" "stage_catalog_service" {
  triggers = {
    handler     = filemd5("${path.module}/../src/catalog_service/handler.py")
    permissions = filemd5("${path.module}/../src/catalog_service/permissions.py")
    repository  = filemd5("${path.module}/../src/catalog_service/repository.py")
    shared_err  = filemd5("${path.module}/../src/shared/errors.py")
    shared_resp = filemd5("${path.module}/../src/shared/response.py")
    script      = filemd5(local.stage_script)
  }

  provisioner "local-exec" {
    command = "python \"${local.stage_script}\" catalog_service"
  }
}

data "archive_file" "catalog_service" {
  type        = "zip"
  source_dir  = "${path.module}/.build/catalog_service"
  output_path = "${path.module}/.build/catalog_service.zip"
  depends_on  = [null_resource.stage_catalog_service]
}

resource "aws_iam_role" "catalog_service" {
  name               = "${local.catalog_service_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "catalog_service_basic" {
  role       = aws_iam_role.catalog_service.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "catalog_service" {
  statement {
    sid = "ProductsTable"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
    ]
    resources = [
      aws_dynamodb_table.products.arn,
      "${aws_dynamodb_table.products.arn}/index/*",
    ]
  }

  statement {
    sid = "StoresTable"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Scan",
    ]
    resources = [aws_dynamodb_table.stores.arn]
  }

  statement {
    sid       = "AuditWrite"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.audit_logs.arn]
  }
}

resource "aws_iam_role_policy" "catalog_service" {
  name   = "${local.catalog_service_name}-policy"
  role   = aws_iam_role.catalog_service.id
  policy = data.aws_iam_policy_document.catalog_service.json
}

resource "aws_cloudwatch_log_group" "catalog_service" {
  name              = "/aws/lambda/${local.catalog_service_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "catalog_service" {
  function_name    = local.catalog_service_name
  role             = aws_iam_role.catalog_service.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.catalog_service.output_path
  source_code_hash = data.archive_file.catalog_service.output_base64sha256
  timeout          = 15
  memory_size      = 256

  environment {
    variables = {
      STAGE            = var.stage_name
      PRODUCTS_TABLE   = aws_dynamodb_table.products.name
      STORES_TABLE     = aws_dynamodb_table.stores.name
      AUDIT_LOGS_TABLE = aws_dynamodb_table.audit_logs.name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.catalog_service,
    aws_iam_role_policy.catalog_service,
  ]
}

resource "aws_lambda_permission" "apigw_catalog_service" {
  statement_id  = "AllowAPIGatewayInvokeCatalog"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.catalog_service.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# --- Rutas /products y /stores (ANY + OPTIONS) ---
resource "aws_api_gateway_resource" "products" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "products"
}

resource "aws_api_gateway_resource" "products_proxy" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.products.id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_resource" "stores" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "stores"
}

resource "aws_api_gateway_resource" "stores_proxy" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.stores.id
  path_part   = "{proxy+}"
}

locals {
  catalog_api_resources = {
    products       = aws_api_gateway_resource.products.id
    products_proxy = aws_api_gateway_resource.products_proxy.id
    stores         = aws_api_gateway_resource.stores.id
    stores_proxy   = aws_api_gateway_resource.stores_proxy.id
  }
}

resource "aws_api_gateway_method" "catalog_any" {
  for_each      = local.catalog_api_resources
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = each.value
  http_method   = "ANY"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.jwt.id
}

resource "aws_api_gateway_integration" "catalog_any" {
  for_each                = local.catalog_api_resources
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = each.value
  http_method             = aws_api_gateway_method.catalog_any[each.key].http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.catalog_service.invoke_arn
}

resource "aws_api_gateway_method" "catalog_options" {
  for_each      = local.catalog_api_resources
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = each.value
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "catalog_options" {
  for_each    = local.catalog_api_resources
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = each.value
  http_method = aws_api_gateway_method.catalog_options[each.key].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "catalog_options" {
  for_each    = local.catalog_api_resources
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = each.value
  http_method = aws_api_gateway_method.catalog_options[each.key].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "catalog_options" {
  for_each    = local.catalog_api_resources
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = each.value
  http_method = aws_api_gateway_method.catalog_options[each.key].http_method
  status_code = aws_api_gateway_method_response.catalog_options[each.key].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,PATCH,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.catalog_options]
}
