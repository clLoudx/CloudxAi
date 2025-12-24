"""Minimal AI adapter shim used for tests.

Provides `is_safe` and `call_openai` functions so the dashboard app can
exercise blocking logic and a simple mock reply when an API key is not
configured. This file is intentionally small and deterministic for tests.
"""
import os
import logging
from typing import List, Dict, Optional

logger = logging.getLogger("ai.adapter.shim")

BLACKLIST = ['rm -rf', 'shutdown', 'reboot', 'passwd', '/etc/shadow', 'import os', 'eval(', 'exec(', 'open(/etc']


def is_safe(text: str) -> bool:
    if not text:
        return True
    t = text.lower()
    for b in BLACKLIST:
        if b in t:
            return False
    return True


def call_openai(messages: List[Dict], model: str = None, api_key: Optional[str] = None, timeout: int = 10):
    # Simple mock: return a predictable reply; if content is unsafe, return blocked
    last = (messages[-1].get('content') if messages else '') or ''
    if not is_safe(last):
        return {"error": "blocked", "reply": "[blocked]"}
    return {"mock": True, "reply": "[MOCK] " + last}
