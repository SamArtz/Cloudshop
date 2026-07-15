import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key


dynamodb = boto3.resource("dynamodb")
products_table = dynamodb.Table(os.environ["PRODUCTS_TABLE"])
stores_table = dynamodb.Table(os.environ["STORES_TABLE"])
audit_table = dynamodb.Table(os.environ["AUDIT_LOGS_TABLE"])


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _to_decimal(value):
    if value is None:
        return None
    return Decimal(str(value))


def _product_item(item: dict | None) -> dict | None:
    if not item:
        return None
    item = dict(item)
    if "price" in item and not isinstance(item["price"], float):
        item["price"] = float(item["price"])
    return item


def write_audit(user_id: str, action: str, resource_type: str, resource_id: str, result: str, details: dict | None = None) -> None:
    item = {
        "auditId": str(uuid.uuid4()),
        "createdAt": _now(),
        "userId": user_id,
        "action": action,
        "resourceType": resource_type,
        "resourceId": resource_id,
        "result": result,
        "details": details or {},
    }
    audit_table.put_item(Item=item)


def create_store(name: str, owner_id: str, description: str | None = None) -> dict:
    now = _now()
    item = {
        "storeId": str(uuid.uuid4()),
        "name": name,
        "description": description or "",
        "ownerId": owner_id,
        "status": "ACTIVE",
        "createdAt": now,
        "updatedAt": now,
    }
    stores_table.put_item(Item=item)
    return item


def get_store_by_id(store_id: str) -> dict | None:
    resp = stores_table.get_item(Key={"storeId": store_id})
    return resp.get("Item")


def list_stores(limit: int = 50) -> list[dict]:
    resp = stores_table.scan(Limit=limit)
    return resp.get("Items", [])


def update_store(store_id: str, updates: dict) -> dict | None:
    if not updates:
        return get_store_by_id(store_id)

    expr_names = {"#updatedAt": "updatedAt"}
    expr_values = {":updatedAt": _now()}
    set_parts = ["#updatedAt = :updatedAt"]

    allowed = {"name", "description", "ownerId", "status"}
    for key, value in updates.items():
        if key not in allowed or value is None:
            continue
        expr_names[f"#{key}"] = key
        expr_values[f":{key}"] = value
        set_parts.append(f"#{key} = :{key}")

    resp = stores_table.update_item(
        Key={"storeId": store_id},
        UpdateExpression="SET " + ", ".join(set_parts),
        ExpressionAttributeNames=expr_names,
        ExpressionAttributeValues=expr_values,
        ConditionExpression="attribute_exists(storeId)",
        ReturnValues="ALL_NEW",
    )
    return resp.get("Attributes")


def deactivate_store(store_id: str) -> dict | None:
    return update_store(store_id, {"status": "INACTIVE"})


def create_product(code: str, name: str, description: str, category: str, price: float, stock: int, store_id: str) -> dict:
    now = _now()
    item = {
        "productId": str(uuid.uuid4()),
        "code": code,
        "name": name,
        "description": description,
        "category": category,
        "price": _to_decimal(price),
        "stock": int(stock),
        "storeId": store_id,
        "status": "ACTIVE",
        "createdAt": now,
        "updatedAt": now,
    }
    products_table.put_item(Item=item)
    return item


def get_product_by_id(product_id: str) -> dict | None:
    resp = products_table.get_item(Key={"productId": product_id})
    return _product_item(resp.get("Item"))


def list_products(limit: int = 50) -> list[dict]:
    resp = products_table.scan(Limit=limit)
    items = resp.get("Items", [])
    return [_product_item(item) for item in items]


def list_products_by_store(store_id: str, limit: int = 50) -> list[dict]:
    resp = products_table.query(
        IndexName="storeId-index",
        KeyConditionExpression=Key("storeId").eq(store_id),
        Limit=limit,
    )
    return [_product_item(item) for item in resp.get("Items", [])]


def update_product(product_id: str, updates: dict) -> dict | None:
    if not updates:
        return get_product_by_id(product_id)

    expr_names = {"#updatedAt": "updatedAt"}
    expr_values = {":updatedAt": _now()}
    set_parts = ["#updatedAt = :updatedAt"]

    allowed = {"code", "name", "description", "category", "price", "stock", "storeId", "status"}
    for key, value in updates.items():
        if key not in allowed or value is None:
            continue
        expr_names[f"#{key}"] = key
        if key in {"price"}:
            expr_values[f":{key}"] = _to_decimal(value)
        elif key in {"stock"}:
            expr_values[f":{key}"] = int(value)
        else:
            expr_values[f":{key}"] = value
        set_parts.append(f"#{key} = :{key}")

    resp = products_table.update_item(
        Key={"productId": product_id},
        UpdateExpression="SET " + ", ".join(set_parts),
        ExpressionAttributeNames=expr_names,
        ExpressionAttributeValues=expr_values,
        ConditionExpression="attribute_exists(productId)",
        ReturnValues="ALL_NEW",
    )
    return _product_item(resp.get("Attributes"))


def delete_product(product_id: str) -> dict | None:
    resp = products_table.delete_item(
        Key={"productId": product_id},
        ReturnValues="ALL_OLD",
    )
    return resp.get("Attributes")
