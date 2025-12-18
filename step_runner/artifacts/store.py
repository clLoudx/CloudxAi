"""Artifact store scaffold. In production, this should write to an immutable, versioned store.
This scaffold only records artifact metadata into the context for audit purposes.
"""
from pathlib import Path

class ArtifactStore:
    def __init__(self, base_url: str = None):
        self.base_url = base_url

    def store(self, path: Path, metadata: dict):
        # dry-run: return a synthetic artifact reference
        return {"artifact_ref": f"dry://{path.name}", "metadata": metadata}
