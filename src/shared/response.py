import json


def api_response(status_code: int, body: dict, headers: dict | None = None):
    default_headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type,Authorization",
        "Access-Control-Allow-Methods": "GET,POST,PUT,PATCH,DELETE,OPTIONS",
    }
    if headers:
        default_headers.update(headers)

    return {
        "statusCode": status_code,
        "headers": default_headers,
        "body": json.dumps(body, default=str),
    }


def success(body: dict, status_code: int = 200):
    return api_response(status_code, body)


def error(message: str, status_code: int = 400, code: str | None = None):
    payload = {"error": message}
    if code:
        payload["code"] = code
    return api_response(status_code, payload)