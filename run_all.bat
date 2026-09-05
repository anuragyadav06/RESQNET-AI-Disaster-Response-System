@echo off
title ResQNet - Autonomous Platform Master Launcher
echo ===================================================
echo Starting ResQNet Autonomous Disaster Response Suite
echo 1. System A Backend (Port 8000)
echo 2. System A Frontend (Port 5173)
echo 3. System B Godot 4 Digital Twin
echo ===================================================
cd /d "%~dp0"
start "ResQNet Backend" cmd /c run_backend.bat
timeout /t 2 /nobreak > nul
start "ResQNet Frontend" cmd /c run_frontend.bat
timeout /t 2 /nobreak > nul
start "ResQNet Godot Twin" cmd /c run_godot.bat
echo All systems launched in separate windows!
