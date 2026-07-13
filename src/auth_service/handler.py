import json
import os
import uuid
from datetime import datetime, timezone

import boto3

from auth_utils import hash_password, verify_password, create_access_token
from permissions import require_permission, can_access_user
from repository import (
    get_user_by_id,
    get_user_by_email,
    create_user,
    update_user,
    list_users,
    write_audit,
    public_user,
)

# Import compartido (cuando empaquetemos, shared va junto al cÃ³digo)
import sys
from pathlib import Path

# Permitir import de shared tanto en local como en el zip de Lambda
ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from shared.errors import AppError, UnauthorizedError, ForbiddenError, NotFoundError, ConflictError
from shared.response import success, error


def _body(event) -> dict:
    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        import base64
        raw = base64.b64decode(raw).decode("utf-8")
    if isinstance(raw, dict):
        return raw
    return json.loads(raw) if raw else {}


def _auth_context(event) -> dict:
    """Datos del Lambda Authorizer."""
    ctx = (event.get("requestContext") or {}).get("authorizer") or {}
    # A veces vienen anidados en "lambda" (HTTP API) o planos (REST)
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
    # Quitar stage si viene /dev/users...
    for stage in (f"/{os.environ.get('STAGE', 'dev')}",):
        if path.startswith(stage):
            path = path[len(stage):] or "/"
    return method, path


def handler(event, context):
    try:
        method, path = _route(event)

        # CORS preflight
        if method == "OPTIONS":
            return success({"ok": True})

        # ---------- Rutas pÃºblicas ----------
        if method == "POST" and path in ("/auth/register", "/auth/register/"):
            return register(event)

        if method == "POST" and path in ("/auth/login", "/auth/login/"):
            return login(event)

        # ---------- Rutas protegidas ----------
        auth = _auth_context(event)
        if not auth.get("userId") or not auth.get("role"):
            raise UnauthorizedError("Token invÃ¡lido o ausente")

        if method == "GET" and path in ("/users/me", "/users/me/"):
            return get_me(auth)

        if method == "GET" and path in ("/users", "/users/"):
            return get_users(auth)

        if method == "GET" and path.startswith("/users/"):
            user_id = path.strip("/").split("/")[-1]
            if user_id == "me":
                return get_me(auth)
            return get_user(auth, user_id)

        if method == "PUT" and path.startswith("/users/"):
            user_id = path.strip("/").split("/")[-1]
            return put_user(event, auth, user_id)

        if method == "PATCH" and path.endswith("/deactivate"):
            # /users/{id}/deactivate
            parts = [p for p in path.split("/") if p]
            # ["users", "{id}", "deactivate"]
            user_id = parts[1] if len(parts) >= 3 else None
            if not user_id:
                return error("Ruta invÃ¡lida", 400)
            return deactivate_user(auth, user_id)

        return error("Ruta no encontrada", 404)

    except AppError as e:
        return error(e.message, e.status_code)
    except json.JSONDecodeError:
        return error("JSON invÃ¡lido", 400)
    except Exception as e:
        print(f"Unhandled error: {e}")
        return error("Error interno", 500)


def register(event):
    data = _body(event)
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""
    full_name = (data.get("fullName") or "").strip()
    role = (data.get("role") or "CLIENT").upper()

    if not email or not password or not full_name:
        return error("email, password y fullName son obligatorios", 400)

    if len(password) < 8:
        return error("La contraseÃ±a debe tener al menos 8 caracteres", 400)

    # Registro pÃºblico solo CLIENT. ADMIN/OPERATOR los crea un ADMIN autenticado.
    auth = _auth_context(event)
    if role != "CLIENT":
        if not auth.get("role"):
            raise ForbiddenError("Solo un ADMIN puede crear usuarios con este rol")
        require_permission(auth["role"], "users:create")
        if role not in ("ADMIN", "OPERATOR", "CLIENT"):
            return error("Rol invÃ¡lido", 400)
    else:
        role = "CLIENT"

    if get_user_by_email(email):
        raise ConflictError("El email ya estÃ¡ registrado")

    user = create_user(email, hash_password(password), full_name, role)

    actor = auth.get("userId") or user["userId"]
    write_audit(actor, "CREATE_USER", user["userId"], "SUCCESS", {"email": email, "role": role})

    return success({"user": public_user(user)}, 201)


def login(event):
    data = _body(event)
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""

    if not email or not password:
        return error("email y password son obligatorios", 400)

    user = get_user_by_email(email)
    if not user or not verify_password(password, user["passwordHash"]):
        write_audit("anonymous", "LOGIN", email, "FAILURE")
        raise UnauthorizedError("Credenciales invÃ¡lidas")

    if user.get("status") != "ACTIVE":
        raise ForbiddenError("Usuario desactivado")

    token = create_access_token(user["userId"], user["email"], user["role"])
    write_audit(user["userId"], "LOGIN", user["userId"], "SUCCESS")

    return success({
        "accessToken": token,
        "tokenType": "Bearer",
        "user": public_user(user),
    })


def get_me(auth):
    user = get_user_by_id(auth["userId"])
    if not user:
        raise NotFoundError("Usuario no encontrado")
    return success({"user": public_user(user)})


def get_users(auth):
    require_permission(auth["role"], "users:read")  # â†’ 403 si no es ADMIN
    users = [public_user(u) for u in list_users()]
    return success({"users": users, "count": len(users)})


def get_user(auth, user_id: str):
    if not can_access_user(auth["role"], auth["userId"], user_id):
        # ADMIN ok; CLIENT solo self; resto 403
        if auth["role"] == "ADMIN":
            pass
        elif has_own_read(auth, user_id):
            pass
        else:
            raise ForbiddenError("No tienes permisos para realizar esta acciÃ³n")

    if auth["role"] != "ADMIN" and auth["userId"] != user_id:
        raise ForbiddenError("No tienes permisos para realizar esta acciÃ³n")

    if auth["role"] == "ADMIN":
        require_permission(auth["role"], "users:read")
    else:
        require_permission(auth["role"], "users:read:own")

    user = get_user_by_id(user_id)
    if not user:
        raise NotFoundError("Usuario no encontrado")
    return success({"user": public_user(user)})


def has_own_read(auth, user_id: str) -> bool:
    return auth["userId"] == user_id


def put_user(event, auth, user_id: str):
    data = _body(event)
    updates = {}

    if auth["role"] == "ADMIN":
        require_permission(auth["role"], "users:update")
        if "fullName" in data:
            updates["fullName"] = data["fullName"]
        if "role" in data:
            updates["role"] = str(data["role"]).upper()
        if "status" in data:
            updates["status"] = str(data["status"]).upper()
    else:
        # CLIENT solo a sÃ­ mismo y solo fullName
        if auth["userId"] != user_id:
            raise ForbiddenError("No tienes permisos para realizar esta acciÃ³n")
        require_permission(auth["role"], "users:update:own")
        if "fullName" in data:
            updates["fullName"] = data["fullName"]
        if "role" in data or "status" in data:
            raise ForbiddenError("No puedes cambiar role o status")

    user = update_user(user_id, updates)
    if not user:
        raise NotFoundError("Usuario no encontrado")

    write_audit(auth["userId"], "UPDATE_USER", user_id, "SUCCESS", updates)
    return success({"user": public_user(user)})


def deactivate_user(auth, user_id: str):
    require_permission(auth["role"], "users:deactivate")  # solo ADMIN

    user = update_user(user_id, {"status": "INACTIVE"})
    if not user:
        raise NotFoundError("Usuario no encontrado")

    write_audit(auth["userId"], "DEACTIVATE_USER", user_id, "SUCCESS")
    return success({"user": public_user(user)})
