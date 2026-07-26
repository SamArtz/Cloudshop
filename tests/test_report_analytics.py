import sys
import unittest
from pathlib import Path

REPORT_DIR = Path(__file__).resolve().parents[1] / "src" / "report_service"
sys.path.insert(0, str(REPORT_DIR))

from analytics import build_dashboard


class ReportAnalyticsTests(unittest.TestCase):
    def setUp(self):
        self.stores = [
            {"storeId": "s1", "name": "Tienda Uno"},
            {"storeId": "s2", "name": "Tienda Dos"},
        ]
        self.products = [
            {"productId": "p1", "code": "P-1", "name": "Producto 1", "storeId": "s1", "stock": 0, "status": "ACTIVE"},
            {"productId": "p2", "code": "P-2", "name": "Producto 2", "storeId": "s2", "stock": 8, "status": "ACTIVE"},
        ]
        self.orders = [
            {
                "orderId": "o1",
                "userId": "u1",
                "customerEmail": "u1@test.com",
                "status": "ENTREGADO",
                "total": 40,
                "items": [
                    {"productId": "p1", "name": "Producto 1", "quantity": 2, "price": 10, "subtotal": 20},
                    {"productId": "p2", "name": "Producto 2", "quantity": 1, "price": 20, "subtotal": 20},
                ],
            },
            {
                "orderId": "o2",
                "userId": "u1",
                "customerEmail": "u1@test.com",
                "status": "PENDIENTE",
                "total": 10,
                "items": [
                    {"productId": "p1", "name": "Producto 1", "quantity": 1, "price": 10, "subtotal": 10},
                ],
            },
            {
                "orderId": "o3",
                "userId": "u2",
                "customerEmail": "u2@test.com",
                "status": "CANCELADO",
                "total": 999,
                "items": [
                    {"productId": "p2", "name": "Producto 2", "quantity": 50, "price": 20, "subtotal": 1000},
                ],
            },
        ]

    def test_dashboard_contains_all_required_sections(self):
        dashboard = build_dashboard(self.orders, self.products, self.stores, top_n=5)

        self.assertEqual(dashboard["summary"]["totalSales"], 50.0)
        self.assertEqual(dashboard["summary"]["totalOrders"], 3)
        self.assertEqual(dashboard["summary"]["cancelledOrders"], 1)
        self.assertEqual(dashboard["topSellingProducts"][0]["productId"], "p1")
        self.assertEqual(dashboard["topSellingProducts"][0]["quantitySold"], 3)
        self.assertEqual(dashboard["topCustomers"][0]["userId"], "u1")
        self.assertEqual(dashboard["outOfStockProducts"][0]["productId"], "p1")

        counts = {item["status"]: item["count"] for item in dashboard["ordersByStatus"]}
        self.assertEqual(counts["ENTREGADO"], 1)
        self.assertEqual(counts["PENDIENTE"], 1)
        self.assertEqual(counts["CANCELADO"], 1)

    def test_cancelled_orders_are_not_counted_as_sales(self):
        dashboard = build_dashboard(self.orders, self.products, self.stores)
        self.assertEqual(dashboard["summary"]["salesOrders"], 2)
        self.assertEqual(dashboard["summary"]["totalSales"], 50.0)


if __name__ == "__main__":
    unittest.main()
