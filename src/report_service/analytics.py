from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from typing import Any

KNOWN_STATUSES = [
    "PENDIENTE",
    "CONFIRMADO",
    "EN_PREPARACION",
    "ENVIADO",
    "ENTREGADO",
    "CANCELADO",
]
EXCLUDED_FROM_SALES = {"CANCELADO"}
UNKNOWN_STORE_ID = "UNKNOWN"
UNKNOWN_STORE_NAME = "Tienda no identificada"


def _number(value: Any) -> Decimal:
    if value in (None, ""):
        return Decimal("0")
    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError, TypeError):
        return Decimal("0")


def _money(value: Decimal) -> float:
    return float(value.quantize(Decimal("0.01")))


def _item_subtotal(item: dict) -> Decimal:
    if item.get("subtotal") is not None:
        return _number(item.get("subtotal"))
    return _number(item.get("price")) * _number(item.get("quantity"))


def build_dashboard(
    orders: list[dict],
    products: list[dict],
    stores: list[dict],
    top_n: int = 5,
) -> dict:
    """Construye las métricas ejecutivas del Módulo 6.

    Las ventas consideran todos los pedidos excepto los CANCELADOS. Esta decisión
    permite reflejar pedidos activos y completados sin contar operaciones anuladas.
    """
    top_n = max(1, min(int(top_n), 20))

    product_by_id = {p.get("productId"): p for p in products if p.get("productId")}
    store_by_id = {s.get("storeId"): s for s in stores if s.get("storeId")}

    status_counts: dict[str, int] = defaultdict(int)
    sales_by_store: dict[str, dict] = {}
    product_sales: dict[str, dict] = {}
    customer_sales: dict[str, dict] = {}

    total_sales = Decimal("0")
    sales_orders = 0
    cancelled_orders = 0

    for order in orders:
        status = str(order.get("status") or "SIN_ESTADO")
        status_counts[status] += 1

        if status == "CANCELADO":
            cancelled_orders += 1
        if status in EXCLUDED_FROM_SALES:
            continue

        sales_orders += 1
        order_total = _number(order.get("total"))
        if order_total == 0:
            order_total = sum((_item_subtotal(item) for item in order.get("items", [])), Decimal("0"))
        total_sales += order_total

        user_id = str(order.get("userId") or "UNKNOWN")
        customer = customer_sales.setdefault(
            user_id,
            {
                "userId": user_id,
                "email": order.get("customerEmail") or "",
                "orderCount": 0,
                "totalSpent": Decimal("0"),
            },
        )
        customer["orderCount"] += 1
        customer["totalSpent"] += order_total
        if not customer["email"] and order.get("customerEmail"):
            customer["email"] = order.get("customerEmail")

        stores_in_order: set[str] = set()
        for item in order.get("items", []):
            product_id = str(item.get("productId") or "UNKNOWN")
            product = product_by_id.get(product_id, {})
            quantity = int(_number(item.get("quantity")))
            subtotal = _item_subtotal(item)

            product_metric = product_sales.setdefault(
                product_id,
                {
                    "productId": product_id,
                    "code": item.get("code") or product.get("code") or "",
                    "name": item.get("name") or product.get("name") or "Producto no identificado",
                    "quantitySold": 0,
                    "revenue": Decimal("0"),
                },
            )
            product_metric["quantitySold"] += quantity
            product_metric["revenue"] += subtotal

            store_id = item.get("storeId") or product.get("storeId") or UNKNOWN_STORE_ID
            store = store_by_id.get(store_id, {})
            store_metric = sales_by_store.setdefault(
                store_id,
                {
                    "storeId": store_id,
                    "storeName": store.get("name") or UNKNOWN_STORE_NAME,
                    "totalSales": Decimal("0"),
                    "itemsSold": 0,
                    "orderIds": set(),
                },
            )
            store_metric["totalSales"] += subtotal
            store_metric["itemsSold"] += quantity
            stores_in_order.add(store_id)

        order_id = order.get("orderId")
        for store_id in stores_in_order:
            if order_id:
                sales_by_store[store_id]["orderIds"].add(order_id)

    sales_by_store_result = []
    for item in sales_by_store.values():
        sales_by_store_result.append(
            {
                "storeId": item["storeId"],
                "storeName": item["storeName"],
                "totalSales": _money(item["totalSales"]),
                "itemsSold": item["itemsSold"],
                "orderCount": len(item["orderIds"]),
            }
        )
    sales_by_store_result.sort(key=lambda x: (-x["totalSales"], x["storeName"]))

    top_products_result = [
        {
            **{k: v for k, v in item.items() if k != "revenue"},
            "revenue": _money(item["revenue"]),
        }
        for item in product_sales.values()
    ]
    top_products_result.sort(key=lambda x: (-x["quantitySold"], -x["revenue"], x["name"]))

    top_customers_result = [
        {
            **{k: v for k, v in item.items() if k != "totalSpent"},
            "totalSpent": _money(item["totalSpent"]),
        }
        for item in customer_sales.values()
    ]
    top_customers_result.sort(key=lambda x: (-x["totalSpent"], -x["orderCount"], x["userId"]))

    out_of_stock = []
    for product in products:
        stock = int(_number(product.get("stock")))
        if stock > 0 or product.get("status") == "INACTIVE":
            continue
        store_id = product.get("storeId") or UNKNOWN_STORE_ID
        store = store_by_id.get(store_id, {})
        out_of_stock.append(
            {
                "productId": product.get("productId"),
                "code": product.get("code") or "",
                "name": product.get("name") or "",
                "stock": stock,
                "storeId": store_id,
                "storeName": store.get("name") or UNKNOWN_STORE_NAME,
            }
        )
    out_of_stock.sort(key=lambda x: (x["storeName"], x["name"]))

    status_order = KNOWN_STATUSES + sorted(set(status_counts) - set(KNOWN_STATUSES))
    orders_by_status = [
        {"status": status, "count": status_counts.get(status, 0)} for status in status_order
    ]

    return {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "salesDefinition": "Pedidos en cualquier estado excepto CANCELADO",
        "summary": {
            "totalSales": _money(total_sales),
            "totalOrders": len(orders),
            "salesOrders": sales_orders,
            "cancelledOrders": cancelled_orders,
            "outOfStockProducts": len(out_of_stock),
        },
        "salesByStore": sales_by_store_result,
        "topSellingProducts": top_products_result[:top_n],
        "outOfStockProducts": out_of_stock,
        "topCustomers": top_customers_result[:top_n],
        "ordersByStatus": orders_by_status,
    }
