# Arquitetura

```
              PC do jogador (até 5)                          Servidor dedicado (Lenovo, 24h)
 ┌──────────────────────────────────────┐          ┌─────────────────────────────────────────┐
 │ GameClient                            │  c_state │ GameServer (rede, save, comandos)       │
 │  ├─ controle do próprio dino ─────────┼─────────▶│  └─ WorldSim (o mundo inteiro)          │
 │  ├─ câmera, HUD, menu                 │ c_action │       ├─ Dino (estado de cada bicho)    │
 │  ├─ TerrainView (mesmo Terrain)       │─────────▶│       ├─ Metabolism (fome, cura...)     │
 │  └─ DinoView por bicho (interpolado) ◀┼──────────│       ├─ Combat (hitbox)                │
 │                                       │snapshot  │       ├─ BotBrain (IA)                  │
 │                                       │ 15 Hz    │       └─ Terrain (mapa por semente)     │
 └──────────────────────────────────────┘          └─────────────────────────────────────────┘
```

Um único executável faz os dois papéis. `scripts/main.gd` decide:
`--server` ou `--headless` → servidor; `--test-client` → cliente de teste; senão → jogo com menu.

## Pastas

| Pasta | O que tem | Depende de |
|---|---|---|
| `scripts/data/` | Tabela de espécies e números de equilíbrio | nada |
| `scripts/world/` | `Terrain`: altura, rio, arbustos, pontos de água | nada |
| `scripts/sim/` | Lógica do mundo: `Dino`, `Metabolism`, `Combat`, `Movement`, `BotBrain`, `WorldSim` | data, world |
| `scripts/net/` | `net.gd` (autoload `Net`, **todas** as RPCs) e `GameServer` | sim |
| `scripts/client/` | `GameClient`, `DinoView`, `TerrainView` | sim (só leitura), net |
| `scripts/ui/` | `Hud` (menu, barras, morte, pausa, chat) | data |
| `tests/` | Testes de unidade (`test_*.gd`) e o cliente de teste de rede | tudo |
| `tools/` | Scripts de teste, print e exportação | — |

**Regra:** `scripts/sim/` não conhece rede nem tela. Por isso dá pra testar o jogo todo
headless e rápido (`tests/run_tests.gd`).

## Laço do servidor

- `GameServer._process`: se **ninguém** está logado, não faz nada (o mundo para).
- Senão, roda `WorldSim.step(1/20 s)` em passo fixo e depois:
  - snapshot de todas as entidades pra cada jogador (15 Hz)
  - status do próprio dino pra cada jogador (10 Hz)
  - save em disco a cada 30 s (e em toda saída/morte)
- `WorldSim.step`: IA dos bots → separação dos corpos → metabolismo → comer/beber →
  golpes pendentes → mortes → carcaças → arbustos → reposição de bots.

## Protocolo (scripts/net/net.gd)

Cliente → servidor:

| RPC | Modo | Conteúdo |
|---|---|---|
| `c_login(nome, espécie, versão)` | confiável | espécie só vale se não houver dino vivo salvo |
| `c_state(seq, pos, yaw, flags)` | não confiável, 20 Hz | flags: correndo, andando |
| `c_action(ação, texto)` | confiável | atacar, começar/parar de comer, descansar, renascer, comando dev, chat |

Servidor → cliente:

| RPC | Conteúdo |
|---|---|
| `s_welcome(info)` | id da entidade, espécie, semente do mapa, se foi restaurado, modo dev |
| `s_login_failed(motivo)` | versão diferente, nome em uso, servidor cheio |
| `s_teleport(seq, pos, yaw)` | posição forçada (spawn, `/tp`). O cliente adota o `seq` novo e o servidor ignora posições antigas |
| `s_snapshot(PackedFloat32Array)` | 8 floats por entidade: id, espécie, crescimento, x, y, z, yaw, flags (morto, correndo, descansando, comendo, jogador, mancando, nadando, andando) |
| `s_self_stats(PackedFloat32Array)` | vida, vida máx., comida, água, fôlego, crescimento, vel. andar/correr, interação, descansando, tempo do mundo |
| `s_roster(dict)` | id → nome dos jogadores online |
| `s_event(tipo, a, b, valor, texto)` | golpe começou, golpe acertou (parte, dano), morte |
| `s_died(causa)`, `s_message(texto)` | morte do próprio jogador; mensagens/chat |

## Hitbox

Cada espécie tem esferas (tronco, peito, pescoço, cabeça, cauda, pernas) em `species.gd`.
O golpe é um segmento vertical saindo da boca/chifre (`attack_point`), descendo até
`attack_reach_down`, pra um bicho grande conseguir morder um pequeno no chão. Acerta se o
segmento (com raio) encostar em alguma esfera do alvo, no fim da preparação do golpe
(`attack_windup`). A parte atingida muda o dano.

## Save (`world.json`)

`format`, `version`, `seed`, `world_time`, `next_id`, `bots[]`, `carcasses[]`, `bush_food[]`,
`players{nome: {alive, dino}}`, `respawn_queue[]`. Os jogadores conectados são gravados
como estão naquele instante; quem está offline fica congelado no registro.
