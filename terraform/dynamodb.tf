# =============================================================================
# DynamoDB — Datos + Auditoría (PDF secciones 3, 7 y 9)
# =============================================================================

# --- Users (Módulo 1) ---
resource "aws_dynamodb_table" "users" {
  name         = "${local.name_prefix}-users"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }
  attribute {
    name = "email"
    type = "S"
  }

  global_secondary_index {
    name            = "email-index"
    hash_key        = "email"
    projection_type = "ALL"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-users" })
}

# --- AuditLogs (PDF sección 7 — Auditoría) ---
# Toda acción relevante: CREATE_USER, DELETE_PRODUCT, CREATE_ORDER, CANCEL_ORDER, etc.
resource "aws_dynamodb_table" "audit_logs" {
  name         = "${local.name_prefix}-audit-logs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "auditId"
  range_key    = "createdAt"

  attribute {
    name = "auditId"
    type = "S"
  }
  attribute {
    name = "createdAt"
    type = "S"
  }
  attribute {
    name = "userId"
    type = "S"
  }
  attribute {
    name = "action"
    type = "S"
  }

  # Consultar auditoría por usuario
  global_secondary_index {
    name            = "userId-createdAt-index"
    hash_key        = "userId"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  # Consultar auditoría por tipo de acción (ELIMINAR_PRODUCTO, CREATE_ORDER…)
  global_secondary_index {
    name            = "action-createdAt-index"
    hash_key        = "action"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-audit-logs" })
}

# --- Products (Módulo 2) ---
resource "aws_dynamodb_table" "products" {
  name         = "${local.name_prefix}-products"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "productId"

  attribute {
    name = "productId"
    type = "S"
  }
  attribute {
    name = "storeId"
    type = "S"
  }

  global_secondary_index {
    name            = "storeId-index"
    hash_key        = "storeId"
    projection_type = "ALL"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-products" })
}

# --- Stores (Módulo 3) ---
resource "aws_dynamodb_table" "stores" {
  name         = "${local.name_prefix}-stores"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "storeId"

  attribute {
    name = "storeId"
    type = "S"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-stores" })
}

# --- Carts (Módulo 4) ---
resource "aws_dynamodb_table" "carts" {
  name         = "${local.name_prefix}-carts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-carts" })
}

# --- Orders (Módulo 5) ---
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

  global_secondary_index {
    name            = "userId-index"
    hash_key        = "userId"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "status-index"
    hash_key        = "status"
    projection_type = "ALL"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-orders" })
}
