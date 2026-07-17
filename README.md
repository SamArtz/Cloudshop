@'
# CloudShop Enterprise - Auth & Security

Módulo de autenticación y gestión de usuarios para CloudShop Enterprise (AWS + Terraform).

## Scope
- Auth Service (Lambda Python 3.12)
- Lambda Authorizer (JWT)
- IAM (mínimo privilegio)
- DynamoDB (Users + AuditLogs)
- API Gateway REST
- Caso de prueba: 403 Forbidden sin permisos

## Stack
- AWS: Lambda, API Gateway, DynamoDB, Secrets Manager, IAM, CloudWatch
- IaC: Terraform
- Auth: JWT (PyJWT) + bcrypt

## Estructura
## Módulo 6 — Dashboard & Monitoreo

- `src/report_service`: Lambda Python del dashboard ejecutivo.
- `terraform/reports.tf`: API, IAM, CloudWatch dashboard, alarmas y métricas.
- `docs/MODULO-DASHBOARD-MONITOREO.md`: documentación y Caso de prueba 3.
- Endpoint: `GET /reports/dashboard` (solo rol `ADMIN`).
