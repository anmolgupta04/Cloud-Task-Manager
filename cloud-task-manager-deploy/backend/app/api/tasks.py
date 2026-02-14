from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional

from app.core.database import get_db
from app.core.redis import get_redis, CacheService
from app.core.security import get_current_user_id
from app.schemas.task import (
    TaskCreate,
    TaskUpdate,
    TaskResponse,
    TaskListResponse,
    TaskFilter,
)
from app.models.task import TaskStatus, TaskPriority
from app.services.task_service import TaskService

router = APIRouter()


def get_task_service(
    db: AsyncSession = Depends(get_db),
    redis=Depends(get_redis),
) -> TaskService:
    return TaskService(db, CacheService(redis))


@router.get("/", response_model=TaskListResponse)
async def list_tasks(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    status: Optional[TaskStatus] = None,
    priority: Optional[TaskPriority] = None,
    is_completed: Optional[bool] = None,
    search: Optional[str] = Query(None, max_length=100),
    current_user_id: int = Depends(get_current_user_id),
    service: TaskService = Depends(get_task_service),
):
    """List all tasks for the current user with optional filters."""
    filters = TaskFilter(
        status=status,
        priority=priority,
        is_completed=is_completed,
        search=search,
    )
    return await service.get_all(current_user_id, filters, page, page_size)


@router.post("/", response_model=TaskResponse, status_code=201)
async def create_task(
    data: TaskCreate,
    current_user_id: int = Depends(get_current_user_id),
    service: TaskService = Depends(get_task_service),
):
    """Create a new task."""
    return await service.create(current_user_id, data)


@router.get("/{task_id}", response_model=TaskResponse)
async def get_task(
    task_id: int,
    current_user_id: int = Depends(get_current_user_id),
    service: TaskService = Depends(get_task_service),
):
    """Get a single task by ID."""
    return await service.get_by_id(task_id, current_user_id)


@router.patch("/{task_id}", response_model=TaskResponse)
async def update_task(
    task_id: int,
    data: TaskUpdate,
    current_user_id: int = Depends(get_current_user_id),
    service: TaskService = Depends(get_task_service),
):
    """Update an existing task."""
    return await service.update(task_id, current_user_id, data)


@router.delete("/{task_id}", status_code=204)
async def delete_task(
    task_id: int,
    current_user_id: int = Depends(get_current_user_id),
    service: TaskService = Depends(get_task_service),
):
    """Delete a task by ID."""
    await service.delete(task_id, current_user_id)
