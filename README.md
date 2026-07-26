# CloudShop Enterprise

Plataforma de comercio electrónico cloud-native (AWS + Terraform).

## Scope del repositorio

| Área | Componentes |
|---|---|
| Auth & seguridad | Auth Service, Lambda Authorizer JWT, IAM |
| Catálogo | Productos y tiendas |
| Carrito & pedidos | Order Service + EventBridge + SES |
| Dashboard | Report Service + CloudWatch (Caso 3) |
| Auditoría | DynamoDB `audit-logs` |
| Frontend | S3 + CloudFront + WAF |
| IaC | Stack Terraform unificado (`terraform/main.tf`) |

## Stack AWS

Lambda · API Gateway · DynamoDB · EventBridge · SES · S3 · CloudFront · WAF ·
Secrets Manager · CloudWatch · IAM · Terraform

## Despliegue completo (Caso de prueba 4)

Ver guía detallada: [docs/EVENTOS-AUDITORIA-TERRAFORM.md](docs/EVENTOS-AUDITORIA-TERRAFORM.md)

```powershell
python scripts/stage_lambda.py all
cd terraform
copy terraform.tfvars.example terraform.tfvars
# editar ses_sender_email
terraform init
terraform apply
```

## Documentación por módulo

- [Carrito & Pedidos / Caso 2](docs/MODULO-CARRITO-PEDIDOS.md)
- [Dashboard & Monitoreo / Caso 3](docs/MODULO-DASHBOARD-MONITOREO.md)
- [Eventos, Auditoría & Terraform / Caso 4](docs/EVENTOS-AUDITORIA-TERRAFORM.md)

## Módulo 6 — Dashboard & Monitoreo

- `src/report_service`: Lambda Python del dashboard ejecutivo.
- `terraform/reports.tf`: API, IAM, CloudWatch dashboard, alarmas y métricas.
- Endpoint: `GET /reports/dashboard` (solo rol `ADMIN`).

## Estructura

```
src/
  auth_service/      # Usuarios + login/register
  authorizer/        # JWT authorizer
  catalog_service/   # Productos y tiendas
  order_service/     # Carrito y pedidos
  report_service/    # Dashboard ejecutivo
  notifications/     # EventBridge → SES + auditoría
  shared/
frontend/            # Estáticos (S3/CloudFront)
terraform/           # Stack completo (main.tf)
scripts/             # Empaquetado de Lambdas
docs/
```
