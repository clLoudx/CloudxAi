# src/app/ai/__init__.py
"""
AI Core Engine Module - PHASE 5

Contains AI System Controller and related components.
"""

from .controller import AISystemController, controller, Task, TaskResult, TaskType, AgentType
from .ollama_client import OllamaClient, OllamaConfig, InferenceRequest, InferenceResponse, ollama_client

__all__ = [
    "AISystemController",
    "controller",
    "Task",
    "TaskResult",
    "TaskType",
    "AgentType",
    "OllamaClient",
    "OllamaConfig",
    "InferenceRequest",
    "InferenceResponse",
    "ollama_client"
]