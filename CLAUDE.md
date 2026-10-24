# CLAUDE.md — regras do projeto

Jogo de sobrevivência com dinossauros pra até 5 amigos, inspirado em The Isle.
**Godot 4.7.2 + GDScript**, servidor dedicado autoritativo. Idealizador e game designer:
**Marcelo**. Programação: **Tux** + Claude Code.

## Antes de mexer em qualquer coisa

1. Leia `docs/design.md`. É a fonte da verdade do game design. Só entra lá o que o Marcelo
   **decidiu**. Ideia sua ou sugestão de IA não decidida vai para "Em aberto".
2. Leia `docs/roadmap.md` pra saber em que versão estamos e qual é o próximo passo.
3. Leia `docs/arquitetura.md` pra entender onde fica cada coisa e o protocolo de rede.

## Comandos

```bash
tools/check.sh        # todos os scripts compilam?
tools/test.sh         # compilação + testes de unidade + teste de rede (rode antes de todo commit)
tools/net_test.sh     # só o teste de rede (servidor + clientes reais headless)
godot --headless --path . -s tests/run_tests.gd -- --only=nome   # filtra testes
tools/screenshot.sh /tmp/a.png carnotaurus "/grow 1;/spawn triceratops 1" 1.9 -0.2   # print do jogo
tools/export.sh       # gera build/DinoSurvival.exe (precisa dos export templates)
godot --headless --path . -- --bench   # teste de desempenho do servidor (5 jogadores + 70 bots)
```

A CI (`.github/workflows/testes.yml`) roda o `tools/test.sh` a cada push, em qualquer branch.

Publicar uma versão pros amigos (vai pra Releases, de onde eles baixam): suba `VERSION` em
`scripts/config.gd` e `config/version` no `project.godot` (os dois iguais) e faça o merge na `main`.
O `.github/workflows/release.yml` vê que essa versão ainda não tem Release, roda os testes, gera o
zip do Windows, cria a tag `vX.Y.Z` e publica. (Também publica se alguém der push numa tag `vX.Y.Z`.)

Rodar o servidor: `godot --headless --path . -- --server --dev --bots=30` (mapa maior: `--map-size=2048`)
Rodar o cliente: `godot --path . -- --connect=127.0.0.1 --name=Tux` (ou sem args = menu)

## Regras

- **Servidor decide tudo que importa** (vida, fome, sede, mordida, morte, bots, relógio).
  A única exceção é o movimento do próprio dino, que o cliente calcula e manda
  (é um jogo entre amigos, sem anticheat).
- **Toda a lógica do mundo fica em `scripts/sim/`** e não depende de rede nem de tela. É isso
  que deixa testar tudo headless. Não coloque regra de jogo no cliente nem no `game_server.gd`.
- **Todas as RPCs ficam em `scripts/net/net.gd`** (o Godot exige o mesmo caminho nos dois lados).
- **Números de equilíbrio ficam em `scripts/data/species.gd`** e `scripts/config.gd`, comentados.
- Mudou o protocolo de rede ou o formato do save? Suba `GameConfig.VERSION`. Se o save mudar,
  suba `WorldSim.SAVE_FORMAT` e escreva a migração em `load_save` (os amigos não podem perder o dino).
- Feature nova = teste novo em `tests/test_*.gd` (unidade) e, se for de rede, uma etapa em
  `tests/net_scenario.gd` + `tools/net_test.sh`.
- Texto que o jogador vê: **português do Brasil**. Comentários: português. Identificadores: inglês.
- Mexeu no visual? Tire um print com `tools/screenshot.sh` e olhe antes de dar por pronto.
- Ao terminar uma feature, atualize o status em `docs/design.md` (✅ / 🟡 / ⬜) e o `docs/roadmap.md`.
- Commits pequenos e descritivos, em português.

## Decisões do Marcelo que mais quebram coisas se esquecidas

- Sem ninguém online o **mundo inteiro para** (nada envelhece, cura, passa fome, muda de estação).
- Quem sai **some do mundo e fica congelado**: não pode ser atacado, não cura, não passa fome.
- Morreu → **recomeça jovem**, sempre.
- Raio só mata **bot**, nunca jogador (quando o clima existir).
- Máximo de **5 jogadores**; população de bots ~70 (máx. 100).
