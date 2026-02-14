from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_
from fastapi import HTTPException
from typing import Optional
import math

from app.models.task import Task, TaskStatus
from app.schemas.task import TaskCreate, TaskUpdate, TaskListResponse, TaskFilter
from app.core.redis import CacheService
from app.core.config import settings


class TaskService:

    def __init__(self, db: AsyncSession, cache: CacheService):
        self.db = db
        self.cache = cache

    def _cache_key(self, user_id: int, task_id: int) -> str:
        return CacheService.make_key("task", str(user_id), str(task_id))

    def _list_cache_key(self, user_id: int, page: int, page_size: int) -> str:
        return CacheService.make_key("tasks", str(user_id), f"p{page}", f"s{page_size}")

    async def get_by_id(self, task_id: int, user_id: int) -> Task:
        # Try cache first
        cached = await self.cache.get(self._cache_key(user_id, task_id))
        if cached:
            return cached

        result = await self.db.execute(
            select(Task).where(
                and_(Task.id == task_id, Task.owner_id == user_id)
            )
        )
        task = result.scalar_one_or_none()
        if not task:
            raise HTTPException(status_code=404, detail="Task not found")

        # Store in cache
        await self.cache.set(self._cache_key(user_id, task_id), task.__dict__)
        return task

    async def get_all(
        self,
        user_id: int,
        filters: TaskFilter,
        page: int = 1,
        page_size: int = settings.DEFAULT_PAGE_SIZE,
    ) -> TaskListResponse:
        page_size = min(page_size, settings.MAX_PAGE_SIZE)
        offset = (page - 1) * page_size

        # Build query
        query = select(Task).where(Task.owner_id == user_id)

        if filters.status:
            query = query.where(Task.status == filters.status)
        if filters.priority:
            query = query.where(Task.priority == filters.priority)
        if filters.is_completed is not None:
            query = query.where(Task.is_completed == filters.is_completed)
        if filters.search:
            query = query.where(Task.title.ilike(f"%{filters.search}%"))

        # Count total
        count_result = await self.db.execute(
            select(func.count()).select_from(query.subquery())
        )
        total = count_result.scalar()

        # Fetch page
        result = await self.db.execute(
            query.order_by(Task.created_at.desc()).offset(offset).limit(page_size)
        )
        tasks = result.scalars().all()

        return TaskListResponse(
            items=tasks,
            total=total,
            page=page,
            page_size=page_size,
            pages=math.ceil(total / page_size) if total else 0,
        )

    async def create(self, user_id: int, data: TaskCreate) -> Task:
        task = Task(**data.model_dump(), owner_id=user_id)
        self.db.add(task)
        await self.db.flush()
        await self.db.refresh(task)

        # Invalidate list cache for this user
        await self.cache.delete_pattern(f"tasks:{user_id}:*")
        return task

    async def update(self, task_id: int, user_id: int, data: TaskUpdate) -> Task:
        task = await self.get_by_id(task_id, user_id)
        if not isinstance(task, Task):
            raise HTTPException(status_code=404, detail="Task not found")

        update_data = data.model_dump(exclude_unset=True)
        for field, value in update_data.items():
            setattr(task, field, value)

        # Auto-set status when completed
        if update_data.get("is_completed"):
            task.status = TaskStatus.DONE

        await self.db.flush()
        await self.db.refresh(task)

        # Invalidate caches
        await self.cache.delete(self._cache_key(user_id, task_id))
        await self.cache.delete_pattern(f"tasks:{user_id}:*")
        return task

    async def delete(self, task_id: int, user_id: int):
        task = await self.get_by_id(task_id, user_id)
        if not isinstance(task, Task):
            raise HTTPException(status_code=404, detail="Task not found")

        await self.db.delete(task)
        await self.db.flush()

        # Invalidate caches
        await self.cache.delete(self._cache_key(user_id, task_id))
        await self.cache.delete_pattern(f"tasks:{user_id}:*")
