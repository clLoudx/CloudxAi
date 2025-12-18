import importlib.util
import os
from pathlib import Path


def _load_module_from_path(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)  # type: ignore
    return module


def test_runner_dry_run():
    """A minimal smoke test for the step_runner logging capture.

    This test does not assume package installation; it imports the logging
    helper by file path and exercises a basic emit call.
    """
    base = Path(__file__).resolve().parents[2]
    capture_path = base / 'step_runner' / 'logs' / 'capture.py'
    assert capture_path.exists(), f"Expected {capture_path} to exist"
    mod = _load_module_from_path(capture_path, 'capture')
    LogCapture = getattr(mod, 'LogCapture')
    lc = LogCapture()
    entry = lc.emit('info', 'dry-run', {'k': 'v'})
    assert isinstance(entry, dict)
    assert entry['level'] == 'info'
    assert entry['message'] == 'dry-run'
