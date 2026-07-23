# CloudShop — Frontend (Parte 5)

Frontend estático para **S3 + CloudFront**. No necesita build ni Node.js.

## Cómo abrirlo en local

Desde la carpeta `frontend`:

```powershell
# Opción A (Python)
python -m http.server 5500

# Opción B (si tienes npx)
npx --yes serve -l 5500
```

Luego abre: http://localhost:5500

> No abras el `index.html` con doble clic (`file://`). El navegador bloquea módulos ES.
> Usa siempre un servidor local como arriba.

## Configurar la URL del API

Cuando tu equipo te pase la Invoke URL (stage `dev`):

1. Pégala en el campo **URL del API** del login, **o**
2. Entra a **Ajustes** y guárdala.

Ejemplo:
`https://xxxx.execute-api.us-east-1.amazonaws.com/dev`

Se guarda en `localStorage` del navegador.

## Credenciales de prueba

```json
{
  "email": "cliente2@test.com",
  "password": "Password1"
}
```

## Pantallas

| Vista | Qué hace |
|---|---|
| Login / Registro | `POST /auth/login`, `POST /auth/register` |
| Productos | `GET /products` + agregar al carrito |
| Carrito | `GET/POST/PUT/DELETE /cart...` + crear pedido |
| Pedidos | `GET /orders` |
| Ajustes | Guardar `API_BASE_URL` |

## Estructura

```
frontend/
  index.html
  css/styles.css
  js/config.js
  js/api.js
  js/app.js
  README.md
```

## Siguiente paso (tu parte AWS)

1. Subir esta carpeta a un bucket **S3**
2. Servirla con **CloudFront**
3. Proteger la entrada con **AWS WAF**
