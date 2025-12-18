# src/app/ai/controller.py
"""
AI System Controller - PHASE 5 Core Engine

Observes inputs/outputs, routes tasks, assigns agents.
Separate from main AI core (Ollama inference).
"""

import asyncio
import logging
from typing import Dict, List, Optional, Any, Callable
from dataclasses import dataclass
from enum import Enum
import structlog

logger = structlog.get_logger("ai.controller")


class TaskType(Enum):
    """Types of tasks the controller can route"""
    REVERSE_ENGINEER = "reverse_engineer"
    SECURITY_ANALYSIS = "security_analysis"
    CODE_GENERATION = "code_generation"
    TESTING = "testing"
    DEPLOYMENT = "deployment"
    GENERAL_QUERY = "general_query"


class AgentType(Enum):
    """Types of helper agents available"""
    REVERSE_ENGINEER_AI = "reverse_engineer_ai"
    SECURITY_AI = "security_ai"
    CODER_AI = "coder_ai"
    TESTER_AI = "tester_ai"
    OPS_AI = "ops_ai"


@dataclass
class Task:
    """Represents a task to be processed"""
    id: str
    type: TaskType
    content: str
    metadata: Dict[str, Any]
    priority: int = 1
    assigned_agent: Optional[AgentType] = None
    status: str = "pending"


@dataclass
class TaskResult:
    """Result from processing a task"""
    task_id: str
    success: bool
    output: Any
    agent_used: AgentType
    processing_time: float
    error: Optional[str] = None


class AISystemController:
    """
    AI System Controller - orchestrates AI operations

    Responsibilities:
    - Observe and collect inputs from various sources
    - Route tasks to appropriate helper agents
    - Monitor task execution and collect feedback
    - Maintain agent registry and health
    """

    def __init__(self):
        self.tasks: Dict[str, Task] = {}
        self.results: Dict[str, TaskResult] = {}
        self.agents: Dict[AgentType, Dict] = {}
        self.input_observers: List[Callable] = []
        self.output_collectors: List[Callable] = []
        self._running = False

    async def start(self):
        """Start the controller"""
        logger.info("Starting AI System Controller")
        self._running = True

        # Initialize agent registry
        await self._initialize_agents()

        # Start background monitoring
        asyncio.create_task(self._monitor_loop())

        logger.info("AI System Controller started")

    async def stop(self):
        """Stop the controller"""
        logger.info("Stopping AI System Controller")
        self._running = False
        logger.info("AI System Controller stopped")

    async def _initialize_agents(self):
        """Initialize the helper agent registry"""
        # TODO: Implement actual agent initialization
        # For now, register mock agents
        for agent_type in AgentType:
            self.agents[agent_type] = {
                "status": "available",
                "last_used": None,
                "success_rate": 1.0,
                "queue_size": 0
            }
        logger.info("Initialized agent registry", agent_count=len(self.agents))

    async def _monitor_loop(self):
        """Background monitoring loop"""
        while self._running:
            try:
                # Monitor agent health
                await self._check_agent_health()

                # Process pending tasks
                await self._process_pending_tasks()

                # Collect metrics
                await self._collect_metrics()

                await asyncio.sleep(5)  # Check every 5 seconds

            except Exception as e:
                logger.error("Error in monitor loop", error=str(e))
                await asyncio.sleep(10)

    async def _check_agent_health(self):
        """Check health of all registered agents"""
        # TODO: Implement actual health checks
        pass

    async def _process_pending_tasks(self):
        """Process tasks that are pending assignment"""
        pending_tasks = [t for t in self.tasks.values() if t.status == "pending"]

        for task in pending_tasks:
            agent = await self._assign_agent(task)
            if agent:
                await self._dispatch_task(task, agent)

    async def _collect_metrics(self):
        """Collect and log controller metrics"""
        # TODO: Implement metrics collection
        pass

    def register_input_observer(self, observer: Callable):
        """Register a function to observe inputs"""
        self.input_observers.append(observer)
        logger.info("Registered input observer")

    def register_output_collector(self, collector: Callable):
        """Register a function to collect outputs"""
        self.output_collectors.append(collector)
        logger.info("Registered output collector")

    async def submit_task(self, task: Task) -> str:
        """Submit a task for processing"""
        self.tasks[task.id] = task

        # Notify observers
        for observer in self.input_observers:
            try:
                await observer(task)
            except Exception as e:
                logger.warning("Input observer failed", observer=str(observer), error=str(e))

        logger.info("Task submitted", task_id=task.id, task_type=task.type.value)
        return task.id

    async def _assign_agent(self, task: Task) -> Optional[AgentType]:
        """Assign an appropriate agent for the task"""
        # Simple routing logic - can be made more sophisticated
        routing_map = {
            TaskType.REVERSE_ENGINEER: AgentType.REVERSE_ENGINEER_AI,
            TaskType.SECURITY_ANALYSIS: AgentType.SECURITY_AI,
            TaskType.CODE_GENERATION: AgentType.CODER_AI,
            TaskType.TESTING: AgentType.TESTER_AI,
            TaskType.DEPLOYMENT: AgentType.OPS_AI,
            TaskType.GENERAL_QUERY: AgentType.CODER_AI  # Default to coder
        }

        agent_type = routing_map.get(task.type)
        if agent_type and self.agents[agent_type]["status"] == "available":
            return agent_type

        # Fallback to any available agent
        for agent_type, info in self.agents.items():
            if info["status"] == "available":
                return agent_type

        return None

    async def _dispatch_task(self, task: Task, agent: AgentType):
        """Dispatch task to assigned agent"""
        task.status = "processing"
        task.assigned_agent = agent

        try:
            # For now, route inference tasks directly to Ollama
            # Later this will route to actual agent implementations
            if task.type in [TaskType.CODE_GENERATION, TaskType.GENERAL_QUERY]:
                await self._dispatch_to_ollama(task, agent)
            else:
                # For other task types, simulate processing until agents are implemented
                asyncio.create_task(self._simulate_agent_processing(task, agent))

        except Exception as e:
            logger.error("Task dispatch failed", task_id=task.id, agent=agent.value, error=str(e))
            task.status = "failed"

    async def _dispatch_to_ollama(self, task: Task, agent: AgentType):
        """Dispatch task to Ollama for inference"""
        from .ollama_client import ollama_client, InferenceRequest

        try:
            # Convert task to Ollama inference request
            messages = [
                {"role": "system", "content": f"You are a {agent.value.replace('_', ' ')} assistant."},
                {"role": "user", "content": task.content}
            ]

            request = InferenceRequest(
                messages=messages,
                model=None,  # Use default model
                temperature=0.1,  # Low temperature for consistent results
                max_tokens=1000
            )

            logger.info("Dispatching to Ollama", task_id=task.id, agent=agent.value)

            # Call Ollama
            response = await ollama_client.generate(request)

            # Create result
            result = TaskResult(
                task_id=task.id,
                success=True,
                output=response.content,
                agent_used=agent,
                processing_time=response.processing_time
            )

            self.results[task.id] = result
            task.status = "completed"

            # Notify collectors
            for collector in self.output_collectors:
                try:
                    await collector(result)
                except Exception as e:
                    logger.warning("Output collector failed", collector=str(collector), error=str(e))

            logger.info("Task completed via Ollama", task_id=task.id, agent=agent.value, processing_time=response.processing_time)

        except Exception as e:
            logger.error("Ollama dispatch failed", task_id=task.id, error=str(e))
            raise

    async def _simulate_agent_processing(self, task: Task, agent: AgentType):
        """Simulate agent processing (replace with real agent calls)"""
        try:
            # Simulate processing time
            await asyncio.sleep(2)

            # Mock result
            result = TaskResult(
                task_id=task.id,
                success=True,
                output=f"Mock output from {agent.value} for task {task.type.value}",
                agent_used=agent,
                processing_time=2.0
            )

            self.results[task.id] = result
            task.status = "completed"

            # Notify collectors
            for collector in self.output_collectors:
                try:
                    await collector(result)
                except Exception as e:
                    logger.warning("Output collector failed", collector=str(collector), error=str(e))

            logger.info("Task completed", task_id=task.id, agent=agent.value)

        except Exception as e:
            logger.error("Task processing failed", task_id=task.id, error=str(e))
            task.status = "failed"

    async def get_task_status(self, task_id: str) -> Optional[Dict]:
        """Get status of a task"""
        task = self.tasks.get(task_id)
        if not task:
            return None

        result = self.results.get(task_id)
        return {
            "task": {
                "id": task.id,
                "type": task.type.value,
                "status": task.status,
                "assigned_agent": task.assigned_agent.value if task.assigned_agent else None
            },
            "result": {
                "success": result.success,
                "output": result.output,
                "processing_time": result.processing_time,
                "error": result.error
            } if result else None
        }

    async def get_controller_stats(self) -> Dict:
        """Get controller statistics"""
        return {
            "total_tasks": len(self.tasks),
            "completed_tasks": len([t for t in self.tasks.values() if t.status == "completed"]),
            "pending_tasks": len([t for t in self.tasks.values() if t.status == "pending"]),
            "failed_tasks": len([t for t in self.tasks.values() if t.status == "failed"]),
            "active_agents": len([a for a in self.agents.values() if a["status"] == "available"])
        }


# Global controller instance
controller = AISystemController()