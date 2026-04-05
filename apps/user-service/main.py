from fastapi import FastAPI, HTTPException

app = FastAPI(title="User Service")

# Chaos flag — flip this to True to simulate 500 errors
FORCE_ERROR = True

USERS = {
    1: {"id": 1, "name": "Alice", "email": "alice@example.com"},
    2: {"id": 2, "name": "Bob", "email": "bob@example.com"},
}

@app.get("/health")
def health():
    # Always returns 200 — this is the shallow health check blindspot
    return {"status": "ok", "service": "user-service"}

@app.get("/users/{user_id}")
def get_user(user_id: int):
    if FORCE_ERROR:
        raise HTTPException(status_code=500, detail="simulated failure")
    return USERS.get(user_id, {"error": "not found"})