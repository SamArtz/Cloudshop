"""
Notificaciones (PDF sección 6 - Arquitectura basada en eventos).

Se dispara por EventBridge cuando se crea un pedido (DetailType=OrderCreated):
  1. Envía un correo de confirmación vía Amazon SES.
  2. Registra una entrada de auditoría del envío.

El descuento de inventario se realiza de forma transaccional en el Order
Service al crear el pedido, por lo que aquí solo se notifica y audita.
"""
import os
import uuid
from datetime import datetime, timezone

import boto3

ses = boto3.client("ses")
dynamodb = boto3.resource("dynamodb")
audit_table = dynamodb.Table(os.environ["AUDIT_LOGS_TABLE"])

SENDER = os.environ["SES_SENDER"]
# Correo de respaldo (sandbox SES): si el cliente no tiene correo verificado
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


def _build_email(order: dict) -> tuple[str, str]:
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


def handler(event, context):
    # Evento de EventBridge: el pedido viene en event["detail"]
    order = event.get("detail") or {}
    order_id = order.get("orderId", "unknown")
    recipient = order.get("customerEmail") or FALLBACK_RECIPIENT

    subject, body = _build_email(order)

    try:
        ses.send_email(
            Source=SENDER,
            Destination={"ToAddresses": [recipient]},
            Message={
                "Subject": {"Data": subject},
                "Body": {"Text": {"Data": body}},
            },
        )
        _write_audit(order.get("userId", "system"), "ORDER_EMAIL_SENT", order_id,
                     "SUCCESS", {"recipient": recipient})
        print(f"Correo enviado para pedido {order_id} -> {recipient}")
    except Exception as e:  # noqa: BLE001
        print(f"Error enviando correo del pedido {order_id}: {e}")
        _write_audit(order.get("userId", "system"), "ORDER_EMAIL_SENT", order_id,
                     "FAILED", {"recipient": recipient, "error": str(e)})
        raise

    return {"ok": True, "orderId": order_id}
