"""Deterministic runner that orchestrates steps in sequence."""
from typing import List
from step_runner.steps.base import Step

class Runner:
    def __init__(self, steps: List[Step], ctx: dict):
        self.steps = steps
        self.ctx = ctx

    def run(self):
        results = []
        for step in self.steps:
            step.prepare(self.ctx)
            result = step.execute(self.ctx)
            step.verify(self.ctx)
            results.append(result)
        return results
