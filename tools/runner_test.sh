#!/usr/bin/env bash
# Testa o próprio executor dos testes de unidade (tests/run_tests.gd).
# Ele tem que acusar teste que bate num erro de script (o GDScript abandona a função no meio),
# teste que não verifica nada e arquivo de teste que não compila, e terminar sozinho.
# Se o executor voltar a engolir isso, os outros testes passam "ok" sem valer nada.
#
# Os testes de mentira são criados numa pasta temporária fora do projeto: um deles tem erro
# de sintaxe de propósito e quebraria o tools/check.sh se morasse em tests/.
set -u
cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT:-godot}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/test_a_passa.gd" <<'EOF'
extends RefCounted
func test_passa(t) -> void:
	t.check(true, "ok")
EOF

cat > "$TMP/test_b_aborta.gd" <<'EOF'
extends RefCounted
func test_aborta_depois_de_um_check(t) -> void:
	t.check(true, "este passa")
	var o: Object = null
	print(o.get_class())   # erro de script: a função é abandonada aqui
	t.check(false, "nunca chega aqui")
func _helper() -> int:
	var o: Object = null
	return o.get_instance_id()   # erro de script dentro de uma função chamada pelo teste
func test_aborta_numa_funcao_chamada(t) -> void:
	t.check(_helper() == 0, "o helper abortou e devolveu o valor padrão")
func test_seguinte_roda_normal(t) -> void:
	t.check(true, "ok")
EOF

cat > "$TMP/test_c_vazio.gd" <<'EOF'
extends RefCounted
func test_sem_verificacao(_t) -> void:
	pass
EOF

cat > "$TMP/test_d_sintaxe.gd" <<'EOF'
extends RefCounted
func test_nem_compila(t) -> void:
	var x = = 3
	t.check(true, "ok")
EOF

cat > "$TMP/test_e_depois.gd" <<'EOF'
extends RefCounted
func test_roda_depois_do_arquivo_quebrado(t) -> void:
	t.check(true, "ok")
EOF

# Se o executor travar (era o que o erro de sintaxe causava), o timeout mata e o teste falha.
LIMIT=()
command -v timeout >/dev/null 2>&1 && LIMIT=(timeout 60)
out=$("${LIMIT[@]}" "$GODOT" --headless --path . -s tests/run_tests.gd -- --dir="$TMP" 2>/dev/null)
code=$?

fail=0
expect() {
  if ! grep -qF -- "$1" <<<"$out"; then echo "faltou na saída do executor: $1"; fail=1; fi
}
expect "  ok   test_a_passa::test_passa ("
expect "  FAIL test_b_aborta::test_aborta_depois_de_um_check: erro de script durante o teste"
expect "  FAIL test_b_aborta::test_aborta_numa_funcao_chamada: erro de script durante o teste"
expect "  ok   test_b_aborta::test_seguinte_roda_normal ("
expect "  FAIL test_c_vazio::test_sem_verificacao: o teste terminou sem fazer nenhuma verificação"
expect "  FAIL test_d_sintaxe: o arquivo test_d_sintaxe.gd não carregou"
expect "  ok   test_e_depois::test_roda_depois_do_arquivo_quebrado ("
expect "== TESTES DE UNIDADE: 4 falha(s), 3 ok =="
if [ "$code" -ne 1 ]; then
  echo "o executor saiu com código $code (esperado 1; 124 = travou e o timeout matou)"
  fail=1
fi

if [ $fail -ne 0 ]; then
  echo "---- saída do executor ----"
  echo "$out"
  echo "---------------------------"
  echo "FALHOU: o executor dos testes de unidade não está acusando o que devia"
  exit 1
fi
echo "OK: o executor acusa teste abortado, teste sem verificação e arquivo que não compila"
