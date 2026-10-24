@echo off
title Servidor Dino Survival
cd /d "%~dp0"
echo ============================================================
echo  Servidor do Dino Survival
echo  Deixe esta janela aberta. Para desligar, feche a janela.
echo  O mundo fica salvo na pasta "servidor" ao lado deste arquivo.
echo  Mude --bots=20 abaixo para ter mais ou menos dinossauros (max. 100).
echo  Tire o --dev para desligar os comandos de teste (/grow, /tp...).
echo ============================================================
DinoSurvival.console.exe --headless -- --server --port=7777 --bots=20 --dev "--save=%~dp0servidor\world.json"
pause
