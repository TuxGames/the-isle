@echo off
title Teste de desempenho - Dino Survival
cd /d "%~dp0"
echo ============================================================
echo  Teste de desempenho do servidor do Dino Survival
echo  Simula 5 jogadores e 70 dinossauros e mede se este PC aguenta.
echo  Leva cerca de 1 minuto. Feche os outros programas antes.
echo  Nao precisa de internet e nao mexe no mundo salvo.
echo ============================================================
DinoSurvival.console.exe --headless -- --bench "--out=%~dp0resultado_desempenho.txt"
echo.
echo O resultado ficou salvo em resultado_desempenho.txt, nesta pasta.
echo Mande esse arquivo pra quem programa o jogo.
pause
