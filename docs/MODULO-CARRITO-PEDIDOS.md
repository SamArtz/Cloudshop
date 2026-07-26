# CloudShop Enterprise — Carrito & Pedidos (Order Service)

Módulos 4 (Carrito) y 5 (Pedidos) del proyecto final. Cubre además el
**Caso de prueba 2** (creación exitosa de pedido con evento, auditoría y correo).

## Componentes

| Componente | AWS | Descripción |
|---|---|---|
| Order Service | Lambda (Python 3.12) | API de carrito y pedidos |
| Notifications | Lambda (Python 3.12) | Consume EventBridge y envía correo (SES) |
| Carritos | DynamoDB (`*-carts`) | PK `userId`, 1 carrito por usuario |
| Pedidos | DynamoDB (`*-orders`) | PK `orderId` + GSI `userId-index`, `status-index` |
| Bus de eventos | EventBridge | Evento `OrderCreated` (`source=cloudshop.orders`) |
| Monitoreo | CloudWatch | Log groups + alarma de errores |
| Correo | SES | Confirmación de pedido |

## Endpoints

Todos requieren `Authorization: Bearer <JWT>` (validado por el Lambda Authorizer).

### Módulo 4 — Carrito (rol CLIENT)
| Método | Ruta | Acción |
|---|---|---|
| GET | `/cart` | Ver carrito |
| POST | `/cart/items` | Agregar producto `{ "productId", "quantity" }` |
| PUT | `/cart/items/{productId}` | Modificar cantidad `{ "quantity" }` (0 = eliminar) |
| DELETE | `/cart/items/{productId}` | Eliminar producto |
| DELETE | `/cart` | Vaciar carrito |

### Módulo 5 — Pedidos
| Método | Ruta | Rol | Acción |
|---|---|---|---|
| POST | `/orders` | CLIENT | Crear pedido desde el carrito |
| GET | `/orders` | CLIENT (propios) / OPERATOR·ADMIN (todos) | Listar (`?status=` opcional) |
| GET | `/orders/{orderId}` | dueño / OPERATOR·ADMIN | Consultar pedido |
| PATCH | `/orders/{orderId}/status` | OPERATOR | Actualizar estado `{ "status" }` |
| PATCH | `/orders/{orderId}/cancel` | OPERATOR (cualq.) / CLIENT (propio PENDIENTE) | Cancelar |

### Estados de pedido
`PENDIENTE → CONFIRMADO → EN_PREPARACION → ENVIADO → ENTREGADO`
y `CANCELADO` (desde cualquier estado no final). Las transiciones inválidas
devuelven `409`.

## Caso de prueba 2 — Creación exitosa de pedido

`POST /orders` ejecuta, de forma **atómica** (DynamoDB `TransactWriteItems`):

1. **Pedido creado** → item en tabla `orders` (estado `PENDIENTE`).
2. **Inventario actualizado** → descuenta `stock` de cada producto con condición
   `stock >= cantidad` (evita sobreventa; si falla, se revierte todo).
3. **Evento generado** → `PutEvents` `OrderCreated` a EventBridge.
4. **Auditoría registrada** → item en la tabla de auditoría (`CREATE_ORDER`).
5. **Correo enviado** → EventBridge dispara la Lambda `notifications`, que envía
   el correo por SES y audita `ORDER_EMAIL_SENT`.

### Ejemplo
```bash
BASE=https://<api-id>.execute-api.us-east-1.amazonaws.com/dev
TOKEN=<jwt-del-cliente>

# 1. Agregar producto al carrito
curl -X POST "$BASE/cart/items" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"productId":"<id>","quantity":2}'

# 2. Crear el pedido (dispara todo el flujo del Caso 2)
curl -X POST "$BASE/orders" -H "Authorization: Bearer $TOKEN"
```

Evidencias: item en `orders`, `stock` decrementado en `products`, evento en las
métricas de la regla EventBridge, entradas en la tabla de auditoría y correo SES.

## Despliegue (Terraform)

El módulo de pedidos forma parte del **stack unificado**. Ver
[EVENTOS-AUDITORIA-TERRAFORM.md](EVENTOS-AUDITORIA-TERRAFORM.md) (Caso 4):

```powershell
python scripts/stage_lambda.py all
cd terraform
copy terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

Ya no se requieren IDs externos de API/tablas: Auth, Catalog, Orders, EventBridge,
SES, auditoría y frontend se crean juntos.
## Seguridad (mínimo privilegio)
- El rol del Order Service solo puede: R/W carritos y pedidos, **leer y ajustar
  stock** de productos (no crear/borrar), escribir auditoría y publicar eventos.
- El rol de notifications solo puede: `ses:SendEmail` sobre la identidad
  verificada y escribir auditoría.
