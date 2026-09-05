// ResQNet Real-Time WebSocket Hook
import { useState, useEffect, useRef, useCallback } from 'react';
import { WorldStateSnapshot } from '../types';
import { api } from '../services/api';

const WS_URL = 'ws://localhost:8000/ws/frontend';

export function useSystemWebSocket() {
  const [snapshot, setSnapshot] = useState<WorldStateSnapshot | null>(null);
  const [isConnected, setIsConnected] = useState<boolean>(false);
  const [latencyMs, setLatencyMs] = useState<number>(12);
  const [lastUpdated, setLastUpdated] = useState<number>(Date.now());
  const wsRef = useRef<WebSocket | null>(null);
  const pingIntervalRef = useRef<any>(null);

  const fetchFallback = useCallback(async () => {
    try {
      const data = await api.getWorldState();
      setSnapshot(data);
      setLastUpdated(Date.now());
    } catch (e) {
      console.warn('Fallback HTTP poll failed:', e);
    }
  }, []);

  useEffect(() => {
    let reconnectTimeout: any = null;
    let isMounted = true;

    function connect() {
      try {
        const ws = new WebSocket(WS_URL);
        wsRef.current = ws;

        ws.onopen = () => {
          if (!isMounted) return;
          setIsConnected(true);
          console.log('[ResQNet WS] Connected to System A');

          // Setup ping/pong latency measurement
          pingIntervalRef.current = setInterval(() => {
            if (ws.readyState === WebSocket.OPEN) {
              const pingStart = Date.now();
              ws.send(JSON.stringify({ type: 'PING', timestamp: pingStart }));
            }
          }, 2000);
        };

        ws.onmessage = (event) => {
          if (!isMounted) return;
          try {
            const msg = JSON.parse(event.data);
            if (msg.type === 'STATE_UPDATE' && msg.snapshot) {
              setSnapshot(msg.snapshot);
              setLastUpdated(Date.now());
            } else if (msg.type === 'PONG' && msg.timestamp) {
              const rtt = Date.now() - msg.timestamp;
              setLatencyMs(rtt);
            }
          } catch (err) {
            console.error('[ResQNet WS] Error parsing packet:', err);
          }
        };

        ws.onerror = (err) => {
          console.warn('[ResQNet WS] Connection error:', err);
        };

        ws.onclose = () => {
          if (!isMounted) return;
          setIsConnected(false);
          clearInterval(pingIntervalRef.current);
          console.log('[ResQNet WS] Disconnected. Retrying in 1.5s...');
          reconnectTimeout = setTimeout(connect, 1500);
        };
      } catch (err) {
        console.error('[ResQNet WS] Setup error:', err);
        reconnectTimeout = setTimeout(connect, 2000);
      }
    }

    // Initial HTTP fetch to avoid blank screen while WS opens
    fetchFallback();
    connect();

    return () => {
      isMounted = false;
      clearInterval(pingIntervalRef.current);
      clearTimeout(reconnectTimeout);
      if (wsRef.current) {
        wsRef.current.close();
      }
    };
  }, [fetchFallback]);

  return {
    snapshot,
    isConnected,
    latencyMs,
    lastUpdated,
    refresh: fetchFallback,
  };
}
