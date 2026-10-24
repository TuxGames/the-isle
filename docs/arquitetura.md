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
- Simulação por distância (`WorldSim._update_sim_tiers`, valores em `config.gd`): cada bot
  roda todo passo, passo sim passo não (com o tempo somado) ou fica congelado, conforme o
  jogador mais próximo. Congelado fica fora do `_grid` e o `get_dino` devolve null pra ele:
  pros outros bichos ele não existe.
- `WorldSim.step`: faixas por distância → IA dos bots (só os que rodam neste passo) → separação dos corpos → metabolismo → comer/beber →
  golpes pendentes → mortes → carcaças → arbustos → reposição de bots → diretor de população.
- Diretor de população (`sim/population_director.gd`, valores em `config.gd`): agrupa os
  jogadores, conta os bots na área de cada grupo e decide onde e qual espécie nasce na
  reposição (`WorldSim.spawn_bot`). A cada 5 s muda de lugar alguns bots congelados longe de
  todos pra área com falta de bots. Sem jogador no mundo não faz nada.

## Protocolo (scripts/net/net.gd)

Cliente → servidor:

| RPC | Modo | Conteúdo |
|---|---|---|
| `c_password(chave)` | confiável | chave da senha (`Accounts.client_key`), mandada logo antes do `c_login` |
| `c_login(nome, espécie, versão)` | confiável | espécie só vale se não houver dino vivo salvo. Nunca muda de assinatura: um jogo de outra versão ainda recebe "versão diferente" |
| `c_set_password(chave atual, chave nova)` | confiável | troca de senha; a resposta vem por `s_message` |
| `c_state(seq, pos, yaw, flags)` | não confiável, 20 Hz | flags: correndo, andando |
| `c_action(ação, texto)` | confiável | atacar, começar/parar de comer, descansar, renascer, comando dev, chat |

Servidor → cliente:

| RPC | Conteúdo |
|---|---|
| `s_welcome(info)` | id da entidade, nome (como foi cadastrado), se a conta acabou de ser criada, espécie, semente e tamanho do mapa (`map_size`), se foi restaurado, modo dev |
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

## Contas (`<save>.contas.json`)

`scripts/net/accounts.gd`. Nome (sem diferença de maiúsculas) → nome como foi cadastrado, sal
aleatório e hash (PBKDF2-SHA256) da chave que o cliente manda. O cliente gera a chave com
PBKDF2 da senha, usando o nome como sal; com "Lembrar a senha", guarda só essa chave em
`user://cliente.cfg`. Fica fora do `world.json` pra trocar de mapa não apagar as senhas. Se o
arquivo estiver ilegível, o servidor não sobe (não pode virar "ninguém tem senha").

## Save (`world.json`)

`format`, `version`, `seed`, `map_size`, `world_time`, `next_id`, `bots[]`, `carcasses[]`, `bush_food[]`,
`players{nome: {alive, dino}}`, `respawn_queue[]`. Os jogadores conectados são gravados
como estão naquele instante; quem está offline fica congelado no registro.

- Formato 2 (v0.2) grava `map_size`; o formato 1 (v0.1) não tinha e é lido como 512 m.
- Tamanho do mapa ao subir o servidor: o de `--map-size`; senão o do save; senão 512 m.
- Save de outro mapa (semente ou tamanho diferente) não é sobrescrito: o servidor guarda ele
  como `world.outro-mapa-<hora>.json` e começa um mundo novo (`WorldSim.save_mismatch`).

## Mapa e terreno

- `Terrain.get_shared(semente, tamanho)` gera o mesmo terreno no servidor e nos clientes. Com
  512 m é idêntico ao da v0.1. Gerar leva ~0,03 s (512 m), ~0,5 s (2048 m), ~1,4 s (4096 m).
- O cliente (`TerrainView`) desenha pedaços de 128 m só num raio de ~1150 m em volta do
  jogador, com 4 níveis de detalhe (vértice a cada 2, 4, 8 e 16 m; arbustos até 448 m) e
  histerese. Monta poucos por quadro (4 ms), mas o pedaço embaixo do jogador sai na hora.
  `TerrainView.wanted_chunks` é a função pura que decide o que carregar (testada sem tela).
