@echo off
title Servidor Dino Survival
cd /d "%~dp0"
echo ============================================================
echo  Servidor do Dino Survival
echo  Deixe esta janela aberta. Para desligar, feche a janela.
echo  O mundo fica salvo na pasta "servidor" ao lado deste arquivo.
echo  Mude --bots=70 abaixo para ter mais ou menos dinossauros (max. 100).
echo  --map-size=2048 e o lado do mapa em metros. Se mudar, os dinos dos jogadores vao junto.
echo  Tire o --dev para desligar os comandos de teste (/grow, /tp...).
echo ============================================================
DinoSurvival.console.exe --headless -- --server --port=7777 --bots=70 --map-size=2048 --dev "--save=%~dp0servidor\world.json"
pause
