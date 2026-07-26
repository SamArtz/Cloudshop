# CloudShop Enterprise — Eventos, Auditoría & Terraform General

Parte del proyecto que cubre **EventBridge**, **DynamoDB AuditLogs**, **Amazon SES**,
la **integración final de Terraform (`main.tf`)** y el **Caso de prueba 4**
(despliegue completo).

## Qué despliega este stack

| Requisito PDF | Recurso Terraform |
|---|---|
| EventBridge | `events.tf` — bus + reglas `OrderCreated` / `OrderCancelled` + archivo |
| Auditoría | `dynamodb.tf` — tabla `*-audit-logs` (PK `auditId`, SK `createdAt` + GSIs) |
| SES | `ses.tf` — identidad del remitente |
| API Gateway | `api.tf` — REST API + stage + logs |
| Lambdas | auth, authorizer, catalog, order, notifications |
| DynamoDB | users, audit-logs, products, stores, carts, orders |
| IAM | roles/policies de mínimo privilegio por Lambda |
| CloudWatch | log groups, alarmas, dashboard |
| S3 + CloudFront + WAF | `frontend.tf` |

## Flujo de eventos (PDF §6)

```
POST /orders
    │
    ├─► DynamoDB orders (+ descuenta stock en products)   [atómico]
    ├─► PutEvents OrderCreated ──► EventBridge bus
    │                                    │
    │                                    └─► Lambda notifications ──► SES + AuditLogs
    └─► AuditLogs CREATE_ORDER
```

Cancelación (`PATCH /orders/{id}/cancel`) publica `OrderCancelled` y audita
`CANCEL_ORDER`; la Lambda de notificaciones envía el correo de cancelación.

## Formato de auditoría (PDF §7)

Cada acción relevante escribe un ítem en `cloudshop-dev-audit-logs`:

```json
{
  "auditId": "uuid",
  "createdAt": "2026-07-25T18:00:00+00:00",
  "userId": "admin01",
  "action": "DELETE_PRODUCT",
  "resourceType": "PRODUCT",
  "resourceId": "...",
  "result": "SUCCESS",
  "details": {}
}
```

Acciones típicas: `CREATE_USER`, `LOGIN`, `DELETE_PRODUCT`, `CREATE_ORDER`,
`CANCEL_ORDER`, `ORDER_EMAIL_SENT`, `UPDATE_ORDER_STATUS`, etc.

## Caso de prueba 4 — Despliegue completo con Terraform

### Prerrequisitos
1. AWS CLI configurado (`aws sts get-caller-identity`).
2. Terraform >= 1.5.
3. Python 3.12 + pip (para empaquetar Lambdas con dependencias Linux).
4. Un correo válido para SES (sandbox: verificar remitente y destinatarios).

### Pasos

```powershell
# 1) Empaquetar Lambdas (genera terraform/.build/*)
python scripts/stage_lambda.py all

# 2) Variables
cd terraform
copy terraform.tfvars.example terraform.tfvars
# Editar ses_sender_email = "tu-correo@..."

# 3) Despliegue completo
terraform init
terraform plan
terraform apply
```

### Evidencias esperadas (Caso 4)
Tras `terraform apply` exitoso, verifica en la consola AWS o con outputs:

```powershell
terraform output
```

Debes ver al menos:
- `api_base_url` — API Gateway desplegado
- `frontend_url` — CloudFront + S3 + WAF
- `event_bus_name` + reglas de EventBridge
- `audit_logs_table`
- `ses_sender_email`
- `lambda_functions` (5 funciones)
- `cloudwatch_dashboard`

Confirma también el correo de verificación SES en tu bandeja y haz click en el enlace.

### Destruir (opcional)

```powershell
terraform destroy
```

## Estructura de archivos Terraform

```
terraform/
  main.tf                 # Orquestación / locals (integración final)
  providers.tf
  variables.tf
  outputs.tf
  dynamodb.tf             # Incluye AuditLogs
  events.tf               # EventBridge
  ses.tf                  # Amazon SES
  api.tf                  # API Gateway
  auth.tf
  catalog.tf
  orders.tf               # Order Service + Notifications Lambda
  frontend.tf             # S3 / CloudFront / WAF
  monitoring.tf           # CloudWatch
  terraform.tfvars.example
```

## Nota sobre el empaquetado

`null_resource` vuelve a ejecutar `scripts/stage_lambda.py` cuando cambia el
código fuente. La primera vez (o si borras `.build/`) conviene correr
`python scripts/stage_lambda.py all` antes de `terraform plan` para que existan
los directorios que usa `archive_file`.
