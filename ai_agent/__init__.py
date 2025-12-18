# ai_agent package shim for compatibility with tests
from .agent_registry import *
__all__ = ["AgentSpec", "AgentStatus", "AgentRegistryProtocol", "InMemoryAgentRegistry"]
