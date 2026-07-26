# Terraform — Parte 5: Frontend & Entrada

Stack independiente para tu módulo:

| Recurso | Servicio AWS |
|---|---|
| Bucket privado del frontend | **S3** |
| CDN + HTTPS | **CloudFront** |
| Protección perimetral | **AWS WAF** |

> **API Gateway** ya lo creó el módulo de Auth del equipo. Tu frontend se conecta
> pegando la Invoke URL en Ajustes. Este stack no lo vuelve a crear (evita
> duplicarlo). La persona 6 lo unifica en el `main.tf` general.

## Requisitos

- AWS CLI configurado (`aws sts get-caller-identity` debe funcionar)
- Terraform >= 1.5
- Permisos IAM para S3, CloudFront y WAFv2

## Despliegue

```powershell
cd terraform\frontend
copy terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

Al terminar, Terraform imprime:

- `cloudfront_url` → abre esa URL en el navegador
- `frontend_bucket_name` → evidencia S3
- `waf_web_acl_name` → evidencia WAF

## Después del apply

1. Abre la `cloudfront_url` (puede tardar 2–5 min en propagarse).
2. Cuando tengas la URL del API Gateway, pégala en **Ajustes** del frontend.
3. Capturas para el PDF: S3, CloudFront, WAF y el sitio abriendo por HTTPS.

## Actualizar el frontend

Si cambias archivos en `/frontend` y `upload_frontend = true`:

```powershell
terraform apply
```

Luego invalida caché de CloudFront (opcional, si no ves cambios):

```powershell
aws cloudfront create-invalidation --distribution-id <ID> --paths "/*"
```

## Costos (aviso de estudiante)

WAF tiene costo fijo pequeño por Web ACL + reglas. Cuando termine el curso,
borra el stack:

```powershell
terraform destroy
```

## Evidencias sugeridas para el documento

1. `terraform plan` / `terraform apply` exitoso  
2. Consola S3 con el bucket y objetos (`index.html`, `css/`, `js/`)  
3. Consola CloudFront (Distribution ID + domain)  
4. Consola WAF (Web ACL + reglas managed + rate limit)  
5. Navegador abriendo `https://xxxx.cloudfront.net`
