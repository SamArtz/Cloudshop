# 5. Frontend & Entrada (S3, CloudFront, API Gateway, AWS WAF)

**Integrante:** Ariana  
**Módulo:** Parte 5 — Frontend & Entrada  
**Fecha de despliegue:** 18 de julio de 2026  

---

## 5.1 Objetivo del módulo

Exponer el frontend de CloudShop Enterprise de forma segura, escalable y automatizada, utilizando:

- **Amazon S3** para el almacenamiento estático del frontend  
- **Amazon CloudFront** como CDN y punto de entrada HTTPS  
- **Amazon API Gateway** como puerta de acceso al backend (stack compartido del equipo)  
- **AWS WAF** para proteger el perímetro de entrada  

Este módulo cumple los servicios obligatorios del proyecto final en la capa de Frontend y Seguridad perimetral, desplegados con **Terraform** (sin creación manual de recursos).

---

## 5.2 Arquitectura de entrada

```
Usuario (navegador)
        │
        ▼
  AWS WAF  (Web ACL asociado a CloudFront)
        │
        ▼
  Amazon CloudFront  (CDN + HTTPS)
        │
        ├──► Amazon S3  (frontend estático: HTML/CSS/JS)
        │
        └──► (consumo vía navegador) Amazon API Gateway
                    │
                    ▼
              AWS Lambda (Auth, Catalog, Orders, …)
                    │
                    ▼
              Amazon DynamoDB
```

### Flujo

1. El usuario abre la URL de CloudFront.  
2. WAF evalúa la petición (reglas managed + rate limit).  
3. CloudFront sirve los archivos del frontend desde S3 (origen privado con OAC).  
4. El frontend llama al API Gateway (Invoke URL del stage `dev`) con JWT Bearer.  
5. API Gateway + Lambda Authorizer validan autenticación/autorización hacia los servicios backend.

---

## 5.3 Diseño del frontend

### Tecnologías

- HTML5, CSS3 y JavaScript (ES Modules)  
- Sin framework ni build: apto para hosting estático en S3  
- Configuración de `API_BASE_URL` por pantalla (localStorage)

### Estructura del código

```
frontend/
  index.html
  css/styles.css
  js/config.js
  js/api.js
  js/app.js
  README.md
```

### Pantallas / funcionalidad

| Vista | Endpoints que consume |
|---|---|
| Login | `POST /auth/login` |
| Registro | `POST /auth/register` |
| Productos | `GET /products`, `POST /cart/items` |
| Carrito | `GET/PUT/DELETE /cart…`, `POST /orders` |
| Pedidos | `GET /orders` |
| Ajustes | Guarda la URL base del API Gateway |

### Credenciales de prueba (CLIENT)

```json
{
  "email": "cliente2@test.com",
  "password": "Password1"
}
```

---

## 5.4 Amazon S3 (frontend)

### Propósito

Almacenar de forma privada los archivos estáticos del frontend.

### Configuración aplicada

| Aspecto | Valor |
|---|---|
| Bucket | `cloudshop-dev-frontend-526053389319` |
| ARN | `arn:aws:s3:::cloudshop-dev-frontend-526053389319` |
| Acceso público | Bloqueado (Block Public Access) |
| Cifrado | SSE-S3 (AES256) |
| Versionado | Habilitado |
| Lectura | Solo CloudFront mediante Origin Access Control (OAC) |

### Objetos desplegados

- `index.html`  
- `css/styles.css`  
- `js/config.js`, `js/api.js`, `js/app.js`  
- `README.md`  

> **Evidencia:** captura de la consola S3 mostrando el bucket y los objetos.

---

## 5.5 Amazon CloudFront

### Propósito

Distribuir el frontend con baja latencia, HTTPS y caché de contenido estático.

### Configuración aplicada

| Aspecto | Valor |
|---|---|
| Distribution ID | `E2ULMP0LOBEKVT` |
| Dominio | `d30u8oxpw19m23.cloudfront.net` |
| URL pública | https://d30u8oxpw19m23.cloudfront.net |
| Origen | Bucket S3 (privado) + OAC |
| Root object | `index.html` |
| Protocolo | Redirect HTTP → HTTPS |
| WAF | Asociado (`cloudshop-dev-frontend-waf`) |

> **Evidencia:** captura de CloudFront (Distribution ID, domain name, origen S3) y captura del navegador abriendo la URL HTTPS.

---

## 5.6 Amazon API Gateway (entrada al backend)

### Propósito

Exponer las APIs REST de CloudShop (Auth, Catálogo, Carrito, Pedidos, etc.) hacia el frontend.

### Integración con este módulo

- API Gateway es un recurso **compartido** del proyecto (creado/administrado por el módulo de Auth e integrado por los demás servicios).  
- El frontend se configura con la **Invoke URL** del stage `dev`:  
  `https://<api-id>.execute-api.us-east-1.amazonaws.com/dev`  
- Las rutas protegidas envían `Authorization: Bearer <JWT>`.  
- CORS habilitado en el backend para `Content-Type` y `Authorization`.

### Relación con el PDF del proyecto

API Gateway forma parte de la capa de entrada obligatoria. En esta parte se documenta su rol como puerta del backend y se deja el frontend preparado para consumirlo.

> **Evidencia (cuando el equipo comparta la URL):** captura de API Gateway → Stages → Invoke URL, y captura de DevTools → Network con llamadas autenticadas.

---

## 5.7 AWS WAF

### Propósito

Proteger la entrada HTTP del frontend en CloudFront contra tráfico abusivo y patrones de ataque conocidos.

### Web ACL

| Aspecto | Valor |
|---|---|
| Nombre | `cloudshop-dev-frontend-waf` |
| Scope | `CLOUDFRONT` |
| ARN | `arn:aws:wafv2:us-east-1:526053389319:global/webacl/cloudshop-dev-frontend-waf/fa348575-222b-4988-8f0a-60beb5859a75` |
| Acción por defecto | Allow |

### Reglas configuradas

| Prioridad | Regla | Acción |
|---|---|---|
| 1 | AWSManagedRulesCommonRuleSet | Bloqueo según reglas AWS (XSS, etc.) |
| 2 | AWSManagedRulesKnownBadInputsRuleSet | Bloqueo de entradas maliciosas conocidas |
| 3 | RateLimitPerIP (2000 req / 5 min / IP) | Block |

> **Evidencia:** captura de WAF → Web ACLs → reglas asociadas a la distribución CloudFront.

---

## 5.8 Infraestructura como Código (Terraform)

### Ubicación

```
terraform/frontend/
  providers.tf
  variables.tf
  frontend.tf
  outputs.tf
  terraform.tfvars.example
  README.md
```

### Comandos de despliegue

```powershell
cd terraform\frontend
copy terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

### Resultado del apply

```
Apply complete! Resources: 15 added, 0 changed, 0 destroyed.

Outputs:
  cloudfront_url         = "https://d30u8oxpw19m23.cloudfront.net"
  frontend_bucket_name   = "cloudshop-dev-frontend-526053389319"
  cloudfront_distribution_id = "E2ULMP0LOBEKVT"
  waf_web_acl_name       = "cloudshop-dev-frontend-waf"
```

> **Evidencia:** captura de `terraform apply` exitoso y de los outputs.

---

## 5.9 Diseño de seguridad (este módulo)

- Bucket S3 **no público**; acceso solo vía CloudFront OAC.  
- Tráfico de usuario forzado a **HTTPS**.  
- WAF con reglas administradas AWS + rate limiting.  
- Credenciales/JWT no se hardcodean en el repositorio; el token vive en `localStorage` del navegador tras el login.  
- Roles IAM del despliegue siguen el principio de mínimo privilegio del usuario/ejecutor de Terraform.

---

## 5.10 Evidencias de despliegue (checklist para pegar capturas)

1. [ ] Consola **S3** — bucket `cloudshop-dev-frontend-526053389319` con objetos  
2. [ ] Consola **CloudFront** — distribución `E2ULMP0LOBEKVT`  
3. [ ] Navegador — sitio en https://d30u8oxpw19m23.cloudfront.net  
4. [ ] Consola **WAF** — Web ACL `cloudshop-dev-frontend-waf` con 3 reglas  
5. [ ] Terminal — `terraform apply` / outputs  
6. [ ] (Pendiente equipo) **API Gateway** Invoke URL + login exitoso desde el frontend  

---

## 5.11 Estado del módulo

| Entregable | Estado |
|---|---|
| Frontend estático | Completado |
| S3 + CloudFront + WAF con Terraform | Completado y desplegado |
| Documentación de arquitectura/seguridad | Completado |
| Conexión end-to-end con API Gateway del equipo | Pendiente de recibir Invoke URL |

Cuando el equipo entregue la Invoke URL del API, basta con pegarla en **Ajustes** del frontend desplegado; no requiere redesplegar S3/CloudFront/WAF.
