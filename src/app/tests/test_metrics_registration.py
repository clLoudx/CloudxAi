import importlib
from app.metrics import register_ollama_metrics


def test_register_ollama_metrics_idempotent():
    # First registration should return a tuple (counter, histogram) or (None, None)
    m1 = register_ollama_metrics()
    assert isinstance(m1, tuple) and len(m1) == 2

    # Second registration should not raise and should return (None, None) if already registered
    m2 = register_ollama_metrics()
    assert isinstance(m2, tuple) and len(m2) == 2


def test_import_ollama_client_does_not_raise_duplicate():
    # Importing the ollama_client module should not raise duplicate metric errors
    importlib.import_module('app.ai.ollama_client')
    # If import succeeds, the module avoided duplicate metric registration at import time
    assert True
