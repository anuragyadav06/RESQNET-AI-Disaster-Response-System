from pydantic import BaseModel, Field
from typing import Any, Dict, Optional
import time, uuid

class Envelope(BaseModel):
    protocol: str = "resqnet.v1"
    message_id: str = Field(default_factory=lambda: f"MSG-{uuid.uuid4().hex[:10]}")
    timestamp: float = Field(default_factory=time.time)
    source_type: str
    source_id: str
    message_type: str
    event_type: Optional[str] = None
    correlation_id: Optional[str] = None
    causation_id: Optional[str] = None
    payload: Dict[str, Any] = Field(default_factory=dict)
