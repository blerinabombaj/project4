from fastapi import FastAPI

app = FastAPI(title="Order Service")

ORDERS = {
    1: {"id": 1, "item": "laptop", "status": "shipped"},
    2: {"id": 2, "item": "mouse", "status": "pending"},
}


@app.get("/health")
def health():
    return {"status": "ok", "service": "order-service"}


@app.get("/orders/{order_id}")
def get_order(order_id: int):
    return ORDERS.get(order_id, {"error": "not found"})
