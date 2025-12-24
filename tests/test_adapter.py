import pytest
from ai.adapter import is_safe, call_openai


def test_is_safe_allows_empty_and_safe_text():
    assert is_safe('') is True
    assert is_safe('Hello, world') is True


def test_is_safe_blocks_bad_phrases():
    assert is_safe('please rm -rf /') is False
    assert is_safe('Reboot and shutdown now') is False
    assert is_safe('use import os to list files') is False


def test_call_openai_returns_mock_reply_for_safe_text():
    resp = call_openai([{'role': 'user', 'content': 'say hi'}])
    assert isinstance(resp, dict)
    assert resp.get('mock') is True
    assert resp.get('reply', '').startswith('[MOCK]')


def test_call_openai_blocks_unsafe_text():
    resp = call_openai([{'role': 'user', 'content': 'rm -rf /'}])
    assert isinstance(resp, dict)
    assert resp.get('error') == 'blocked' or 'blocked' in resp.get('reply', '')
