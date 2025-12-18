import os
import os
import yaml

# Path to the workflow file (tests live in .github/workflows/tests)
WORKFLOW_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'auto-merge.yml'))


def load_workflow(path):
    with open(path, 'r') as f:
        return yaml.safe_load(f)


def _get_on_mapping(wf):
    """Return the mapping under the workflow 'on' key.

    Note: some YAML loaders (YAML 1.1) coerce the bare string 'on' to boolean True.
    Accept either 'on' or True as the top-level key.
    """
    if 'on' in wf:
        return wf['on']
    if True in wf:
        return wf[True]
    return None


def test_triggers_ready_for_review():
    wf = load_workflow(WORKFLOW_PATH)
    on_map = _get_on_mapping(wf)
    assert on_map is not None, "Workflow missing 'on' trigger mapping"
    assert 'pull_request' in on_map, "Workflow must trigger on pull_request ready_for_review"
    pr = on_map['pull_request']
    # pull_request can be a mapping with types
    assert isinstance(pr, dict) and 'types' in pr and 'ready_for_review' in pr['types']


def test_requires_auto_merge_label():
    wf = load_workflow(WORKFLOW_PATH)
    jobs = wf.get('jobs', {})
    # locate the validate job and its steps
    validate = jobs.get('validate', {})
    steps = validate.get('steps', [])
    found = False
    for step in steps:
        if step.get('id') == 'check' and step.get('uses', '').startswith('actions/github-script'):
            script = step.get('with', {}).get('script', '')
            if 'auto-merge' in script:
                found = True
                break
    assert found, "Workflow must require 'auto-merge' label in validate step"
