# CloudShop Enterprise — Dashboard & Monitoreo

Responsabilidad de la **Persona 4** del proyecto final:

- Lambda **Report Service** en Python 3.12.
- Módulo 6: Dashboard ejecutivo.
- Logs, métricas, errores y latencia en Amazon CloudWatch.
- Caso de prueba 3: visualización de métricas.

## 1. Arquitectura

```text
Administrador
    │ JWT (rol ADMIN)
    ▼
API Gateway: GET /reports/dashboard
    │ Lambda Authorizer
    ▼
Report Service (Lambda)
    ├── Scan de Pedidos (DynamoDB)
    ├── Scan de Productos (DynamoDB)
    ├── Scan de Tiendas (DynamoDB)
    ├── Respuesta JSON del dashboard ejecutivo
    └── Logs estructurados + métricas EMF → CloudWatch
```

El servicio tiene permisos de **solo lectura** sobre las tablas necesarias. No
puede crear, actualizar ni eliminar pedidos, productos o tiendas.

## 2. API

### `GET /reports/dashboard`

Devuelve los seis indicadores solicitados:

1. Total de ventas.
2. Ventas por tienda.
3. Productos más vendidos.
4. Productos agotados.
5. Clientes con más compras.
6. Pedidos por estado.

**Autorización:** únicamente `ADMIN` mediante el permiso `reports:read`.

Parámetro opcional:

| Parámetro | Descripción | Valores |
|---|---|---|
| `top` | Cantidad de productos y clientes mostrados | 1–20; por defecto 5 |

Ejemplo:

```bash
BASE=https://<api-id>.execute-api.us-east-1.amazonaws.com/dev
TOKEN=<jwt-admin>

curl "$BASE/reports/dashboard?top=5" \
  -H "Authorization: Bearer $TOKEN"
```

Respuesta resumida:

```json
{
  "dashboard": {
    "generatedAt": "2026-07-17T20:00:00+00:00",
    "salesDefinition": "Pedidos en cualquier estado excepto CANCELADO",
    "summary": {
      "totalSales": 250.50,
      "totalOrders": 8,
      "salesOrders": 7,
      "cancelledOrders": 1,
      "outOfStockProducts": 2
    },
    "salesByStore": [],
    "topSellingProducts": [],
    "outOfStockProducts": [],
    "topCustomers": [],
    "ordersByStatus": []
  }
}
```

> El total de ventas excluye pedidos `CANCELADO`. Los demás estados se mantienen
> porque representan pedidos vigentes dentro del flujo comercial.

## 3. Diseño de datos utilizado

### Pedidos

Campos leídos: `orderId`, `userId`, `customerEmail`, `items`, `total`, `status`
y `createdAt`.

Cada elemento de `items` aporta `productId`, `name`, `price`, `quantity` y
`subtotal`.

### Productos

Campos leídos: `productId`, `code`, `name`, `stock`, `storeId` y `status`.

El producto se considera agotado cuando `stock <= 0` y su estado no es
`INACTIVE`.

### Tiendas

Campos leídos: `storeId` y `name` para presentar las ventas por tienda.

Los pedidos existentes no guardan `storeId` dentro de cada ítem. Por esa razón,
el reporte relaciona `productId → storeId` con la tabla de productos. El código
también acepta `storeId` en el ítem para mantener compatibilidad con futuras
versiones.

## 4. CloudWatch

### Logs

Log group:

```text
/aws/lambda/cloudshop-<stage>-report-service
```

Los logs son JSON e incluyen nivel, mensaje, request ID, usuario, rol y errores.
La retención se controla con `log_retention_days`.

### Métricas personalizadas

Namespace: `CloudShop/ReportService`

- `DashboardRequests`
- `DashboardLatency`
- `ApplicationErrors`
- `AuthorizationDenied`

Se publican mediante **Embedded Metric Format (EMF)** desde los logs de Lambda,
sin requerir permisos adicionales de `cloudwatch:PutMetricData`.

### Métricas administradas

El dashboard también muestra:

- Lambda: `Invocations`, `Errors` y `Duration`.
- API Gateway: `Count`, `Latency`, `4XXError` y `5XXError`.
- Seguridad: `AuthenticationErrors`, cuando se configura el log group del
  Authorizer.

### Alarmas

- Errores de la Lambda Report Service.
- Latencia promedio del dashboard por encima del umbral configurado.
- Errores `5XX` de API Gateway.

## 5. Caso de prueba 3 — Visualización de métricas

1. Registrar un usuario con rol `CLIENT`.
2. Cambiar su atributo `role` a `ADMIN` en la tabla de usuarios de DynamoDB.
3. Iniciar sesión otra vez para obtener un JWT nuevo con el rol actualizado.
4. Ejecutar varias veces `GET /reports/dashboard`.
5. Ejecutar una petición con un usuario `CLIENT` para producir un `403`.
6. Abrir **CloudWatch → Dashboards → `cloudshop-dev-monitoring`**.
7. Evidenciar en capturas:
   - solicitudes del dashboard;
   - latencia promedio;
   - errores o accesos denegados;
   - invocaciones de Lambda;
   - métricas de API Gateway;
   - logs recientes.

Las métricas personalizadas pueden tardar unos minutos en aparecer después de
la primera invocación.

## 6. Terraform

Recursos agregados en `terraform/reports.tf`:

- IAM Role y Policy de mínimo privilegio.
- Lambda Report Service.
- CloudWatch Log Group.
- Ruta `GET /reports/dashboard` y CORS.
- Métricas detalladas de API Gateway.
- Metric filter del Authorizer.
- Tres alarmas.
- Dashboard de CloudWatch.

Variables nuevas:

```hcl
stores_table_name          = "cloudshop-dev-stores"
stores_table_arn           = "arn:aws:dynamodb:...:table/cloudshop-dev-stores"
api_gateway_name           = "cloudshop-api"
authorizer_log_group_name  = "/aws/lambda/cloudshop-dev-authorizer"
report_latency_alarm_ms    = 3000
```

Despliegue:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

Como API Gateway es compartido entre módulos, la persona responsable de la
integración final debe incorporar este deployment al `main.tf` o redesplegar el
stage `dev` después de agregar la ruta.

## 7. Consideración de escalabilidad

Para el alcance académico, el reporte pagina los `Scan` de DynamoDB y calcula
los indicadores bajo demanda. En un escenario empresarial con millones de
registros, la evolución recomendada sería mantener agregados por evento usando
EventBridge o DynamoDB Streams, reduciendo scans y tiempo de respuesta.
