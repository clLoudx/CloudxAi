# src/app/tests/test_controller.py
"""
Tests for AI System Controller
"""

import pytest
import asyncio
from unittest.mock import AsyncMock, MagicMock, patch
from src.app.ai.controller import (
    AISystemController,
    Task,
    TaskResult,
    TaskType,
    AgentType
)


class TestAISystemController:
    """Test cases for AI System Controller"""

    @pytest.fixture
    def controller(self):
        """Create a fresh controller instance"""
        ctrl = AISystemController()
        return ctrl

    @pytest.mark.asyncio
    async def test_controller_initialization(self, controller):
        """Test controller initializes correctly"""
        assert len(controller.agents) == 0
        assert len(controller.tasks) == 0
        assert len(controller.results) == 0
        assert not controller._running

    @pytest.mark.asyncio
    async def test_controller_start_stop(self, controller):
        """Test controller start and stop"""
        await controller.start()
        assert controller._running
        assert len(controller.agents) == 5  # All AgentType enum values

        await controller.stop()
        assert not controller._running

    @pytest.mark.asyncio
    async def test_task_submission(self, controller):
        """Test task submission and observation"""
        observer_mock = AsyncMock()
        controller.register_input_observer(observer_mock)

        task = Task(
            id="test-123",
            type=TaskType.REVERSE_ENGINEER,
            content="Test content",
            metadata={}
        )

        task_id = await controller.submit_task(task)

        assert task_id == "test-123"
        assert task_id in controller.tasks
        observer_mock.assert_called_once_with(task)

    @pytest.mark.asyncio
    async def test_agent_assignment(self, controller):
        """Test agent assignment logic"""
        await controller.start()  # Initialize agents

        # Test direct routing
        task = Task(
            id="test-1",
            type=TaskType.REVERSE_ENGINEER,
            content="Test",
            metadata={}
        )

        agent = await controller._assign_agent(task)
        assert agent == AgentType.REVERSE_ENGINEER_AI

        # Test security task
        task.type = TaskType.SECURITY_ANALYSIS
        agent = await controller._assign_agent(task)
        assert agent == AgentType.SECURITY_AI

    @pytest.mark.asyncio
    async def test_task_processing_simulation(self, controller):
        """Test simulated task processing"""
        await controller.start()

        collector_mock = AsyncMock()
        controller.register_output_collector(collector_mock)

        task = Task(
            id="test-process",
            type=TaskType.CODE_GENERATION,
            content="Generate code",
            metadata={}
        )

        # Mock Ollama client
        with patch('src.app.ai.ollama_client.ollama_client') as mock_client:
            mock_response = MagicMock()
            mock_response.content = "Generated code here"
            mock_response.processing_time = 0.5
            mock_client.generate = AsyncMock(return_value=mock_response)

            await controller.submit_task(task)

            # Wait for processing to complete
            await asyncio.sleep(0.1)

            # Check task completed
            assert task.status == "completed"
            assert task.assigned_agent == AgentType.CODER_AI

            # Check result exists
            assert "test-process" in controller.results
            result = controller.results["test-process"]
            assert result.success
            assert result.agent_used == AgentType.CODER_AI
            assert result.output == "Generated code here"

            # Check collector was called
            collector_mock.assert_called_once()
            call_args = collector_mock.call_args[0][0]
            assert isinstance(call_args, TaskResult)
            assert call_args.task_id == "test-process"

    @pytest.mark.asyncio
    async def test_task_status_query(self, controller):
        """Test getting task status"""
        task = Task(
            id="status-test",
            type=TaskType.TESTING,
            content="Test task",
            metadata={}
        )

        # Task not found
        status = await controller.get_task_status("nonexistent")
        assert status is None

        # Task exists but no result
        controller.tasks[task.id] = task
        status = await controller.get_task_status(task.id)
        assert status["task"]["id"] == task.id
        assert status["result"] is None

        # Task with result
        result = TaskResult(
            task_id=task.id,
            success=True,
            output="Test output",
            agent_used=AgentType.TESTER_AI,
            processing_time=1.5
        )
        controller.results[task.id] = result

        status = await controller.get_task_status(task.id)
        assert status["result"]["success"] is True
        assert status["result"]["output"] == "Test output"

    @pytest.mark.asyncio
    async def test_controller_stats(self, controller):
        """Test controller statistics"""
        await controller.start()

        # Add some test tasks
        tasks = [
            Task(id="1", type=TaskType.CODE_GENERATION, content="Code", metadata={}, status="completed"),
            Task(id="2", type=TaskType.TESTING, content="Test", metadata={}, status="pending"),
            Task(id="3", type=TaskType.DEPLOYMENT, content="Deploy", metadata={}, status="failed"),
        ]

        for task in tasks:
            controller.tasks[task.id] = task

        stats = await controller.get_controller_stats()

        assert stats["total_tasks"] == 3
        assert stats["completed_tasks"] == 1
        assert stats["pending_tasks"] == 1
        assert stats["failed_tasks"] == 1
        assert stats["active_agents"] == 5  # All agents available

    @pytest.mark.asyncio
    async def test_observer_error_handling(self, controller):
        """Test error handling in observers"""
        # Observer that raises exception
        async def failing_observer(task):
            raise ValueError("Observer failed")

        controller.register_input_observer(failing_observer)
        controller.register_input_observer(AsyncMock())  # Working observer

        task = Task(id="error-test", type=TaskType.GENERAL_QUERY, content="Test", metadata={})

        # Should not raise exception, should log warning
        await controller.submit_task(task)

        # Check task was still submitted
        assert task.id in controller.tasks

    @pytest.mark.asyncio
    async def test_collector_error_handling(self, controller):
        """Test error handling in collectors"""
        await controller.start()

        # Collector that raises exception
        async def failing_collector(result):
            raise RuntimeError("Collector failed")

        controller.register_output_collector(failing_collector)
        controller.register_output_collector(AsyncMock())  # Working collector

        task = Task(id="collector-error", type=TaskType.CODE_GENERATION, content="Test", metadata={})

        # Mock Ollama client
        with patch('src.app.ai.ollama_client.ollama_client') as mock_client:
            mock_response = MagicMock()
            mock_response.content = "Test output"
            mock_response.processing_time = 0.1
            mock_client.generate = AsyncMock(return_value=mock_response)

            await controller.submit_task(task)

            # Wait for processing
            await asyncio.sleep(0.1)

            # Task should still complete despite collector error
            assert task.status == "completed"