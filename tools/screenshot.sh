#!/usr/bin/env bash
# Tira um print do jogo rodando de verdade (servidor + cliente com tela virtual).
# Serve pra conferir o visual sem abrir o jogo. Precisa de xvfb-run e Mesa (Linux).
#
# Uso: tools/screenshot.sh saida.png [espécie] [comandos de dev] [cam-yaw] [cam-pitch] [segundos]
# Ex.:  tools/screenshot.sh /tmp/a.png carnotaurus "/grow 1;/spawn triceratops 1" 1.4 -0.25
# Mapa maior: SERVER_ARGS="--map-size=2048" tools/screenshot.sh /tmp/b.png carnotaurus "/tp 1500 1200"
set -u
cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT:-godot}"
OUT="${1:-/tmp/print.png}"
SPECIES="${2:-carnotaurus}"
CMDS="${3:-}"
CAM_YAW="${4:-}"
CAM_PITCH="${5:--0.3}"
WAIT="${6:-7}"
PORT="${PORT:-7810}"
TMP="$(mktemp -d)"

"$GODOT" --headless --path . -- --server --dev --port="$PORT" --bots="${BOTS:-30}" --save="$TMP/world.json" ${SERVER_ARGS:-} >"$TMP/server.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT
sleep 2

EXTRA=()
[ -n "$CAM_YAW" ] && EXTRA+=("--cam-yaw=$CAM_YAW")
[ -n "$CMDS" ] && EXTRA+=("--cmd=$CMDS")
timeout 90 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . \
  --rendering-driver opengl3 --rendering-method gl_compatibility --resolution 1280x720 -- \
  --connect=127.0.0.1:"$PORT" --name=Foto --species="$SPECIES" --cam-pitch="$CAM_PITCH" \
  --screenshot="$OUT" --screenshot-after="$WAIT" --auto-quit="$((WAIT + 2))" "${EXTRA[@]}" ${CLIENT_ARGS:-} >"$TMP/client.log" 2>&1
grep -E "SCRIPT ERROR|print salvo|AUTOPILOT|ERROR" "$TMP/client.log" "$TMP/server.log" | grep -v -E "ALSA|audio_driver|status < 0"
