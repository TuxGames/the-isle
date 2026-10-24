#!/usr/bin/env bash
# Confere se todos os scripts compilam.
# 1) abre o projeto no editor headless (gera o cache de classes)
# 2) confere cada .gd separadamente (ignora o aviso falso do autoload Net nesse modo)
cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT:-godot}"
fail=0
out=$("$GODOT" --headless --path . --import 2>&1)
if echo "$out" | grep -qE "SCRIPT ERROR|ERROR:"; then
  echo "$out" | grep -E -A1 "SCRIPT ERROR|ERROR:"
  fail=1
fi
for f in $(find scripts tests -name '*.gd' | sort); do
  r=$("$GODOT" --headless --path . --check-only -s "$f" 2>&1 \
      | grep -E "SCRIPT ERROR|Parse Error|ERROR" \
      | grep -v "Identifier not found: Net" \
      | grep -v "Failed to compile depended scripts" \
      | grep -v 'with error "Compilation failed"')
  if [ -n "$r" ]; then echo "== $f"; echo "$r"; fail=1; fi
done
[ $fail -eq 0 ] && echo "OK: todos os scripts compilam"
exit $fail
