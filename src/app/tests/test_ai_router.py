# src/app/tests/test_ai_router.py
"""
Tests for AI System Controller API endpoints
"""

import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch, AsyncMock

from src.app.main import app
from src.app.ai.controller import TaskType


@pytest.fixture
def client():
    """Create test client"""
    # Mock database and redis for testing
    mock_db = AsyncMock()

    def override_get_db():
        return mock_db

    mock_redis = AsyncMock()
    mock_redis.ping = AsyncMock(return_value=True)

    def override_get_redis():
        return mock_redis

    app.dependency_overrides = {}
    from src.app.db.session import get_db
    from src.app.core.redis_client import get_redis
    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_redis] = override_get_redis

    client = TestClient(app)

    # Start the controller for this test session
    from src.app.ai.controller import controller
    # Reset controller state
    controller.tasks.clear()
    controller.results.clear()
    controller.agents.clear()
    controller.input_observers.clear()
    controller.output_collectors.clear()
    controller._running = False

    # Initialize agents without starting the monitor loop
    import asyncio
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    try:
        loop.run_until_complete(controller._initialize_agents())
    finally:
        loop.close()

    yield client

    # Clean up
    app.dependency_overrides = {}


class TestAIRouter:
    """Test cases for AI API endpoints"""

    @pytest.mark.asyncio
    async def test_submit_task(self, client):
        """Test task submission endpoint"""
        task_data = {
            "type": "reverse_engineer",
            "content": "Analyze this code",
            "metadata": {"source": "test"},
            "priority": 5
        }

        response = client.post("/api/v1/ai/tasks", json=task_data)

        assert response.status_code == 200
        task_id = response.json()
        assert isinstance(task_id, str)
        assert "reverse_engineer" in task_id

    @pytest.mark.asyncio
    async def test_get_task_status_not_found(self, client):
        """Test getting status of non-existent task"""
        response = client.get("/api/v1/ai/tasks/nonexistent")

        assert response.status_code == 404
        assert response.json()["detail"] == "Task not found"

    @pytest.mark.asyncio
    async def test_get_task_status(self, client):
        """Test getting task status"""
        # First submit a task
        task_data = {
            "type": "code_generation",
            "content": "Generate a function",
            "metadata": {},
            "priority": 1
        }

        submit_response = client.post("/api/v1/ai/tasks", json=task_data)
        task_id = submit_response.json()

        # Get status
        status_response = client.get(f"/api/v1/ai/tasks/{task_id}")
        assert status_response.status_code == 200

        status_data = status_response.json()
        assert "task" in status_data
        assert "result" in status_data
        assert status_data["task"]["id"] == task_id
        assert status_data["task"]["type"] == "code_generation"

    @pytest.mark.asyncio
    async def test_get_controller_stats(self, client):
        """Test getting controller statistics"""
        response = client.get("/api/v1/ai/stats")

        assert response.status_code == 200
        stats = response.json()

        required_fields = ["total_tasks", "completed_tasks", "pending_tasks", "failed_tasks", "active_agents"]
        for field in required_fields:
            assert field in stats
            assert isinstance(stats[field], int)
            assert stats[field] >= 0

    @pytest.mark.asyncio
    async def test_list_agents(self, client):
        """Test listing available agents"""
        response = client.get("/api/v1/ai/agents")

        assert response.status_code == 200
        data = response.json()

        assert "agents" in data
        agents = data["agents"]

        # Should have all agent types
        expected_agents = ["reverse_engineer_ai", "security_ai", "coder_ai", "tester_ai", "ops_ai"]
        for agent in expected_agents:
            assert agent in agents
            assert "status" in agents[agent]
            assert "last_used" in agents[agent]
            assert "success_rate" in agents[agent]
            assert "queue_size" in agents[agent]

    @pytest.mark.asyncio
    async def test_invalid_task_type(self, client):
        """Test submitting task with invalid type"""
        task_data = {
            "type": "invalid_type",
            "content": "Test content",
            "metadata": {},
            "priority": 1
        }

        response = client.post("/api/v1/ai/tasks", json=task_data)

        # Should fail validation
        assert response.status_code == 422  # Validation error

    @pytest.mark.asyncio
    async def test_task_priority_bounds(self, client):
        """Test task priority validation"""
        # Test minimum priority
        task_data = {
            "type": "testing",
            "content": "Test content",
            "metadata": {},
            "priority": 1
        }

        response = client.post("/api/v1/ai/tasks", json=task_data)
        assert response.status_code == 200

        # Test maximum priority
        task_data["priority"] = 10
        response = client.post("/api/v1/ai/tasks", json=task_data)
        assert response.status_code == 200

        # Test invalid priority (too low)
        task_data["priority"] = 0
        response = client.post("/api/v1/ai/tasks", json=task_data)
        assert response.status_code == 422

        # Test invalid priority (too high)
        task_data["priority"] = 11
        response = client.post("/api/v1/ai/tasks", json=task_data)
        assert response.status_code == 422