from __future__ import annotations

import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from shared.errors import AppError, UnauthorizedError
from shared.response import error, success

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from permissions import require_permission
import repository as repo

STAGE = os.environ.get("STAGE", "dev")
SERVICE_NAME = "ReportService"
METRIC_NAMESPACE = "CloudShop/ReportService"


def _auth_context(event) -> dict:
    ctx = (event.get("requestContext") or {}).get("authorizer") or {}
    if "lambda" in ctx and isinstance(ctx["lambda"], dict):
        ctx = ctx["lambda"]
    return {
        "userId": ctx.get("userId") or ctx.get("principalId"),
        "role": ctx.get("role"),
        "email": ctx.get("email"),
    }


def _route(event) -> tuple[str, str]:
    method = (
        event.get("httpMethod")
        or event.get("requestContext", {}).get("http", {}).get("method")
        or ""
    ).upper()
    path = event.get("path") or event.get("rawPath") or ""
    stage_prefix = f"/{STAGE}"
    if path.startswith(stage_prefix):
        path = path[len(stage_prefix):] or "/"
    return method, path.rstrip("/") or "/"


def _top_n(event) -> int:
    params = event.get("queryStringParameters") or {}
    raw = params.get("top", "5")
    try:
        value = int(raw)
    except (TypeError, ValueError) as exc:
        raise AppError("El parámetro top debe ser un número entero", 400) from exc
    if value < 1 or value > 20:
        raise AppError("El parámetro top debe estar entre 1 y 20", 400)
    return value


def _log(level: str, message: str, **fields) -> None:
    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": level,
        "service": SERVICE_NAME,
        "stage": STAGE,
        "message": message,
        **fields,
    }
    print(json.dumps(payload, default=str))


def _emit_metrics(
    latency_ms: float,
    *,
    application_errors: int = 0,
    authorization_denied: int = 0,
) -> None:
    """Publica métricas personalizadas con CloudWatch Embedded Metric Format."""
    metric_event = {
        "_aws": {
            "Timestamp": int(time.time() * 1000),
            "CloudWatchMetrics": [
                {
                    "Namespace": METRIC_NAMESPACE,
                    "Dimensions": [["Service", "Stage"]],
                    "Metrics": [
                        {"Name": "DashboardRequests", "Unit": "Count"},
                        {"Name": "DashboardLatency", "Unit": "Milliseconds"},
                        {"Name": "ApplicationErrors", "Unit": "Count"},
                        {"Name": "AuthorizationDenied", "Unit": "Count"},
                    ],
                }
            ],
        },
        "Service": SERVICE_NAME,
        "Stage": STAGE,
        "DashboardRequests": 1,
        "DashboardLatency": round(latency_ms, 2),
        "ApplicationErrors": application_errors,
        "AuthorizationDenied": authorization_denied,
    }
    print(json.dumps(metric_event))


def handler(event, context):
    started = time.perf_counter()
    request_id = getattr(context, "aws_request_id", "local")
    application_errors = 0
    authorization_denied = 0

    try:
        method, path = _route(event)

        if method == "OPTIONS":
            return success({"ok": True})

        auth = _auth_context(event)
        if not auth.get("userId") or not auth.get("role"):
            authorization_denied = 1
            raise UnauthorizedError("Token inválido o ausente")

        require_permission(auth["role"], "reports:read")

        if method == "GET" and path == "/reports/dashboard":
            dashboard = repo.get_executive_dashboard(top_n=_top_n(event))
            _log(
                "INFO",
                "Dashboard ejecutivo generado",
                requestId=request_id,
                userId=auth["userId"],
                role=auth["role"],
                totalOrders=dashboard["summary"]["totalOrders"],
            )
            return success({"dashboard": dashboard})

        return error("Ruta de reportes no encontrada", 404)

    except AppError as exc:
        if exc.status_code in (401, 403):
            authorization_denied = 1
        else:
            application_errors = 1
        _log(
            "WARN" if exc.status_code < 500 else "ERROR",
            exc.message,
            requestId=request_id,
            statusCode=exc.status_code,
        )
        return error(exc.message, exc.status_code)
    except Exception as exc:  # noqa: BLE001
        application_errors = 1
        _log(
            "ERROR",
            "Error no controlado al generar reportes",
            requestId=request_id,
            errorType=type(exc).__name__,
            error=str(exc),
        )
        return error("Error interno", 500)
    finally:
        elapsed_ms = (time.perf_counter() - started) * 1000
        _emit_metrics(
            elapsed_ms,
            application_errors=application_errors,
            authorization_denied=authorization_denied,
        )
