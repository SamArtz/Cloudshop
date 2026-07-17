from __future__ import annotations

import os
from decimal import Decimal

import boto3

from analytics import build_dashboard


dynamodb = boto3.resource("dynamodb")
orders_table = dynamodb.Table(os.environ["ORDERS_TABLE"])
products_table = dynamodb.Table(os.environ["PRODUCTS_TABLE"])
stores_table = dynamodb.Table(os.environ["STORES_TABLE"])


def _json_numbers(value):
    if isinstance(value, list):
        return [_json_numbers(item) for item in value]
    if isinstance(value, dict):
        return {key: _json_numbers(item) for key, item in value.items()}
    if isinstance(value, Decimal):
        return int(value) if value % 1 == 0 else float(value)
    return value


def _scan_all(table) -> list[dict]:
    """Lee todas las páginas de un Scan de DynamoDB."""
    items: list[dict] = []
    scan_kwargs = {}

    while True:
        response = table.scan(**scan_kwargs)
        items.extend(response.get("Items", []))
        last_key = response.get("LastEvaluatedKey")
        if not last_key:
            break
        scan_kwargs["ExclusiveStartKey"] = last_key

    return items


def get_executive_dashboard(top_n: int = 5) -> dict:
    orders = _scan_all(orders_table)
    products = _scan_all(products_table)
    stores = _scan_all(stores_table)
    return _json_numbers(build_dashboard(orders, products, stores, top_n=top_n))
