#!/usr/bin/env bash
# Roda tudo: compilação, testes de unidade e teste de rede. Use antes de todo commit.
# pipefail: sem ele o `| grep` esconde a falha do teste de rede e o script sai com 0.
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT:-godot}"
./tools/check.sh || exit 1
"$GODOT" --headless --path . -s tests/run_tests.gd 2>&1 | grep -vE "^Godot Engine|^$" || exit 1
"$GODOT" --headless --path . -s tests/run_tests.gd >/dev/null 2>&1 || { echo "testes de unidade falharam"; exit 1; }
./tools/net_test.sh | grep -E "TEST FAIL|==" || exit 1
