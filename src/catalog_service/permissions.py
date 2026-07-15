from shared.errors import ForbiddenError

ROLE_PERMISSIONS = {
    "ADMIN": {
        "products:manage",
        "products:read",
        "stores:manage",
        "stores:read",
    },
    "OPERATOR": {
        "products:manage",
        "products:read",
        "stores:read",
    },
    "CLIENT": {
        "products:read",
        "stores:read",
    },
}


def has_permission(role: str, permission: str) -> bool:
    return permission in ROLE_PERMISSIONS.get(role, set())


def require_permission(role: str, permission: str) -> None:
    if not has_permission(role, permission):
        raise ForbiddenError("No tienes permisos para realizar esta acción")
