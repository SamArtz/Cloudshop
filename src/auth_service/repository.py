import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource("dynamodb")
users_table = dynamodb.Table(os.environ["USERS_TABLE"])
audit_table = dynamodb.Table(os.environ["AUDIT_LOGS_TABLE"])


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def get_user_by_id(user_id: str) -> dict | None:
    resp = users_table.get_item(Key={"userId": user_id})
    return resp.get("Item")


def get_user_by_email(email: str) -> dict | None:
    resp = users_table.query(
        IndexName="email-index",
        KeyConditionExpression=Key("email").eq(email.lower()),
        Limit=1,
    )
    items = resp.get("Items", [])
    return items[0] if items else None


def create_user(email: str, password_hash: str, full_name: str, role: str) -> dict:
    now = _now()
    item = {
        "userId": str(uuid.uuid4()),
        "email": email.lower(),
        "passwordHash": password_hash,
        "fullName": full_name,
        "role": role,
        "status": "ACTIVE",
        "createdAt": now,
        "updatedAt": now,
    }
    users_table.put_item(
        Item=item,
        ConditionExpression="attribute_not_exists(userId)",
    )
    return item


def update_user(user_id: str, updates: dict) -> dict | None:
    if not updates:
        return get_user_by_id(user_id)

    expr_names = {}
    expr_values = {":updatedAt": _now()}
    set_parts = ["#updatedAt = :updatedAt"]

    allowed = {"fullName", "role", "status"}
    for key, value in updates.items():
        if key not in allowed or value is None:
            continue
        expr_names[f"#{key}"] = key
        expr_values[f":{key}"] = value
        set_parts.append(f"#{key} = :{key}")

    expr_names["#updatedAt"] = "updatedAt"

    resp = users_table.update_item(
        Key={"userId": user_id},
        UpdateExpression="SET " + ", ".join(set_parts),
        ExpressionAttributeNames=expr_names,
        ExpressionAttributeValues=expr_values,
        ConditionExpression="attribute_exists(userId)",
        ReturnValues="ALL_NEW",
    )
    return resp.get("Attributes")


def list_users(limit: int = 50) -> list[dict]:
    resp = users_table.scan(Limit=limit)
    return resp.get("Items", [])


def write_audit(user_id: str, action: str, resource_id: str, result: str, details: dict | None = None) -> None:
    item = {
        "auditId": str(uuid.uuid4()),
        "createdAt": _now(),
        "userId": user_id,
        "action": action,
        "resourceType": "USER",
        "resourceId": resource_id,
        "result": result,
        "details": details or {},
    }
    audit_table.put_item(Item=item)


def public_user(user: dict) -> dict:
    """Quita passwordHash de la respuesta."""
    return {
        "userId": user.get("userId"),
        "email": user.get("email"),
        "fullName": user.get("fullName"),
        "role": user.get("role"),
        "status": user.get("status"),
        "createdAt": user.get("createdAt"),
        "updatedAt": user.get("updatedAt"),
        "lastLoginAt": user.get("lastLoginAt"),
    }