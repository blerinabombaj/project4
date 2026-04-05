from fastapi import FastAPI

app = FastAPI(title="User Service")

USERS = {
    1: {"id": 1, "name": "Alice", "email": "alice@example.com"},
    2: {"id": 2, "name": "Bob", "email": "bob@example.com"},
}


@app.get("/health")
def health():
    return {"status": "ok", "service": "user-service"}


@app.get("/users/{user_id}")
def get_user(user_id: int):
    return USERS.get(user_id, {"error": "not found"})
