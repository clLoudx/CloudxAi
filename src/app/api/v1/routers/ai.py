# src/app/api/v1/routers/ai.py
"""
AI System Controller API endpoints.

Provides endpoints for interacting with the AI System Controller.
"""

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, Field
from typing import Dict, Any, Optional, List
import structlog

from ....ai.controller import controller, Task, TaskType, TaskResult
from ....ai.ollama_client import ollama_client, InferenceRequest
from ....core.logging import get_logger

logger = get_logger(__name__)
router = APIRouter()


class TaskSubmissionRequest(BaseModel):
    """Request model for task submission"""
    type: TaskType = Field(..., description="Type of task to submit")
    content: str = Field(..., description="Task content/description")
    metadata: Dict[str, Any] = Field(default_factory=dict, description="Additional task metadata")
    priority: int = Field(default=1, ge=1, le=10, description="Task priority (1-10)")


class TaskStatusResponse(BaseModel):
    """Response model for task status"""
    task: Dict[str, Any]
    result: Optional[Dict[str, Any]] = None


class ControllerStatsResponse(BaseModel):
    """Response model for controller statistics"""
    total_tasks: int
    completed_tasks: int
    pending_tasks: int
    failed_tasks: int
    active_agents: int


@router.post(
    "/tasks",
    summary="Submit Task",
    description="Submit a task to the AI System Controller for processing",
    response_model=str
)
async def submit_task(request: TaskSubmissionRequest):
    """
    Submit a task for AI processing.

    The task will be routed to the appropriate AI agent based on its type.
    """
    try:
        task = Task(
            id=f"task_{request.type.value}_{len(controller.tasks)}",  # Simple ID generation
            type=request.type,
            content=request.content,
            metadata=request.metadata,
            priority=request.priority
        )

        task_id = await controller.submit_task(task)
        logger.info("Task submitted via API", task_id=task_id, task_type=request.type.value)

        return task_id

    except Exception as e:
        logger.error("Failed to submit task", error=str(e), task_type=request.type.value)
        raise HTTPException(status_code=500, detail="Failed to submit task")


@router.get(
    "/tasks/{task_id}",
    summary="Get Task Status",
    description="Get the current status and result of a submitted task",
    response_model=TaskStatusResponse
)
async def get_task_status(task_id: str):
    """
    Get the status of a task by its ID.

    Returns task information and result if completed.
    """
    try:
        status = await controller.get_task_status(task_id)
        if status is None:
            raise HTTPException(status_code=404, detail="Task not found")

        return TaskStatusResponse(**status)

    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to get task status", error=str(e), task_id=task_id)
        raise HTTPException(status_code=500, detail="Failed to get task status")


@router.get(
    "/stats",
    summary="Controller Statistics",
    description="Get statistics about the AI System Controller",
    response_model=ControllerStatsResponse
)
async def get_controller_stats():
    """
    Get statistics about the controller's operation.

    Includes counts of tasks by status and active agents.
    """
    try:
        stats = await controller.get_controller_stats()
        return ControllerStatsResponse(**stats)

    except Exception as e:
        logger.error("Failed to get controller stats", error=str(e))
        raise HTTPException(status_code=500, detail="Failed to get controller statistics")


@router.get(
    "/agents",
    summary="List Agents",
    description="Get information about available AI agents"
)
async def list_agents():
    """
    Get information about all registered AI agents.

    Returns agent types, status, and basic metrics.
    """
    try:
        agents_info = {}
        for agent_type, info in controller.agents.items():
            agents_info[agent_type.value] = {
                "status": info["status"],
                "last_used": info["last_used"],
                "success_rate": info["success_rate"],
                "queue_size": info["queue_size"]
            }

        return {"agents": agents_info}

    except Exception as e:
        logger.error("Failed to list agents", error=str(e))
        raise HTTPException(status_code=500, detail="Failed to list agents")


class InferenceRequestModel(BaseModel):
    """Request model for AI inference"""
    messages: List[Dict[str, str]] = Field(..., description="List of messages for inference")
    model: Optional[str] = Field(None, description="Model to use for inference")
    temperature: Optional[float] = Field(None, ge=0.0, le=2.0, description="Temperature for generation")
    max_tokens: Optional[int] = Field(None, gt=0, description="Maximum tokens to generate")
    stream: bool = Field(False, description="Whether to stream the response")


class InferenceResponseModel(BaseModel):
    """Response model for AI inference"""
    content: str
    model: str
    usage: Dict[str, Any]
    finish_reason: Optional[str] = None
    processing_time: float


@router.get(
    "/ollama/health",
    summary="Ollama Health Check",
    description="Check if Ollama server is healthy and responsive"
)
async def ollama_health_check():
    """
    Health check for Ollama inference engine.

    Returns connection status and available models.
    """
    try:
        is_healthy = await ollama_client.health_check()

        if is_healthy:
            # Get available models
            models = await ollama_client.list_models()
            model_names = [model.get('name', '') for model in models]

            return {
                "status": "healthy",
                "models": model_names,
                "model_count": len(model_names)
            }
        else:
            return {
                "status": "unhealthy",
                "models": [],
                "model_count": 0
            }

    except Exception as e:
        logger.error("Ollama health check failed", error=str(e))
        raise HTTPException(status_code=503, detail="Ollama service unavailable")


@router.post(
    "/ollama/generate",
    summary="Generate AI Inference",
    description="Generate AI response using Ollama",
    response_model=InferenceResponseModel
)
async def generate_inference(request: InferenceRequestModel):
    """
    Generate AI inference using Ollama.

    Accepts messages and generation parameters.
    """
    try:
        inference_request = InferenceRequest(
            messages=request.messages,
            model=request.model,
            temperature=request.temperature,
            max_tokens=request.max_tokens,
            stream=False  # API doesn't support streaming yet
        )

        response = await ollama_client.generate(inference_request)

        return InferenceResponseModel(
            content=response.content,
            model=response.model,
            usage=response.usage,
            finish_reason=response.finish_reason,
            processing_time=response.processing_time
        )

    except Exception as e:
        logger.error("Inference generation failed", error=str(e))
        raise HTTPException(status_code=500, detail="Inference generation failed")


@router.get(
    "/ollama/models",
    summary="List Ollama Models",
    description="Get list of available Ollama models"
)
async def list_ollama_models():
    """
    List all available models in Ollama.

    Returns detailed model information.
    """
    try:
        models = await ollama_client.list_models()
        return {"models": models, "count": len(models)}

    except Exception as e:
        logger.error("Failed to list Ollama models", error=str(e))
        raise HTTPException(status_code=500, detail="Failed to list models")