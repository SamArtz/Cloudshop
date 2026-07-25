"""
Notificaciones (PDF sección 6 - Arquitectura basada en eventos).

Se dispara por EventBridge cuando:
  - DetailType=OrderCreated   → correo de confirmación
  - DetailType=OrderCancelled → correo de cancelación

Además registra una entrada de auditoría del envío en DynamoDB AuditLogs.
"""
import os
import uuid
from datetime import datetime, timezone

import boto3

ses = boto3.client("ses")
dynamodb = boto3.resource("dynamodb")
audit_table = dynamodb.Table(os.environ["AUDIT_LOGS_TABLE"])

SENDER = os.environ["SES_SENDER"]
FALLBACK_RECIPIENT = os.environ.get("SES_FALLBACK_RECIPIENT", SENDER)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _write_audit(user_id, action, resource_id, result, details=None):
    audit_table.put_item(
        Item={
            "auditId": str(uuid.uuid4()),
            "createdAt": _now(),
            "userId": user_id,
            "action": action,
            "resourceType": "NOTIFICATION",
            "resourceId": resource_id,
            "result": result,
            "details": details or {},
        }
    )


def _build_created_email(order: dict) -> tuple[str, str]:
    lines = [
        f"Hola, tu pedido {order.get('orderId')} fue creado con éxito.",
        "",
        "Detalle:",
    ]
    for it in order.get("items", []):
        lines.append(
            f"  - {it.get('name')} x{it.get('quantity')} = {it.get('subtotal')}"
        )
    lines += [
        "",
        f"Total: {order.get('total')}",
        f"Estado: {order.get('status')}",
        "",
        "Gracias por comprar en CloudShop.",
    ]
    subject = f"CloudShop - Pedido {order.get('orderId')} confirmado"
    return subject, "\n".join(lines)


def _build_cancelled_email(order: dict) -> tuple[str, str]:
    subject = f"CloudShop - Pedido {order.get('orderId')} cancelado"
    body = (
        f"Hola, tu pedido {order.get('orderId')} fue cancelado.\n\n"
        f"Total original: {order.get('total')}\n"
        f"Estado: {order.get('status')}\n\n"
        "Si no solicitaste esta cancelación, contacta a soporte.\n"
    )
    return subject, body


def handler(event, context):
    detail_type = event.get("detail-type") or event.get("detailType") or "OrderCreated"
    order = event.get("detail") or {}
    order_id = order.get("orderId", "unknown")
    recipient = order.get("customerEmail") or FALLBACK_RECIPIENT

    if detail_type == "OrderCancelled":
        subject, body = _build_cancelled_email(order)
        audit_action = "ORDER_CANCEL_EMAIL_SENT"
    else:
        subject, body = _build_created_email(order)
        audit_action = "ORDER_EMAIL_SENT"

    try:
        ses.send_email(
            Source=SENDER,
            Destination={"ToAddresses": [recipient]},
            Message={
                "Subject": {"Data": subject},
                "Body": {"Text": {"Data": body}},
            },
        )
        _write_audit(
            order.get("userId", "system"),
            audit_action,
            order_id,
            "SUCCESS",
            {"recipient": recipient, "detailType": detail_type},
        )
        print(f"Correo enviado ({detail_type}) pedido {order_id} -> {recipient}")
    except Exception as e:  # noqa: BLE001
        print(f"Error enviando correo del pedido {order_id}: {e}")
        _write_audit(
            order.get("userId", "system"),
            audit_action,
            order_id,
            "FAILED",
            {"recipient": recipient, "error": str(e), "detailType": detail_type},
        )
        raise

    return {"ok": True, "orderId": order_id, "detailType": detail_type}
