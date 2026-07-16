from shared.errors import ForbiddenError

# Matriz de permisos por rol para Carrito (Módulo 4) y Pedidos (Módulo 5).
# Coherente con src/auth_service/permissions.py (PDF sección 5).
#
#   Cliente   -> comprar productos (carrito) y consultar SUS pedidos.
#   Operador  -> gestionar pedidos (cambiar estado, cancelar) y verlos todos.
#   Admin     -> consultar pedidos (reportes). No opera pedidos (mínimo privilegio).
ROLE_PERMISSIONS = {
    "ADMIN": {
        "orders:read",          # ver cualquier pedido (reportes)
    },
    "OPERATOR": {
        "orders:manage",        # cambiar estado / cancelar cualquier pedido
        "orders:read",          # ver cualquier pedido
    },
    "CLIENT": {
        "cart:manage",          # agregar / modificar / eliminar / vaciar carrito
        "orders:create",        # crear pedido a partir del carrito
        "orders:read:own",      # consultar únicamente sus propios pedidos
    },
}


def has_permission(role: str, permission: str) -> bool:
    return permission in ROLE_PERMISSIONS.get(role, set())


def require_permission(role: str, permission: str) -> None:
    if not has_permission(role, permission):
        raise ForbiddenError("No tienes permisos para realizar esta acción")


def can_read_order(role: str, request_user_id: str, order_owner_id: str) -> bool:
    """ADMIN/OPERATOR ven cualquier pedido; CLIENT solo los suyos."""
    if has_permission(role, "orders:read"):
        return True
    if has_permission(role, "orders:read:own") and request_user_id == order_owner_id:
        return True
    return False
