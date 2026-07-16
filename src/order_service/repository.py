import json
import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key
from boto3.dynamodb.types import TypeSerializer

from shared.errors import ConflictError, NotFoundError

dynamodb = boto3.resource("dynamodb")
_client = dynamodb.meta.client
_events = boto3.client("events")
_serializer = TypeSerializer()

CARTS_TABLE = os.environ["CARTS_TABLE"]
ORDERS_TABLE = os.environ["ORDERS_TABLE"]
PRODUCTS_TABLE = os.environ["PRODUCTS_TABLE"]
AUDIT_LOGS_TABLE = os.environ["AUDIT_LOGS_TABLE"]
EVENT_BUS_NAME = os.environ.get("EVENT_BUS_NAME", "default")

carts_table = dynamodb.Table(CARTS_TABLE)
orders_table = dynamodb.Table(ORDERS_TABLE)
products_table = dynamodb.Table(PRODUCTS_TABLE)
audit_table = dynamodb.Table(AUDIT_LOGS_TABLE)

# Estados de pedido (PDF Módulo 5)
STATUS_PENDING = "PENDIENTE"
STATUS_CONFIRMED = "CONFIRMADO"
STATUS_PREPARING = "EN_PREPARACION"
STATUS_SHIPPED = "ENVIADO"
STATUS_DELIVERED = "ENTREGADO"
STATUS_CANCELLED = "CANCELADO"

FINAL_STATUSES = {STATUS_DELIVERED, STATUS_CANCELLED}

# Transiciones de estado permitidas
STATUS_TRANSITIONS = {
    STATUS_PENDING: {STATUS_CONFIRMED, STATUS_CANCELLED},
    STATUS_CONFIRMED: {STATUS_PREPARING, STATUS_CANCELLED},
    STATUS_PREPARING: {STATUS_SHIPPED, STATUS_CANCELLED},
    STATUS_SHIPPED: {STATUS_DELIVERED},
    STATUS_DELIVERED: set(),
    STATUS_CANCELLED: set(),
}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _to_decimal(value):
    return Decimal(str(value))


def _floats(item):
    """Convierte Decimals a float para serializar la respuesta JSON."""
    if isinstance(item, list):
        return [_floats(i) for i in item]
    if isinstance(item, dict):
        return {k: _floats(v) for k, v in item.items()}
    if isinstance(item, Decimal):
        return int(item) if item % 1 == 0 else float(item)
    return item


def _serialize(item: dict) -> dict:
    return {k: _serializer.serialize(v) for k, v in item.items()}


# ---------------------------------------------------------------------------
# Auditoría (PDF sección 7)
# ---------------------------------------------------------------------------
def write_audit(user_id, action, resource_id, result, details=None):
    # DynamoDB (resource) no acepta float: convertimos floats -> Decimal
    safe_details = json.loads(json.dumps(details or {}, default=str), parse_float=Decimal)
    audit_table.put_item(
        Item={
            "auditId": str(uuid.uuid4()),
            "createdAt": _now(),
            "userId": user_id,
            "action": action,
            "resourceType": "ORDER",
            "resourceId": resource_id,
            "result": result,
            "details": safe_details,
        }
    )


# ---------------------------------------------------------------------------
# EventBridge (PDF sección 6 - arquitectura basada en eventos)
# ---------------------------------------------------------------------------
def publish_order_created(order: dict) -> None:
    _events.put_events(
        Entries=[
            {
                "Source": "cloudshop.orders",
                "DetailType": "OrderCreated",
                "Detail": json.dumps(_floats(order), default=str),
                "EventBusName": EVENT_BUS_NAME,
            }
        ]
    )


# ---------------------------------------------------------------------------
# Productos (solo lectura desde este servicio)
# ---------------------------------------------------------------------------
def get_product(product_id: str) -> dict | None:
    resp = products_table.get_item(Key={"productId": product_id})
    return resp.get("Item")


# ---------------------------------------------------------------------------
# Módulo 4 - Carrito de compras
# ---------------------------------------------------------------------------
def get_cart(user_id: str) -> dict:
    resp = carts_table.get_item(Key={"userId": user_id})
    cart = resp.get("Item") or {"userId": user_id, "items": [], "updatedAt": None}
    cart.setdefault("items", [])
    return _floats(cart)


def _save_cart(user_id: str, items: list[dict]) -> dict:
    now = _now()
    carts_table.put_item(Item={"userId": user_id, "items": items, "updatedAt": now})
    return _floats({"userId": user_id, "items": items, "updatedAt": now})


def add_cart_item(user_id: str, product_id: str, quantity: int) -> dict:
    product = get_product(product_id)
    if not product:
        raise NotFoundError("Producto no encontrado")
    if product.get("status") == "INACTIVE":
        raise ConflictError("El producto no está disponible")

    available = int(product.get("stock", 0))
    resp = carts_table.get_item(Key={"userId": user_id})
    items = (resp.get("Item") or {}).get("items", [])

    # Si el producto ya está en el carrito, se acumula la cantidad
    found = False
    for it in items:
        if it["productId"] == product_id:
            it["quantity"] = int(it["quantity"]) + int(quantity)
            found = True
            break
    if not found:
        items.append(
            {
                "productId": product_id,
                "code": product.get("code"),
                "name": product.get("name"),
                "price": _to_decimal(product.get("price", 0)),
                "quantity": int(quantity),
            }
        )

    # Validación de stock disponible sobre la cantidad total solicitada
    total_qty = next(int(i["quantity"]) for i in items if i["productId"] == product_id)
    if total_qty > available:
        raise ConflictError(f"Stock insuficiente (disponible: {available})")

    return _save_cart(user_id, items)


def set_cart_item_qty(user_id: str, product_id: str, quantity: int) -> dict:
    resp = carts_table.get_item(Key={"userId": user_id})
    items = (resp.get("Item") or {}).get("items", [])
    if not any(i["productId"] == product_id for i in items):
        raise NotFoundError("El producto no está en el carrito")

    if quantity <= 0:
        # cantidad 0 => se elimina el ítem
        items = [i for i in items if i["productId"] != product_id]
        return _save_cart(user_id, items)

    product = get_product(product_id)
    available = int(product.get("stock", 0)) if product else 0
    if quantity > available:
        raise ConflictError(f"Stock insuficiente (disponible: {available})")

    for it in items:
        if it["productId"] == product_id:
            it["quantity"] = int(quantity)
    return _save_cart(user_id, items)


def remove_cart_item(user_id: str, product_id: str) -> dict:
    resp = carts_table.get_item(Key={"userId": user_id})
    items = (resp.get("Item") or {}).get("items", [])
    new_items = [i for i in items if i["productId"] != product_id]
    if len(new_items) == len(items):
        raise NotFoundError("El producto no está en el carrito")
    return _save_cart(user_id, new_items)


def clear_cart(user_id: str) -> dict:
    return _save_cart(user_id, [])


# ---------------------------------------------------------------------------
# Módulo 5 - Pedidos
# ---------------------------------------------------------------------------
def create_order_from_cart(user_id: str, customer_email: str | None) -> dict:
    """
    Caso de prueba 2: crea el pedido y descuenta inventario de forma ATÓMICA
    (TransactWriteItems). Si algún producto no tiene stock suficiente, la
    transacción completa se revierte y no se crea el pedido.
    """
    cart = get_cart(user_id)
    items = cart.get("items", [])
    if not items:
        raise ConflictError("El carrito está vacío")

    now = _now()
    order_id = str(uuid.uuid4())

    order_items = []
    total = Decimal("0")
    for it in items:
        qty = int(it["quantity"])
        price = _to_decimal(it["price"])
        subtotal = price * qty
        total += subtotal
        order_items.append(
            {
                "productId": it["productId"],
                "code": it.get("code"),
                "name": it.get("name"),
                "price": price,
                "quantity": qty,
                "subtotal": subtotal,
            }
        )

    order_item = {
        "orderId": order_id,
        "userId": user_id,
        "customerEmail": customer_email or "",
        "items": order_items,
        "total": total,
        "status": STATUS_PENDING,
        "statusHistory": [{"status": STATUS_PENDING, "at": now}],
        "createdAt": now,
        "updatedAt": now,
    }

    # Transacción: 1 Put del pedido + 1 Update de stock por producto.
    transact_items = [
        {
            "Put": {
                "TableName": ORDERS_TABLE,
                "Item": _serialize(order_item),
                "ConditionExpression": "attribute_not_exists(orderId)",
            }
        }
    ]
    for it in order_items:
        transact_items.append(
            {
                "Update": {
                    "TableName": PRODUCTS_TABLE,
                    "Key": {"productId": {"S": it["productId"]}},
                    "UpdateExpression": "SET stock = stock - :qty, updatedAt = :now",
                    "ConditionExpression": "attribute_exists(productId) AND #st = :active AND stock >= :qty",
                    "ExpressionAttributeNames": {"#st": "status"},
                    "ExpressionAttributeValues": {
                        ":qty": {"N": str(it["quantity"])},
                        ":now": {"S": now},
                        ":active": {"S": "ACTIVE"},
                    },
                }
            }
        )

    try:
        _client.transact_write_items(TransactItems=transact_items)
    except _client.exceptions.TransactionCanceledException as exc:
        # Stock insuficiente o producto inexistente/inactivo
        raise ConflictError(
            "No se pudo crear el pedido: stock insuficiente o producto no disponible"
        ) from exc

    # Carrito consumido -> se vacía
    clear_cart(user_id)
    return _floats(order_item)


def get_order(order_id: str) -> dict | None:
    resp = orders_table.get_item(Key={"orderId": order_id})
    return _floats(resp.get("Item")) if resp.get("Item") else None


def list_orders(status: str | None = None, limit: int = 100) -> list[dict]:
    if status:
        resp = orders_table.query(
            IndexName="status-index",
            KeyConditionExpression=Key("status").eq(status),
            Limit=limit,
        )
    else:
        resp = orders_table.scan(Limit=limit)
    return [_floats(i) for i in resp.get("Items", [])]


def list_orders_by_user(user_id: str, limit: int = 100) -> list[dict]:
    resp = orders_table.query(
        IndexName="userId-index",
        KeyConditionExpression=Key("userId").eq(user_id),
        Limit=limit,
    )
    return [_floats(i) for i in resp.get("Items", [])]


def update_order_status(order_id: str, new_status: str) -> dict:
    order = get_order(order_id)
    if not order:
        raise NotFoundError("Pedido no encontrado")

    current = order["status"]
    if new_status not in STATUS_TRANSITIONS:
        raise ConflictError(f"Estado inválido: {new_status}")
    if new_status not in STATUS_TRANSITIONS.get(current, set()):
        raise ConflictError(f"Transición no permitida: {current} -> {new_status}")

    if new_status == STATUS_CANCELLED:
        return cancel_order(order_id)

    now = _now()
    history = order.get("statusHistory", [])
    history.append({"status": new_status, "at": now})
    resp = orders_table.update_item(
        Key={"orderId": order_id},
        UpdateExpression="SET #st = :s, updatedAt = :now, statusHistory = :h",
        ExpressionAttributeNames={"#st": "status"},
        ExpressionAttributeValues={":s": new_status, ":now": now, ":h": history},
        ConditionExpression="attribute_exists(orderId)",
        ReturnValues="ALL_NEW",
    )
    return _floats(resp.get("Attributes"))


def cancel_order(order_id: str) -> dict:
    """Cancela el pedido y DEVUELVE el inventario de forma atómica."""
    order = get_order(order_id)
    if not order:
        raise NotFoundError("Pedido no encontrado")
    if order["status"] in FINAL_STATUSES:
        raise ConflictError(f"El pedido ya está en estado final: {order['status']}")

    now = _now()
    history = order.get("statusHistory", [])
    history.append({"status": STATUS_CANCELLED, "at": now})

    transact_items = [
        {
            "Update": {
                "TableName": ORDERS_TABLE,
                "Key": {"orderId": {"S": order_id}},
                "UpdateExpression": "SET #st = :s, updatedAt = :now, statusHistory = :h",
                "ConditionExpression": "attribute_exists(orderId) AND #st <> :cancelled",
                "ExpressionAttributeNames": {"#st": "status"},
                "ExpressionAttributeValues": {
                    ":s": {"S": STATUS_CANCELLED},
                    ":now": {"S": now},
                    ":h": _serializer.serialize(history),
                    ":cancelled": {"S": STATUS_CANCELLED},
                },
            }
        }
    ]
    for it in order.get("items", []):
        transact_items.append(
            {
                "Update": {
                    "TableName": PRODUCTS_TABLE,
                    "Key": {"productId": {"S": it["productId"]}},
                    "UpdateExpression": "SET stock = stock + :qty, updatedAt = :now",
                    "ConditionExpression": "attribute_exists(productId)",
                    "ExpressionAttributeValues": {
                        ":qty": {"N": str(int(it["quantity"]))},
                        ":now": {"S": now},
                    },
                }
            }
        )

    _client.transact_write_items(TransactItems=transact_items)
    order["status"] = STATUS_CANCELLED
    order["statusHistory"] = history
    order["updatedAt"] = now
    return _floats(order)
