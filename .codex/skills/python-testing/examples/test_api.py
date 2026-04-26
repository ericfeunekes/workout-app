"""
Example FastAPI tests demonstrating API testing patterns.

These examples show:
- Behavior testing with TestClient
- Request validation
- Error responses
- Authentication
"""

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from pydantic import BaseModel, EmailStr

# ============================================================================
# Example FastAPI Application (minimal for demonstration)
# ============================================================================

app = FastAPI()


class UserCreate(BaseModel):
    name: str
    email: EmailStr


class User(BaseModel):
    id: str
    name: str
    email: str


# Fake database for demonstration
fake_db = {}


@app.post("/users", status_code=201)
async def create_user(user: UserCreate):
    """Create a new user."""
    user_id = f"user-{len(fake_db) + 1}"
    user_data = User(id=user_id, name=user.name, email=user.email)
    fake_db[user_id] = user_data
    return user_data


@app.get("/users/{user_id}")
async def get_user(user_id: str):
    """Get user by ID."""
    if user_id not in fake_db:
        raise HTTPException(status_code=404, detail="User not found")
    return fake_db[user_id]


# ============================================================================
# Fixtures
# ============================================================================


@pytest.fixture
def client():
    """Provide TestClient for API testing."""
    # Clear fake database before each test
    fake_db.clear()

    with TestClient(app) as client:
        yield client


# ============================================================================
# Behavior Tests
# ============================================================================


@pytest.mark.behavior
@pytest.mark.api
def test_create_user_endpoint(client):
    """Test user creation through API."""
    response = client.post("/users", json={"name": "Alice", "email": "alice@example.com"})

    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Alice"
    assert data["email"] == "alice@example.com"
    assert "id" in data


@pytest.mark.behavior
@pytest.mark.api
def test_get_user_endpoint(client):
    """Test user retrieval through API."""
    # Create user first
    create_response = client.post("/users", json={"name": "Alice", "email": "alice@example.com"})
    user_id = create_response.json()["id"]

    # Get user
    response = client.get(f"/users/{user_id}")

    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "Alice"
    assert data["email"] == "alice@example.com"


# ============================================================================
# Validation Tests
# ============================================================================


@pytest.mark.behavior
@pytest.mark.api
def test_create_user_rejects_invalid_email(client):
    """Test API validates email format."""
    response = client.post("/users", json={"name": "Alice", "email": "not-an-email"})

    assert response.status_code == 422
    detail = response.json()["detail"]
    assert any("email" in str(error["loc"]) for error in detail)


@pytest.mark.behavior
@pytest.mark.api
def test_create_user_requires_name(client):
    """Test API validates required fields."""
    response = client.post("/users", json={"email": "alice@example.com"})

    assert response.status_code == 422
    detail = response.json()["detail"]
    assert any("name" in str(error["loc"]) for error in detail)


# ============================================================================
# Error Response Tests
# ============================================================================


@pytest.mark.behavior
@pytest.mark.api
def test_get_user_returns_404_when_not_found(client):
    """Test API returns proper 404 response."""
    response = client.get("/users/nonexistent-id")

    assert response.status_code == 404
    assert response.json()["detail"] == "User not found"


# ============================================================================
# Priority Markers
# ============================================================================


@pytest.mark.behavior
@pytest.mark.api
@pytest.mark.p0
def test_critical_user_creation_workflow(client):
    """Test critical user creation path (must always pass)."""
    # Create user
    response = client.post("/users", json={"name": "Alice", "email": "alice@example.com"})

    assert response.status_code == 201
    user_id = response.json()["id"]

    # Verify user exists
    get_response = client.get(f"/users/{user_id}")
    assert get_response.status_code == 200
    assert get_response.json()["email"] == "alice@example.com"
