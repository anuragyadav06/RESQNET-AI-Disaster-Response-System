"""
ResQNet Audit Engine - Immutable Decision Audit Logging
"""
import asyncio
import json
import os
import time
import uuid
from typing import Any, Dict, List, Optional
import aiosqlite

from app.core.config import settings
from app.schemas.audit import AuditEventType, AuditRecord


class AuditLogger:
    def __init__(self, db_path: str = settings.DB_PATH, max_in_memory: int = 1000):
        self.db_path = db_path
        self.max_in_memory = max_in_memory
        self._records: List[AuditRecord] = []
        self._lock = asyncio.Lock()
        self._initialized = False

    async def initialize(self):
        if self._initialized:
            return
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute(
                """
                CREATE TABLE IF NOT EXISTS audit_events (
                    event_id TEXT PRIMARY KEY,
                    timestamp REAL,
                    event_type TEXT,
                    decision TEXT,
                    inputs TEXT,
                    output TEXT,
                    reason TEXT,
                    confidence REAL,
                    affected_entities TEXT
                )
                """
            )
            await db.execute(
                "CREATE INDEX IF NOT EXISTS idx_timestamp ON audit_events(timestamp DESC)"
            )
            await db.execute(
                "CREATE INDEX IF NOT EXISTS idx_event_type ON audit_events(event_type)"
            )
            await db.commit()
        self._initialized = True

    async def log_event(
        self,
        event_type: AuditEventType,
        decision: str,
        reason: str,
        inputs: Optional[Dict[str, Any]] = None,
        output: Optional[Dict[str, Any]] = None,
        confidence: float = 1.0,
        affected_entities: Optional[List[str]] = None,
        timestamp: Optional[float] = None,
    ) -> AuditRecord:
        if timestamp is None:
            timestamp = time.time()
        
        event_id = f"EVT-{int(timestamp*1000)}-{uuid.uuid4().hex[:6]}"
        record = AuditRecord(
            event_id=event_id,
            timestamp=timestamp,
            event_type=event_type,
            decision=decision,
            inputs=inputs or {},
            output=output or {},
            reason=reason,
            confidence=confidence,
            affected_entities=affected_entities or [],
        )

        async with self._lock:
            self._records.append(record)
            if len(self._records) > self.max_in_memory:
                self._records.pop(0)

        # Async fire-and-forget persist to SQLite
        asyncio.create_task(self._persist_to_sqlite(record))
        return record

    async def _persist_to_sqlite(self, record: AuditRecord):
        try:
            if not self._initialized:
                await self.initialize()
            async with aiosqlite.connect(self.db_path) as db:
                await db.execute(
                    """
                    INSERT INTO audit_events 
                    (event_id, timestamp, event_type, decision, inputs, output, reason, confidence, affected_entities)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        record.event_id,
                        record.timestamp,
                        record.event_type.value,
                        record.decision,
                        json.dumps(record.inputs),
                        json.dumps(record.output),
                        record.reason,
                        record.confidence,
                        json.dumps(record.affected_entities),
                    ),
                )
                await db.commit()
        except Exception as e:
            # Fallback in-memory logger should not crash main loop
            print(f"[AuditLogger Error] Failed to persist event {record.event_id}: {e}")

    def get_recent(
        self,
        limit: int = 100,
        event_type: Optional[AuditEventType] = None,
        entity_id: Optional[str] = None,
    ) -> List[AuditRecord]:
        filtered = self._records
        if event_type:
            filtered = [r for r in filtered if r.event_type == event_type]
        if entity_id:
            filtered = [r for r in filtered if entity_id in r.affected_entities]
        
        # Return newest first
        return list(reversed(filtered[-limit:]))


# Global singleton
audit_logger = AuditLogger()
