"""A simple, safe git clone step. In this scaffold we implement a dry-run placeholder.

Real runner should perform a shallow clone in an isolated workspace with no credentials.
"""
from .base import Step

class GitCloneStep(Step):
    name = "git_clone"

    def __init__(self, repo_url: str, ref: str = "main"):
        self.repo_url = repo_url
        self.ref = ref

    def prepare(self, ctx: dict):
        # validate inputs
        if not self.repo_url:
            raise ValueError("repo_url required")

    def execute(self, ctx: dict):
        # dry-run: record intent only
        ctx.setdefault("actions", []).append({"git_clone": {"repo": self.repo_url, "ref": self.ref}})
        return {"status": "dry-run", "repo": self.repo_url}

    def verify(self, ctx: dict):
        # nothing to verify in dry-run
        return True
