"""Collect artifacts from the workspace and record their provenance. Dry-run only."""
from .base import Step

class ArchiveStep(Step):
    name = "archive"

    def __init__(self, pattern: str = "**/*"):
        self.pattern = pattern

    def prepare(self, ctx: dict):
        pass

    def execute(self, ctx: dict):
        # do not access filesystem in this scaffold
        ctx.setdefault("actions", []).append({"archive": {"pattern": self.pattern}})
        return {"status": "dry-run", "pattern": self.pattern}

    def verify(self, ctx: dict):
        return True
