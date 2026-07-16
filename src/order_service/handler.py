import base64
import json
import os
import sys
from pathlib import Path

from shared.errors import AppError, UnauthorizedError, ForbiddenError, NotFoundError
from shared.response import success, error

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from permissions import require_permission, can_read_order
import repository as repo


def _body(event) -> dict:
    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    if isinstance(raw, dict):
        return raw
    return json.loads(raw) if raw else {}


def _auth_context(event) -> dict:
    ctx = (event.get("requestContext") or {}).get("authorizer") or {}
    if "lambda" in ctx and isinstance(ctx["lambda"], dict):
        ctx = ctx["lambda"]
    return {
        "userId": ctx.get("userId") or ctx.get("principalId"),
        "role": ctx.get("role"),
        "email": ctx.get("email"),
    }


def _route(event) -> tuple[str, str]:
    method = (
        event.get("httpMethod")
        or event.get("requestContext", {}).get("http", {}).get("method")
        or ""
    ).upper()
    path = event.get("path") or event.get("rawPath") or ""
    stage = f"/{os.environ.get('STAGE', 'dev')}"
    if path.startswith(stage):
        path = path[len(stage):] or "/"
    return method, path


def handler(event, context):
    try:
        method, path = _route(event)

        if method == "OPTIONS":
            return success({"ok": True})

        auth = _auth_context(event)
        if not auth.get("userId") or not auth.get("role"):
            raise UnauthorizedError("Token inválido o ausente")

        parts = [p for p in path.split("/") if p]

        # -------- Módulo 4: Carrito --------
        if parts[:1] == ["cart"]:
            return _route_cart(method, parts, event, auth)

        # -------- Módulo 5: Pedidos --------
        if parts[:1] == ["orders"]:
            return _route_orders(method, parts, event, auth)

        return error("Ruta no encontrada", 404)

    except AppError as e:
        return error(e.message, e.status_code)
    except json.JSONDecodeError:
        return error("JSON inválido", 400)
    except Exception as e:  # noqa: BLE001
        print(f"Unhandled error: {e}")
        return error("Error interno", 500)


# ---------------------------------------------------------------------------
# Módulo 4 - Carrito de compras
# ---------------------------------------------------------------------------
def _route_cart(method, parts, event, auth):
    require_permission(auth["role"], "cart:manage")
    user_id = auth["userId"]

    # GET /cart
    if method == "GET" and parts == ["cart"]:
        return success({"cart": repo.get_cart(user_id)})

    # DELETE /cart -> vaciar carrito
    if method == "DELETE" and parts == ["cart"]:
        return success({"cart": repo.clear_cart(user_id)})

    # POST /cart/items -> agregar producto
    if method == "POST" and parts == ["cart", "items"]:
        data = _body(event)
        product_id = data.get("productId")
        quantity = int(data.get("quantity", 1))
        if not product_id or quantity <= 0:
            return error("productId y quantity (>0) son obligatorios", 400)
        return success({"cart": repo.add_cart_item(user_id, product_id, quantity)}, 201)

    # PUT /cart/items/{productId} -> modificar cantidad
    if method == "PUT" and len(parts) == 3 and parts[:2] == ["cart", "items"]:
        product_id = parts[2]
        data = _body(event)
        quantity = int(data.get("quantity", 0))
        return success({"cart": repo.set_cart_item_qty(user_id, product_id, quantity)})

    # DELETE /cart/items/{productId} -> eliminar producto
    if method == "DELETE" and len(parts) == 3 and parts[:2] == ["cart", "items"]:
        product_id = parts[2]
        return success({"cart": repo.remove_cart_item(user_id, product_id)})

    return error("Ruta de carrito no encontrada", 404)


# ---------------------------------------------------------------------------
# Módulo 5 - Pedidos
# ---------------------------------------------------------------------------
def _route_orders(method, parts, event, auth):
    # POST /orders -> crear pedido (Caso de prueba 2)
    if method == "POST" and parts == ["orders"]:
        return _create_order(auth)

    # GET /orders -> listar (propios para CLIENT; todos para OPERATOR/ADMIN)
    if method == "GET" and parts == ["orders"]:
        return _list_orders(event, auth)

    # GET /orders/{orderId} -> consultar pedido
    if method == "GET" and len(parts) == 2:
        return _get_order(auth, parts[1])

    # PATCH /orders/{orderId}/status -> actualizar estado
    if method == "PATCH" and len(parts) == 3 and parts[2] == "status":
        return _update_status(event, auth, parts[1])

    # PATCH /orders/{orderId}/cancel -> cancelar pedido
    if method == "PATCH" and len(parts) == 3 and parts[2] == "cancel":
        return _cancel_order(auth, parts[1])

    return error("Ruta de pedidos no encontrada", 404)


def _create_order(auth):
    require_permission(auth["role"], "orders:create")
    order = repo.create_order_from_cart(auth["userId"], auth.get("email"))
    # Evento -> EventBridge (dispara notificaciones/SES y auditoría por evento)
    repo.publish_order_created(order)
    # Auditoría directa (PDF sección 7)
    repo.write_audit(auth["userId"], "CREATE_ORDER", order["orderId"], "SUCCESS",
                     {"total": order["total"], "items": len(order["items"])})
    return success({"order": order}, 201)


def _list_orders(event, auth):
    params = event.get("queryStringParameters") or {}
    status = params.get("status")

    role = auth["role"]
    if role == "CLIENT":
        require_permission(role, "orders:read:own")
        orders = repo.list_orders_by_user(auth["userId"])
        if status:
            orders = [o for o in orders if o.get("status") == status]
    else:
        require_permission(role, "orders:read")
        orders = repo.list_orders(status=status)
    return success({"items": orders, "count": len(orders)})


def _get_order(auth, order_id):
    order = repo.get_order(order_id)
    if not order:
        raise NotFoundError("Pedido no encontrado")
    if not can_read_order(auth["role"], auth["userId"], order.get("userId")):
        raise ForbiddenError("No tienes permisos para ver este pedido")
    return success({"order": order})


def _update_status(event, auth, order_id):
    require_permission(auth["role"], "orders:manage")
    data = _body(event)
    new_status = data.get("status")
    if not new_status:
        return error("El campo status es obligatorio", 400)
    order = repo.update_order_status(order_id, new_status)
    repo.write_audit(auth["userId"], "UPDATE_ORDER_STATUS", order_id, "SUCCESS",
                     {"status": new_status})
    return success({"order": order})


def _cancel_order(auth, order_id):
    order = repo.get_order(order_id)
    if not order:
        raise NotFoundError("Pedido no encontrado")

    role = auth["role"]
    # OPERADOR/ADMIN pueden cancelar cualquiera; el CLIENTE solo su pedido PENDIENTE.
    from permissions import has_permission
    if has_permission(role, "orders:manage"):
        pass
    elif (
        has_permission(role, "orders:create")
        and order.get("userId") == auth["userId"]
        and order.get("status") == repo.STATUS_PENDING
    ):
        pass
    else:
        raise ForbiddenError("No tienes permisos para cancelar este pedido")

    cancelled = repo.cancel_order(order_id)
    repo.write_audit(auth["userId"], "CANCEL_ORDER", order_id, "SUCCESS",
                     {"previousStatus": order.get("status")})
    return success({"order": cancelled})
