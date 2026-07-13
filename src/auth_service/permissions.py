from shared.errors import ForbiddenError

# Matriz de permisos por rol (PDF sección 5)
ROLE_PERMISSIONS = {
    "ADMIN": {
        "users:create",
        "users:read",
        "users:update",
        "users:deactivate",
        "stores:manage",
        "products:manage",
        "orders:read",
        "reports:read",
    },
    "OPERATOR": {
        "inventory:manage",
        "orders:manage",
        "products:read",
    },
    "CLIENT": {
        "products:read",
        "cart:manage",
        "orders:create",
        "orders:read:own",
        "users:read:own",
        "users:update:own",
    },
}


def has_permission(role: str, permission: str) -> bool:
    return permission in ROLE_PERMISSIONS.get(role, set())


def require_permission(role: str, permission: str) -> None:
    if not has_permission(role, permission):
        raise ForbiddenError("No tienes permisos para realizar esta acción")


def can_access_user(request_role: str, request_user_id: str, target_user_id: str) -> bool:
    """ADMIN puede ver cualquiera; CLIENT solo a sí mismo."""
    if request_role == "ADMIN":
        return True
    if request_role == "CLIENT" and request_user_id == target_user_id:
        return True
    return False