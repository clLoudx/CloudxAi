Developer guide — CloudxAi
===============================

Local development

1. Create a Python virtual environment (do not commit it):

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

2. Running unit tests (recommended to use PYTHONPATH for local imports):

```bash
export PYTHONPATH=.
pytest -q
```

3. Running the StepRunner unit test (fast):

```bash
PYTHONPATH=. pytest -q step_runner/tests/test_runner.py
```

4. Linting and formatting (pre-commit recommended):

 - Use `black`, `ruff`, and `isort` where applicable. Add pre-commit hooks via `.pre-commit-config.yaml` if you maintain the repository.

Branching and PRs

 - Create branches with descriptive names, e.g. `chore/phase-6/hygiene`.
 - Open a draft PR first for hygiene and repo-scope changes.

Agent onboarding primer
----------------------
This repository includes a mandatory agent onboarding primer at `docs/AGENT_EXECUTION_PRIMER.md`. Automated agents, CI runners, and repository automation SHOULD reference this file and must acknowledge the onboarding sentence (see file) before performing implementation work. Maintainers and reviewers should verify agent acknowledgements as part of PR review for automation-related changes.

Developer guide — CloudxAi
===============================

Local development

1. Create a Python virtual environment (do not commit it):

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

1. Running unit tests (recommended to use PYTHONPATH for local imports):

```bash
export PYTHONPATH=.
pytest -q
```

1. Running the StepRunner unit test (fast):

```bash
PYTHONPATH=. pytest -q step_runner/tests/test_runner.py
```

1. Linting and formatting (pre-commit recommended):

- Use `black`, `ruff`, and `isort` where applicable. Add pre-commit hooks via `.pre-commit-config.yaml` if you maintain the repository.

Branching and PRs

- Create branches with descriptive names, e.g. `chore/phase-6/hygiene`.
- Open a draft PR first for hygiene and repo-scope changes.

Debugging tips

- Use `print` or logging in `ai/controller/fastapi_app.py` for API-level debugging.
- For worker issues, instrument `worker/runner.py` and run in an isolated environment.
