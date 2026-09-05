"""Lightweight in-process event bus for operational events."""
from __future__ import annotations
import asyncio
import time
from collections import deque
from typing import Any, Awaitable, Callable, Dict, List

Subscriber = Callable[[Dict[str, Any]], Awaitable[None]]

class EventBus:
    def __init__(self, max_events: int = 500):
        self.history = deque(maxlen=max_events)
        self.subscribers: List[Subscriber] = []
        self._lock = asyncio.Lock()

    async def publish(self, event_type: str, payload: Dict[str, Any], source: str = "SYSTEM_A", correlation_id: str | None = None):
        event = {
            "protocol": "resqnet.v1",
            "event_id": f"EVT-{int(time.time()*1000)}",
            "timestamp": time.time(),
            "event_type": event_type,
            "source": source,
            "correlation_id": correlation_id,
            "payload": payload,
        }
        async with self._lock:
            self.history.append(event)
            subscribers = list(self.subscribers)
        if subscribers:
            await asyncio.gather(*(s(event) for s in subscribers), return_exceptions=True)
        return event

    def subscribe(self, subscriber: Subscriber):
        if subscriber not in self.subscribers:
            self.subscribers.append(subscriber)

    def recent(self, limit: int = 100):
        return list(self.history)[-limit:]

event_bus = EventBus()
