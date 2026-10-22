#!/usr/bin/env bash
# Teste de rede de ponta a ponta: um servidor dedicado de verdade + clientes de verdade.
#
# Roteiro:
#  1. bob (Dryosaurus novo) e alice (Carnotaurus) entram ao mesmo tempo.
#  2. alice vira adulta, erra uma mordida de costas e acerta o bob de frente.
#  3. bob sai; alice confere que o dino dele sumiu e continua jogando sozinha.
#  4. alice sai: ninguém online → o mundo tem que pausar.
#  5. bob volta: tem que estar EXATAMENTE igual (vida, fome, sede, crescimento, posição).
#  6. o servidor reinicia (lê o save) e o bob volta de novo, ainda igual.
#  7. bob morre e renasce jovem.
set -u
cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT:-godot}"
PORT="${PORT:-7791}"
TMP="$(mktemp -d)"
SAVE="$TMP/world.json"
LOG="$TMP/server.log"
FAILS=0
SERVER_PID=""

start_server() {
  "$GODOT" --headless --path . -- --server --dev --port="$PORT" --bots=0 --save="$SAVE" >>"$LOG" 2>&1 &
  SERVER_PID=$!
  sleep 2
}

stop_server() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null
  SERVER_PID=""
}

client() {
  local role="$1"; shift
  "$GODOT" --headless --path . -- --test-client --role="$role" --port="$PORT" "$@" >"$TMP/$role.log" 2>&1
  local code=$?
  grep -E "TEST|SCRIPT ERROR|ERROR:" "$TMP/$role.log"
  return $code
}

trap stop_server EXIT

start_server
client bob --out="$TMP/bob.json" & BOB=$!
sleep 1
client alice & ALICE=$!
wait $BOB || FAILS=$((FAILS+1))
wait $ALICE || FAILS=$((FAILS+1))

sleep 3   # ninguém online: o mundo tem que ficar parado
client bob_return --expect="$TMP/bob.json" || FAILS=$((FAILS+1))

stop_server
start_server   # reinício do servidor: o estado tem que vir do save
client bob_return --expect="$TMP/bob.json" || FAILS=$((FAILS+1))
client bob_die || FAILS=$((FAILS+1))
stop_server

echo "---- log do servidor ----"
grep -E "\[mundo\]|\[login\]|\[morte\]|ERROR" "$LOG"
echo "-------------------------"

# Toda vez que o mundo é retomado, tem que voltar no mesmo instante em que pausou.
if awk '
  /\[mundo\] pausado em world_time=/ { split($0, a, "world_time="); split(a[2], b, " "); p = b[1]; next }
  /\[mundo\] retomado em world_time=/ {
    split($0, a, "world_time="); r = a[2] + 0
    if (p == "") next
    if (r == p + 0) { print "TEST PASS: [servidor] mundo parado sem ninguém online (pausou e voltou em " r ")" }
    else { print "TEST FAIL: [servidor] relógio andou com o servidor vazio (" p " -> " r ")"; bad = 1 }
  }
  END { exit bad }' "$LOG"; then :; else FAILS=$((FAILS+1)); fi

# Enquanto a alice jogava sozinha, o relógio tinha que andar.
BOB_OUT=$(grep -m1 "\[login\] bob saiu" "$LOG" | sed -E 's/.*world_time=([0-9.]+).*/\1/')
ALICE_OUT=$(grep -m1 "\[login\] alice saiu" "$LOG" | sed -E 's/.*world_time=([0-9.]+).*/\1/')
if awk -v a="$BOB_OUT" -v b="$ALICE_OUT" 'BEGIN { exit !(b > a + 3) }'; then
  echo "TEST PASS: [servidor] mundo andou enquanto só a alice jogava ($BOB_OUT -> $ALICE_OUT)"
else
  echo "TEST FAIL: [servidor] mundo não andou com a alice online ($BOB_OUT -> $ALICE_OUT)"
  FAILS=$((FAILS+1))
fi

if grep -q "SCRIPT ERROR" "$LOG" "$TMP"/*.log; then
  echo "TEST FAIL: erros de script nos logs (ver $TMP)"
  FAILS=$((FAILS+1))
fi

if [ "$FAILS" -eq 0 ]; then
  echo "== TESTE DE REDE: TUDO OK =="
else
  echo "== TESTE DE REDE: $FAILS etapa(s) com falha — logs em $TMP =="
fi
exit "$FAILS"
