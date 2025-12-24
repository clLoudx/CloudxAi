# src/app/ai/ollama_client.py
"""
Ollama Client - Main AI Core Inference Engine

Local-first AI inference with failover support.
Async wrapper around Ollama API with timeout and cancellation.
"""

import asyncio
import json
import time
from typing import List, Dict, Optional, Any, AsyncGenerator, Union
from contextlib import asynccontextmanager
from dataclasses import dataclass
import structlog

logger = structlog.get_logger("ai.ollama")

try:
    import ollama
    OLLAMA_AVAILABLE = True
except ImportError:
    OLLAMA_AVAILABLE = False
    logger.warning("Ollama package not available - using mock mode")

# Metrics are registered lazily via the metrics helper to avoid duplicate
# registration at import time (which can happen during test collection).


class OllamaConfig:
    """Configuration for Ollama client"""

    def __init__(
        self,
        host: str = "http://localhost:11434",
        default_model: str = "llama3.2:3b",
        request_timeout: float = 30.0,
        max_retries: int = 2,
        temperature: float = 0.1,
        max_tokens: Optional[int] = None,
        stream: bool = False
    ):
        self.host = host
        self.default_model = default_model
        self.request_timeout = request_timeout
        self.max_retries = max_retries
        self.temperature = temperature
        self.max_tokens = max_tokens
        self.stream = stream


class OllamaInferenceError(Exception):
    """Base exception for Ollama inference errors"""
    pass


class OllamaTimeoutError(OllamaInferenceError):
    """Timeout during Ollama inference"""
    pass


class OllamaConnectionError(OllamaInferenceError):
    """Connection error with Ollama server"""
    pass


class OllamaModelError(OllamaInferenceError):
    """Model-related error"""
    pass


@dataclass
class InferenceRequest:
    """Request for AI inference"""
    messages: List[Dict[str, str]]
    model: Optional[str] = None
    temperature: Optional[float] = None
    max_tokens: Optional[int] = None
    stream: Optional[bool] = None
    timeout: Optional[float] = None


@dataclass
class InferenceResponse:
    """Response from AI inference"""
    content: str
    model: str
    usage: Dict[str, Any]
    finish_reason: Optional[str] = None
    processing_time: float = 0.0


class OllamaClient:
    """
    Async Ollama client for AI inference

    Features:
    - Async inference with timeout/cancellation
    - Streaming support
    - Automatic retries
    - Health checks
    - Metrics collection
    - Failover-ready abstraction
    """

    def __init__(self, config: OllamaConfig, metrics: tuple | None = None):
        self.config = config
        self._client = None
        self._healthy = False
        # metrics is a tuple: (counter, histogram)
        self._metrics = metrics or (None, None)

        if not OLLAMA_AVAILABLE:
            logger.warning("Ollama not available - operating in mock mode")
            return

        try:
            self._client = ollama.AsyncClient(host=config.host)
            logger.info("Ollama client initialized", host=config.host)
        except Exception as e:
            logger.error("Failed to initialize Ollama client", error=str(e))
            self._client = None

    async def _ensure_client(self):
        """Ensure Ollama client is available"""
        if not OLLAMA_AVAILABLE:
            raise OllamaConnectionError("Ollama package not available")

        if self._client is None:
            raise OllamaConnectionError("Ollama client not initialized")

    async def health_check(self) -> bool:
        """
        Check if Ollama server is healthy and responsive

        Returns:
            bool: True if healthy, False otherwise
        """
        if not OLLAMA_AVAILABLE or self._client is None:
            self._healthy = False
            return False

        try:
            # Try to list models as a health check
            await asyncio.wait_for(
                self._client.list(),
                timeout=5.0
            )
            self._healthy = True
            logger.debug("Ollama health check passed")
            return True
        except asyncio.TimeoutError:
            logger.warning("Ollama health check timeout")
        except Exception as e:
            logger.warning("Ollama health check failed", error=str(e))

        self._healthy = False
        return False

    async def list_models(self) -> List[Dict[str, Any]]:
        """
        List available models

        Returns:
            List of model information
        """
        await self._ensure_client()

        try:
            response = await self._client.list()
            return response.get('models', [])
        except Exception as e:
            logger.error("Failed to list models", error=str(e))
            raise OllamaConnectionError(f"Failed to list models: {e}")

    async def pull_model(self, model: str) -> bool:
        """
        Pull a model from registry

        Args:
            model: Model name to pull

        Returns:
            bool: True if successful
        """
        await self._ensure_client()

        try:
            logger.info("Pulling model", model=model)
            await self._client.pull(model)
            logger.info("Model pulled successfully", model=model)
            return True
        except Exception as e:
            logger.error("Failed to pull model", model=model, error=str(e))
            return False

    async def generate(
        self,
        request: InferenceRequest
    ) -> InferenceResponse:
        """
        Generate inference response

        Args:
            request: Inference request

        Returns:
            Inference response
        """
        if not OLLAMA_AVAILABLE:
            # Mock response for testing
            return await self._mock_generate(request)

        await self._ensure_client()

        model = request.model or self.config.default_model
        timeout = request.timeout or self.config.request_timeout

        # Prepare Ollama request
        ollama_request = {
            "model": model,
            "messages": request.messages,
            "stream": request.stream or self.config.stream,
            "options": {
                "temperature": request.temperature or self.config.temperature,
            }
        }

        if request.max_tokens or self.config.max_tokens:
            ollama_request["options"]["num_predict"] = request.max_tokens or self.config.max_tokens

        start_time = time.time()

        for attempt in range(self.config.max_retries + 1):
            try:
                logger.debug("Starting Ollama inference", model=model, attempt=attempt + 1)

                # Use instance metrics if available (may be None in tests)
                _, latency = self._metrics
                if latency:
                    with latency.labels(model=model).time():
                        response = await asyncio.wait_for(
                            self._client.chat(**ollama_request),
                            timeout=timeout
                        )
                else:
                    response = await asyncio.wait_for(
                        self._client.chat(**ollama_request),
                        timeout=timeout
                    )

                processing_time = time.time() - start_time

                # Extract response content
                message = response.get('message', {})
                content = message.get('content', '')

                # Create usage info (Ollama doesn't provide detailed usage like OpenAI)
                usage = {
                    "prompt_tokens": 0,  # Ollama doesn't provide this
                    "completion_tokens": 0,  # Ollama doesn't provide this
                    "total_tokens": 0
                }

                finish_reason = response.get('done_reason')

                counter, _ = self._metrics
                if counter:
                    counter.labels(model=model, status="success").inc()

                logger.info("Ollama inference completed", model=model, processing_time=processing_time)

                return InferenceResponse(
                    content=content,
                    model=model,
                    usage=usage,
                    finish_reason=finish_reason,
                    processing_time=processing_time
                )

            except asyncio.TimeoutError:
                processing_time = time.time() - start_time
                logger.warning("Ollama inference timeout", model=model, attempt=attempt + 1, timeout=timeout)

                if attempt == self.config.max_retries:
                    counter, _ = self._metrics
                    if counter:
                        counter.labels(model=model, status="timeout").inc()
                    raise OllamaTimeoutError(f"Inference timeout after {processing_time:.2f}s")

            except Exception as e:
                processing_time = time.time() - start_time
                logger.warning("Ollama inference failed", model=model, attempt=attempt + 1, error=str(e))

                if attempt == self.config.max_retries:
                    counter, _ = self._metrics
                    if counter:
                        counter.labels(model=model, status="error").inc()
                    raise OllamaInferenceError(f"Inference failed: {e}")

                # Wait before retry
                await asyncio.sleep(0.5 * (2 ** attempt))

        # Should not reach here
        raise OllamaInferenceError("Inference failed after all retries")

    async def generate_stream(
        self,
        request: InferenceRequest
    ) -> AsyncGenerator[str, None]:
        """
        Generate streaming inference response

        Args:
            request: Inference request

        Yields:
            Response chunks
        """
        if not OLLAMA_AVAILABLE:
            # Mock streaming response
            yield "Mock streaming response from Ollama"
            return

        await self._ensure_client()

        model = request.model or self.config.default_model
        timeout = request.timeout or self.config.request_timeout

        ollama_request = {
            "model": model,
            "messages": request.messages,
            "stream": True,
            "options": {
                "temperature": request.temperature or self.config.temperature,
            }
        }

        if request.max_tokens or self.config.max_tokens:
            ollama_request["options"]["num_predict"] = request.max_tokens or self.config.max_tokens

        try:
            logger.debug("Starting streaming Ollama inference", model=model)

            # Use asyncio.wait_for with timeout for the entire streaming operation
            async def _stream_with_timeout():
                async for chunk in self._client.chat(**ollama_request):
                    message = chunk.get('message', {})
                    content = message.get('content', '')
                    if content:
                        yield content

                    if chunk.get('done', False):
                        break

            async for chunk in _stream_with_timeout():
                yield chunk

            logger.debug("Streaming Ollama inference completed", model=model)

        except Exception as e:
            logger.error("Streaming Ollama inference failed", model=model, error=str(e))
            raise OllamaInferenceError(f"Streaming inference failed: {e}")

    async def _mock_generate(self, request: InferenceRequest) -> InferenceResponse:
        """Mock inference for testing when Ollama is not available"""
        logger.info("Using mock Ollama inference")

        # Simulate processing time
        await asyncio.sleep(0.1)

        # Get the last user message
        last_message = ""
        for msg in reversed(request.messages):
            if msg.get('role') == 'user':
                last_message = msg.get('content', '')
                break

        mock_response = f"[MOCK OLLAMA] Response to: {last_message[:50]}..."

        return InferenceResponse(
            content=mock_response,
            model=request.model or self.config.default_model,
            usage={"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
            finish_reason="stop",
            processing_time=0.1
        )


def create_ollama_client(config: OllamaConfig | None = None):
    """Factory to create an OllamaClient with metrics registered lazily.

    Avoids import-time side-effects by registering metrics here and
    passing them into the client instance.
    """
    cfg = config or OllamaConfig()
    try:
        from ..metrics import register_ollama_metrics

        metrics = register_ollama_metrics()
    except Exception:
        metrics = (None, None)

    return OllamaClient(cfg, metrics=metrics)


# Backwards-compatible module-level name. Keep as None to avoid import-time
# initialization; callers should use create_ollama_client() or obtain the
# client from app.state/controller.ollama_client when available.
ollama_client = None