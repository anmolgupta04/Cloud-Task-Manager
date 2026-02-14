import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession

from app.main import app
from app.core.database import Base, get_db
from app.core.redis import get_redis, CacheService

# Test database
TEST_DATABASE_URL = "sqlite+aiosqlite:///./test.db"

engine_test = create_async_engine(TEST_DATABASE_URL, echo=False)
TestingSessionLocal = async_sessionmaker(
    engine_test, expire_on_commit=False, class_=AsyncSession
)


class MockRedis:
    """In-memory mock for Redis."""
    def __init__(self):
        self._store = {}

    async def get(self, key):
        return self._store.get(key)

    async def setex(self, key, ttl, value):
        self._store[key] = value

    async def delete(self, *keys):
        for k in keys:
            self._store.pop(k, None)

    async def keys(self, pattern):
        import fnmatch
        return [k for k in self._store if fnmatch.fnmatch(k, pattern)]


mock_redis = MockRedis()


async def override_get_db():
    async with TestingSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


async def override_get_redis():
    return mock_redis


app.dependency_overrides[get_db] = override_get_db
app.dependency_overrides[get_redis] = override_get_redis


@pytest_asyncio.fixture(scope="session", autouse=True)
async def setup_database():
    async with engine_test.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with engine_test.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)


@pytest_asyncio.fixture
async def client():
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as ac:
        yield ac


@pytest_asyncio.fixture
async def auth_headers(client: AsyncClient):
    """Register + login, return auth headers."""
    await client.post("/api/v1/auth/register", json={
        "email": "test@example.com",
        "username": "testuser",
        "password": "TestPass123!",
        "full_name": "Test User",
    })
    resp = await client.post("/api/v1/auth/login", json={
        "email": "test@example.com",
        "password": "TestPass123!",
    })
    token = resp.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


# ── AUTH TESTS ──────────────────────────────────────────────

class TestAuth:

    @pytest.mark.asyncio
    async def test_register_success(self, client):
        resp = await client.post("/api/v1/auth/register", json={
            "email": "new@example.com",
            "username": "newuser",
            "password": "Password123!",
        })
        assert resp.status_code == 201
        data = resp.json()
        assert data["email"] == "new@example.com"
        assert "hashed_password" not in data

    @pytest.mark.asyncio
    async def test_register_duplicate_email(self, client):
        payload = {"email": "dup@example.com", "username": "dup1", "password": "Pass123!"}
        await client.post("/api/v1/auth/register", json=payload)
        payload["username"] = "dup2"
        resp = await client.post("/api/v1/auth/register", json=payload)
        assert resp.status_code == 400

    @pytest.mark.asyncio
    async def test_login_success(self, client):
        await client.post("/api/v1/auth/register", json={
            "email": "login@example.com",
            "username": "loginuser",
            "password": "Pass123!",
        })
        resp = await client.post("/api/v1/auth/login", json={
            "email": "login@example.com",
            "password": "Pass123!",
        })
        assert resp.status_code == 200
        assert "access_token" in resp.json()
        assert "refresh_token" in resp.json()

    @pytest.mark.asyncio
    async def test_login_wrong_password(self, client):
        resp = await client.post("/api/v1/auth/login", json={
            "email": "login@example.com",
            "password": "WrongPassword!",
        })
        assert resp.status_code == 401


# ── TASK TESTS ──────────────────────────────────────────────

class TestTasks:

    @pytest.mark.asyncio
    async def test_create_task(self, client, auth_headers):
        resp = await client.post("/api/v1/tasks/", headers=auth_headers, json={
            "title": "Write unit tests",
            "description": "Cover all API endpoints",
            "priority": "high",
        })
        assert resp.status_code == 201
        data = resp.json()
        assert data["title"] == "Write unit tests"
        assert data["status"] == "todo"

    @pytest.mark.asyncio
    async def test_list_tasks(self, client, auth_headers):
        resp = await client.get("/api/v1/tasks/", headers=auth_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert "items" in data
        assert "total" in data

    @pytest.mark.asyncio
    async def test_update_task(self, client, auth_headers):
        create_resp = await client.post("/api/v1/tasks/", headers=auth_headers, json={
            "title": "Task to update"
        })
        task_id = create_resp.json()["id"]
        resp = await client.patch(
            f"/api/v1/tasks/{task_id}",
            headers=auth_headers,
            json={"status": "in_progress"},
        )
        assert resp.status_code == 200
        assert resp.json()["status"] == "in_progress"

    @pytest.mark.asyncio
    async def test_delete_task(self, client, auth_headers):
        create_resp = await client.post("/api/v1/tasks/", headers=auth_headers, json={
            "title": "Task to delete"
        })
        task_id = create_resp.json()["id"]
        resp = await client.delete(f"/api/v1/tasks/{task_id}", headers=auth_headers)
        assert resp.status_code == 204

    @pytest.mark.asyncio
    async def test_unauthorized_access(self, client):
        resp = await client.get("/api/v1/tasks/")
        assert resp.status_code == 401
