@echo off
title ResQNet System A - Backend Server
echo ===================================================
echo Starting ResQNet System A Backend (FastAPI + WebSocket)
echo API Docs: http://localhost:8000/docs
echo WebSocket: ws://localhost:8000/ws/frontend
echo Simulation WS: ws://localhost:8000/ws/simulation/{session_id}
echo ===================================================
cd /d "%~dp0"
py -m uvicorn app.main:app --app-dir backend --host 0.0.0.0 --port 8000 --reload
pause
