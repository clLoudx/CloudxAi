import pytest
from step_runner.runner import Runner
from step_runner.steps.git_clone import GitCloneStep

def test_runner_dry_run():
    ctx = {}
    steps = [GitCloneStep(repo_url="https://example.com/repo.git", ref="main")]
    r = Runner(steps, ctx)
    results = r.run()
    assert isinstance(results, list)
    assert results[0]["status"] == "dry-run"
    assert "actions" in ctx
