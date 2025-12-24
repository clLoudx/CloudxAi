from app.ai.ollama_client import create_ollama_client


def test_create_ollama_client_returns_client():
    client = create_ollama_client()
    # Client should be an object with a generate coroutine method
    assert hasattr(client, 'generate')
    assert callable(getattr(client, 'generate'))
