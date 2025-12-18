"""Simple runner that executes a job payload.

For the POC we execute trivial tasks: type 'noop' or 'sleep'.
"""
from __future__ import annotations

import time
from typing import Dict, Any


def run_job(job: Dict[str, Any]) -> None:
    job_type = job.get('type')
    payload = job.get('payload') or '{}'
    try:
        # payload stored as JSON string in sqlite helper; convert if necessary
        if isinstance(payload, str):
            import json
            payload_obj = json.loads(payload)
        else:
            payload_obj = payload
    except Exception:
        payload_obj = {}

    if job_type == 'noop':
        # do nothing
        return
    if job_type == 'sleep':
        seconds = int(payload_obj.get('seconds', 1))
        time.sleep(seconds)
        return
    # default: noop
    return
