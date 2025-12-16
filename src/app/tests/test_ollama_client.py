# src/app/tests/test_ollama_client.py
"""
Tests for Ollama Client
"""

import pytest
import asyncio
from unittest.mock import AsyncMock, patch, MagicMock
from src.app.ai.ollama_client import (
    OllamaClient,
    OllamaConfig,
    InferenceRequest,
    InferenceResponse,
    OllamaInferenceError,
    OllamaTimeoutError,
    OllamaConnectionError
)


class TestOllamaClient:
    """Test cases for Ollama client"""

    @pytest.fixture
    def config(self):
        """Create test config"""
        return OllamaConfig(
            host="http://localhost:11434",
            default_model="llama3.2:3b",
            request_timeout=5.0,
            max_retries=1
        )

    @pytest.fixture
    def client(self, config):
        """Create test client"""
        return OllamaClient(config)

    @pytest.mark.asyncio
    async def test_client_initialization(self, config):
        """Test client initializes correctly"""
        client = OllamaClient(config)
        assert client.config == config
        assert client._healthy == False

    @pytest.mark.asyncio
    async def test_mock_mode_when_ollama_unavailable(self):
        """Test client works in mock mode when Ollama package unavailable"""
        with patch('src.app.ai.ollama_client.OLLAMA_AVAILABLE', False):
            config = OllamaConfig()
            client = OllamaClient(config)

            request = InferenceRequest(messages=[{"role": "user", "content": "Hello"}])
            response = await client.generate(request)

            assert "MOCK OLLAMA" in response.content
            assert response.model == config.default_model
            assert response.processing_time > 0

    @pytest.mark.asyncio
    async def test_health_check_success(self, client):
        """Test successful health check"""
        # Mock the client.list() call
        mock_response = {"models": [{"name": "llama3.2:3b"}]}
        client._client.list = AsyncMock(return_value=mock_response)

        healthy = await client.health_check()
        assert healthy == True
        assert client._healthy == True

    @pytest.mark.asyncio
    async def test_health_check_failure(self, client):
        """Test failed health check"""
        client._client.list = AsyncMock(side_effect=Exception("Connection failed"))

        healthy = await client.health_check()
        assert healthy == False
        assert client._healthy == False

    @pytest.mark.asyncio
    async def test_list_models(self, client):
        """Test listing models"""
        mock_models = [{"name": "llama3.2:3b"}, {"name": "codellama:7b"}]
        mock_response = {"models": mock_models}
        client._client.list = AsyncMock(return_value=mock_response)

        models = await client.list_models()
        assert models == mock_models

    @pytest.mark.asyncio
    async def test_pull_model_success(self, client):
        """Test successful model pull"""
        client._client.pull = AsyncMock()

        success = await client.pull_model("llama3.2:3b")
        assert success == True
        client._client.pull.assert_called_once_with("llama3.2:3b")

    @pytest.mark.asyncio
    async def test_pull_model_failure(self, client):
        """Test failed model pull"""
        client._client.pull = AsyncMock(side_effect=Exception("Pull failed"))

        success = await client.pull_model("llama3.2:3b")
        assert success == False

    @pytest.mark.asyncio
    async def test_generate_success(self, client):
        """Test successful inference generation"""
        mock_response = {
            "message": {"content": "Hello, world!"},
            "done_reason": "stop"
        }
        client._client.chat = AsyncMock(return_value=mock_response)

        request = InferenceRequest(
            messages=[{"role": "user", "content": "Hello"}],
            model="llama3.2:3b"
        )

        response = await client.generate(request)

        assert isinstance(response, InferenceResponse)
        assert response.content == "Hello, world!"
        assert response.model == "llama3.2:3b"
        assert response.finish_reason == "stop"
        assert response.processing_time > 0

    @pytest.mark.asyncio
    async def test_generate_timeout(self, client):
        """Test inference timeout"""
        client._client.chat = AsyncMock(side_effect=asyncio.TimeoutError())

        request = InferenceRequest(
            messages=[{"role": "user", "content": "Hello"}],
            timeout=0.1
        )

        with pytest.raises(OllamaTimeoutError):
            await client.generate(request)

    @pytest.mark.asyncio
    async def test_generate_with_retries(self, client):
        """Test inference with retries"""
        # First call fails, second succeeds
        mock_response = {
            "message": {"content": "Success after retry"},
            "done_reason": "stop"
        }
        client._client.chat = AsyncMock(side_effect=[Exception("First attempt failed"), mock_response])

        request = InferenceRequest(messages=[{"role": "user", "content": "Hello"}])

        response = await client.generate(request)

        assert response.content == "Success after retry"
        assert client._client.chat.call_count == 2  # Two attempts

    @pytest.mark.asyncio
    async def test_generate_max_retries_exceeded(self, client):
        """Test inference fails after max retries"""
        client._client.chat = AsyncMock(side_effect=Exception("Always fails"))

        request = InferenceRequest(messages=[{"role": "user", "content": "Hello"}])

        with pytest.raises(OllamaInferenceError):
            await client.generate(request)

        assert client._client.chat.call_count == 2  # max_retries + 1

    @pytest.mark.asyncio
    async def test_streaming_generation(self, client):
        """Test streaming inference"""
        # Create an async generator mock
        async def mock_stream(**kwargs):
            yield {"message": {"content": "Hello"}, "done": False}
            yield {"message": {"content": " world"}, "done": False}
            yield {"message": {"content": "!"}, "done": True}

        client._client.chat = mock_stream

        request = InferenceRequest(
            messages=[{"role": "user", "content": "Hello"}],
            stream=True
        )

        chunks_received = []
        async for chunk in client.generate_stream(request):
            chunks_received.append(chunk)

        assert chunks_received == ["Hello", " world", "!"]

    @pytest.mark.asyncio
    async def test_streaming_error(self, client):
        """Test streaming inference error"""
        client._client.chat = AsyncMock(side_effect=Exception("Streaming failed"))

        request = InferenceRequest(
            messages=[{"role": "user", "content": "Hello"}],
            stream=True
        )

        with pytest.raises(OllamaInferenceError):
            async for chunk in client.generate_stream(request):
                pass

    @pytest.mark.asyncio
    async def test_connection_error_when_client_none(self):
        """Test connection error when client is not initialized"""
        config = OllamaConfig()
        client = OllamaClient(config)
        client._client = None  # Simulate initialization failure

        request = InferenceRequest(messages=[{"role": "user", "content": "Hello"}])

        with pytest.raises(OllamaConnectionError):
            await client.generate(request)