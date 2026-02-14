import redis.asyncio as aioredis
import json
from typing import Any, Optional
from app.core.config import settings

redis_client: Optional[aioredis.Redis] = None


async def init_redis():
    """Initialize Redis connection pool."""
    global redis_client
    redis_client = aioredis.from_url(
        settings.REDIS_URL,
        encoding="utf-8",
        decode_responses=True,
        max_connections=20,
    )


async def close_redis():
    """Close Redis connection pool."""
    global redis_client
    if redis_client:
        await redis_client.close()


async def get_redis() -> aioredis.Redis:
    """Dependency: returns Redis client."""
    return redis_client


class CacheService:
    """Helper class for caching operations."""

    def __init__(self, client: aioredis.Redis):
        self.client = client

    async def get(self, key: str) -> Optional[Any]:
        value = await self.client.get(key)
        if value:
            return json.loads(value)
        return None

    async def set(self, key: str, value: Any, ttl: int = settings.CACHE_TTL):
        await self.client.setex(key, ttl, json.dumps(value, default=str))

    async def delete(self, key: str):
        await self.client.delete(key)

    async def delete_pattern(self, pattern: str):
        keys = await self.client.keys(pattern)
        if keys:
            await self.client.delete(*keys)

    @staticmethod
    def make_key(*parts: str) -> str:
        return ":".join(parts)
