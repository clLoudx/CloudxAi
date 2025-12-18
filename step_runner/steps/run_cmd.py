"""Execute a command in the isolated workspace. This scaffold performs a safe dry-run.

WARNING: This implementation is intentionally non-executing to respect safety constraints.
Replace with a controlled execution layer (docker/pod) in production.
"""
from .base import Step

class RunCmdStep(Step):
    name = "run_cmd"

    def __init__(self, cmd: str):
        self.cmd = cmd

    def prepare(self, ctx: dict):
        if not self.cmd:
            raise ValueError("cmd required")

    def execute(self, ctx: dict):
        # record the command intent without executing
        ctx.setdefault("actions", []).append({"run_cmd": {"cmd": self.cmd}})
        return {"status": "dry-run", "cmd": self.cmd}

    def verify(self, ctx: dict):
        return True
