#!/usr/bin/env bash
# Gera o jogo pra Windows: build/DinoSurvival-windows-vX.zip com o .exe, o .bat do servidor
# e o LEIA-ME. Precisa dos export templates do Godot 4.7.2 instalados.
set -eu
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
VERSION=$(grep -E '^const VERSION' scripts/config.gd | sed -E 's/.*"(.*)".*/\1/')
rm -rf build/windows
mkdir -p build/windows
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Windows" build/windows/DinoSurvival.exe 2>&1 | grep -vE "^$|savepack|Godot Engine" || true
test -f build/windows/DinoSurvival.exe
cp tools/windows/iniciar_servidor.bat tools/windows/testar_desempenho.bat tools/windows/LEIA-ME.txt build/windows/
(cd build/windows && rm -f "../DinoSurvival-windows-v$VERSION.zip" && zip -q -r "../DinoSurvival-windows-v$VERSION.zip" .)
ls -la build/windows "build/DinoSurvival-windows-v$VERSION.zip"
