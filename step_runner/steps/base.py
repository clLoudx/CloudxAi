from abc import ABC, abstractmethod

class Step(ABC):
    name: str = "base"

    @abstractmethod
    def prepare(self, ctx: dict):
        pass

    @abstractmethod
    def execute(self, ctx: dict):
        pass

    @abstractmethod
    def verify(self, ctx: dict):
        pass

    def cleanup(self, ctx: dict):
        # optional
        return None
