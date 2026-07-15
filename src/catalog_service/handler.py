import base64
import json
import os
import sys
from pathlib import Path

from shared.errors import AppError, UnauthorizedError, ForbiddenError, NotFoundError, ConflictError
from shared.response import success, error

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from permissions import require_permission
from repository import (
    create_product,
    get_product_by_id,
    list_products,
    list_products_by_store,
    update_product,
    delete_product,
    create_store,
    get_store_by_id,
    list_stores,
    update_store,
    deactivate_store,
    write_audit,
)


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
    method = (event.get("httpMethod") or event.get("requestContext", {}).get("http", {}).get("method") or "").upper()
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

        # -------- Productos --------
        if method == "POST" and path in ("/products", "/products/"):
            return post_product(event, auth)
        if method == "GET" and path in ("/products", "/products/"):
            return get_products(auth)
        if method == "GET" and path.startswith("/products/"):
            product_id = path.strip("/").split("/")[-1]
            return get_product(auth, product_id)
        if method == "PUT" and path.startswith("/products/"):
            product_id = path.strip("/").split("/")[-1]
            return put_product(event, auth, product_id)
        if method == "DELETE" and path.startswith("/products/"):
            product_id = path.strip("/").split("/")[-1]
            return delete_product_route(auth, product_id)

        # -------- Tiendas --------
        if method == "POST" and path in ("/stores", "/stores/"):
            return post_store(event, auth)
        if method == "GET" and path in ("/stores", "/stores/"):
            return get_stores(auth)
        if method == "GET" and path.startswith("/stores/"):
            store_id = path.strip("/").split("/")[-1]
            return get_store(auth, store_id)
        if method == "PUT" and path.startswith("/stores/"):
            store_id = path.strip("/").split("/")[-1]
            return put_store(event, auth, store_id)
        if method == "PATCH" and path.endswith("/deactivate"):
            parts = [p for p in path.split("/") if p]
            if len(parts) >= 3 and parts[0] == "stores":
                store_id = parts[1]
                return deactivate_store_route(auth, store_id)

        return error("Ruta no encontrada", 404)

    except AppError as e:
        return error(e.message, e.status_code)
    except json.JSONDecodeError:
        return error("JSON inválido", 400)
    except Exception as e:
        print(f"Unhandled error: {e}")
        return error("Error interno", 500)


def post_product(event, auth):
    require_permission(auth["role"], "products:manage")
    data = _body(event)
    required = ["code", "name", "description", "category", "price", "stock", "storeId"]
    missing = [field for field in required if not data.get(field)]
    if missing:
        return error(f"Campos obligatorios faltantes: {', '.join(missing)}", 400)

    store = get_store_by_id(data["storeId"])
    if not store:
        raise NotFoundError("Tienda no encontrada")
    if store.get("status") == "INACTIVE":
        return error("No se pueden crear productos en una tienda inactiva", 400)

    product = create_product(
        code=data["code"],
        name=data["name"],
        description=data["description"],
        category=data["category"],
        price=data["price"],
        stock=data["stock"],
        store_id=data["storeId"],
    )
    write_audit(auth["userId"], "CREATE_PRODUCT", "PRODUCT", product["productId"], "SUCCESS", {"code": product["code"]})
    return success({"product": product}, 201)


def get_products(auth):
    require_permission(auth["role"], "products:read")
    products = list_products()
    return success({"items": products, "count": len(products)})


def get_product(auth, product_id):
    require_permission(auth["role"], "products:read")
    product = get_product_by_id(product_id)
    if not product:
        raise NotFoundError("Producto no encontrado")
    return success({"product": product})


def put_product(event, auth, product_id):
    require_permission(auth["role"], "products:manage")
    data = _body(event)
    if not data:
        return error("No hay datos para actualizar", 400)

    existing = get_product_by_id(product_id)
    if not existing:
        raise NotFoundError("Producto no encontrado")

    if data.get("storeId"):
        store = get_store_by_id(data["storeId"])
        if not store:
            raise NotFoundError("Tienda no encontrada")
        if store.get("status") == "INACTIVE":
            return error("No se pueden asignar productos a una tienda inactiva", 400)

    product = update_product(product_id, data)
    write_audit(auth["userId"], "UPDATE_PRODUCT", "PRODUCT", product_id, "SUCCESS", data)
    return success({"product": product})


def delete_product_route(auth, product_id):
    require_permission(auth["role"], "products:manage")
    existing = get_product_by_id(product_id)
    if not existing:
        raise NotFoundError("Producto no encontrado")
    deleted = delete_product(product_id)
    write_audit(auth["userId"], "DELETE_PRODUCT", "PRODUCT", product_id, "SUCCESS", {"code": existing.get("code")})
    return success({"deleted": deleted}, 200)


def post_store(event, auth):
    require_permission(auth["role"], "stores:manage")
    data = _body(event)
    if not data.get("name") or not data.get("ownerId"):
        return error("name y ownerId son obligatorios", 400)

    store = create_store(
        name=data["name"],
        owner_id=data["ownerId"],
        description=data.get("description"),
    )
    write_audit(auth["userId"], "CREATE_STORE", "STORE", store["storeId"], "SUCCESS", {"name": store["name"]})
    return success({"store": store}, 201)


def get_stores(auth):
    require_permission(auth["role"], "stores:read")
    stores = list_stores()
    return success({"items": stores, "count": len(stores)})


def get_store(auth, store_id):
    require_permission(auth["role"], "stores:read")
    store = get_store_by_id(store_id)
    if not store:
        raise NotFoundError("Tienda no encontrada")
    products = list_products_by_store(store_id)
    return success({"store": store, "products": products})


def put_store(event, auth, store_id):
    require_permission(auth["role"], "stores:manage")
    data = _body(event)
    existing = get_store_by_id(store_id)
    if not existing:
        raise NotFoundError("Tienda no encontrada")

    store = update_store(store_id, data)
    write_audit(auth["userId"], "UPDATE_STORE", "STORE", store_id, "SUCCESS", data)
    return success({"store": store})


def deactivate_store_route(auth, store_id):
    require_permission(auth["role"], "stores:manage")
    existing = get_store_by_id(store_id)
    if not existing:
        raise NotFoundError("Tienda no encontrada")
    store = deactivate_store(store_id)
    write_audit(auth["userId"], "DEACTIVATE_STORE", "STORE", store_id, "SUCCESS", {"status": store.get("status")})
    return success({"store": store})
