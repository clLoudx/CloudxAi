"""Isolated workspace helpers. Uses temporary directories and enforces isolation.

This is a minimal, safe scaffold. Real deployments must replace the isolation layer with container-based isolation.
"""
import tempfile
import shutil
from pathlib import Path

class Workspace:
    def __init__(self):
        self._td = None
        self.path = None

    def __enter__(self):
        self._td = tempfile.TemporaryDirectory()
        self.path = Path(self._td.name)
        return self

    def __exit__(self, exc_type, exc, tb):
        try:
            self.cleanup()
        finally:
            if self._td:
                self._td.cleanup()

    def cleanup(self):
        # ensure files are removed; in prod, use stronger isolation
        if self.path and self.path.exists():
            shutil.rmtree(self.path, ignore_errors=True)
