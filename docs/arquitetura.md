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
| `scripts/sim/` | Lógica do mundo: `Dino`, `Metabolism`, `Injuries`, `Combat`, `Movement`, `BotBrain`, `Nests`, `WorldSim` | data, world |
| `scripts/net/` | `net.gd` (autoload `Net`, **todas** as RPCs) e `GameServer` | sim |
| `scripts/client/` | `GameClient`, `DinoView`, `TerrainView`, `ScentView`, `NestView` | sim (só leitura), net |
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
- Saída do jogador: `WorldSim.request_logout`. Se ele levou golpe nos últimos
  `COMBAT_LOGOUT_S`, o dino fica em `WorldSim.lingering` (parado, vulnerável) e sai sozinho
  depois; se o jogador voltar antes, `login_player` devolve o mesmo dino.
- Save de outro mapa (semente ou tamanho): o servidor guarda o antigo à parte, cria o mundo
  novo e chama `WorldSim.adopt_players`, que traz os registros dos jogadores marcados com
  `relocate` (no login o dino ganha um lugar novo no mapa).
- Simulação por distância (`WorldSim._update_sim_tiers`, valores em `config.gd`): cada bot
  roda todo passo, passo sim passo não (com o tempo somado) ou fica congelado, conforme o
  jogador mais próximo. Congelado fica fora do `_grid` e o `get_dino` devolve null pra ele:
  pros outros bichos ele não existe.
- `WorldSim.step`: faixas por distância → IA dos bots (só os que rodam neste passo) → separação dos corpos → metabolismo → comer/beber →
  golpes pendentes → mortes → carcaças → arbustos → reposição de bots → ninhos (construção, pedidos,
  choco) → diretor de população →
  saída de quem estava em briga → pegadas do faro.
- Ferimentos (`sim/injuries.gd`, valores em `config.gd`): cada golpe que acerta passa por
  `Injuries.from_hit`, que abre sangramento, fratura ou mordida funda em `dino.injuries`
  (tipo → segundos que faltam). Os tempos andam em `Metabolism.step` (só com o dino ativo, então
  congelam com quem sai); a fratura entra em `Movement.speeds` (vale pros bots e chega no
  cliente pelo `ST_WALK`/`ST_SPRINT`) e a mordida funda e o sangramento cortam a cura.
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
| `c_set_password(chave atual, chave nova)` | confiável | troca de senha; a resposta vem por `s_password_changed` |
| `c_redeem_code(código)` | confiável | resgata um código (aba Conta); resposta por `s_redeem_result` |
| `c_staff_create_code(recompensa, parâmetro, usos, dias)` | confiável | só admin; resposta por `s_staff_codes` |
| `c_staff_list_codes()`, `c_staff_revoke_code(código)` | confiável | só admin; resposta por `s_staff_codes` |
| `c_sniff()` | confiável | faro (tecla F); resposta por `s_scent` |
| `c_mate()` | confiável | parceiro (tecla R): pede a postura no próprio ninho ou aceita o pedido de outro jogador; respostas por `s_message`/`s_nests` |
| `c_nest(segurando)` | confiável | ninho (tecla N): `true` ao apertar, `false` ao soltar; o servidor conta os 8 s parado |

RPC nova sempre com nome que vem **depois** de `c_login` (e `s_login_failed`) em ordem alfabética,
declarada no fim da seção: assim o `c_login` não muda de posição e um jogo de outra versão ainda
recebe "versão diferente".
| `c_state(seq, pos, yaw, flags)` | não confiável, 20 Hz | flags: correndo, andando |
| `c_action(ação, texto)` | confiável | atacar, começar/parar de comer, descansar, renascer (texto = espécie, ou `"nest"` pra nascer no próprio ninho), comando dev, chat |

Servidor → cliente:

| RPC | Conteúdo |
|---|---|
| `s_welcome(info)` | id da entidade, nome (como foi cadastrado), se a conta acabou de ser criada, espécie, semente e tamanho do mapa (`map_size`), se foi restaurado, modo dev |
| `s_login_failed(motivo)` | versão diferente, nome em uso, servidor cheio |
| `s_teleport(seq, pos, yaw)` | posição forçada (spawn, `/tp`). O cliente adota o `seq` novo e o servidor ignora posições antigas |
| `s_snapshot(PackedFloat32Array)` | 8 floats por entidade: id, espécie, crescimento, x, y, z, yaw, flags (morto, correndo, descansando, comendo, jogador, mancando (vida baixa ou osso quebrado), nadando, andando) |
| `s_self_stats(PackedFloat32Array)` | vida, vida máx., comida, água, fôlego, crescimento, vel. andar/correr (já com a fratura), interação, descansando, tempo do mundo, segundos de boost de crescimento, segundos que faltam de sangramento, fratura e mordida funda (`ST_BLEED`, `ST_FRACTURE`, `ST_DEEP`; 0 = não tem); reprodução (15 a 21): ovos no meu ninho (-1 = sem ninho), ovo pronto pra mim, segundos até chocar, recarga da postura, progresso do ninho segurando N (-1 = não está fazendo), segundos pra aceitar um pedido de parceiro e o id de quem pediu (`ST_NEST_EGGS` … `ST_MATE_FROM`) |
| `s_roster(dict)` | id → nome dos jogadores online |
| `s_event(tipo, a, b, valor, texto)` | golpe começou, golpe acertou (parte, dano), morte |
| `s_died(causa)`, `s_message(texto)` | morte do próprio jogador; mensagens/chat |
| `s_password_changed(ok, texto)` | resposta da troca de senha (o cliente atualiza a senha lembrada) |
| `s_redeem_result(ok, texto, perks)` | resposta do resgate, com o que a conta tem agora (`beta`, `species`) |
| `s_staff_codes(lista, criado, texto)` | resposta das ações de admin: lista de códigos, o código recém-criado e uma mensagem |
| `s_scent(ok, PackedFloat32Array, recarga)` | resposta do faro: `ok` false = ainda em recarga; 5 floats por item (x, z, idade, espécie, tipo: pegada ou carcaça); segundos até poder de novo |
| `s_nests(lista, meu)` | ninhos, mandado no login e quando algo muda: lista de `{id, pos, sp (índice da espécie), owner, eggs (vagas com ovo), ready (vagas com o ovo pronto pro dono)}` e o ninho de quem recebe (`has_nest`, `eggs`, `ready`, `species`: o botão "Nascer no ninho") |

## Reprodução (`scripts/sim/nests.gd`)

`Nests`, dentro do `WorldSim` (`sim.nests`), números em `config.gd` (seção "Reprodução") e
`clutch`/`egg_kg` em `species.gd`. Guarda os ninhos (`nests`: dono, espécie, posição, ovos em
vagas fixas em volta do centro, `hatch_at` em tempo de mundo), a recarga da postura por jogador
(`lay_ready`) e, só na memória, a recarga dos bots parceiros, os pedidos entre jogadores, quem está
segurando N e quem está comendo ovo.

- `set_building` (N) e `step`: 8 s parado → `build`. `press_mate` (R): aceita o pedido que
  chegou ou procura parceiro (`partners_near`); bot responde na hora (`bot_refusal`), jogador
  recebe o pedido (`requests`, 15 s). A postura (`lay`) põe `clutch` ovos e marca a recarga.
- `step` → `_step_hatching`: no `hatch_at` o primeiro ovo do dono fica `ready` e os outros viram
  bots filhotes (`hatch_bot`) enquanto houver vaga até `BOT_MAX`. `respawn_in_nest` usa o ovo
  pronto (Action.RESPAWN com `"nest"`).
- Ovo comido: `WorldSim._interact` pergunta `egg_in_reach` (só carnívoro) e chama `eat_egg`
  (3 s segurando E). O bot carnívoro com fome usa o estado `eat_egg` do `BotBrain`.
- Bots: `WorldSim._process_respawns` chama `try_bot_nest`; 25% das reposições (com jogador no
  mundo) viram ninho de bot no lugar que o diretor de população escolheria. Ninho de bot com
  ovos conta como um bot (`bot_slots`) pra reposição não encher em dobro.
- O servidor só repassa: `_flush_nests` manda os avisos (`messages`) e, se `dirty`, o `s_nests`
  pra todos. `NestView` (cliente) desenha anel e ovos.

## Faro (`scripts/sim/scent.gd`)

`ScentTrail`, dentro do `WorldSim`: no fim de cada passo, quem andou `SCENT_SPACING_M` desde a
última pegada deixa outra (posição, `world_time`, espécie, id). Bot congelado e morto não deixam;
pulo maior que `SCENT_TELEPORT_M` num passo é teleporte e não deixa. Vale tudo em tempo de mundo,
então com o mundo parado nada envelhece. Guarda no máximo `SCENT_MAX_PRINTS` (as mais velhas saem
antes) e não vai pro save. `WorldSim.sniff(dino)` confere a recarga (por nome de jogador) e devolve
as pegadas dos outros e as carcaças com carne no `smell_radius` da espécie. No cliente,
`ScentView` desenha tudo numa MultiMesh só e apaga sozinho depois de `SNIFF_SHOW_S`.

## Hitbox

Cada espécie tem esferas (tronco, peito, pescoço, cabeça, cauda, pernas) em `species.gd`.
O golpe é um segmento vertical saindo da boca/chifre (`attack_point`), descendo até
`attack_reach_down`, pra um bicho grande conseguir morder um pequeno no chão. Acerta se o
segmento (com raio) encostar em alguma esfera do alvo, no fim da preparação do golpe
(`attack_windup`). A parte atingida muda o dano.

## Aviso de versão nova (`scripts/client/update_check.gd`)

No menu inicial o cliente pede `GameConfig.RELEASES_API` (última Release do GitHub) e, se a tag
for mais nova que `GameConfig.VERSION`, mostra "Versão nova disponível" com o botão "Baixar".
Qualquer falha (sem internet, GitHub fora) fica quieta. `--fake-latest=vX.Y.Z` finge uma versão
nova (prints).

## Configurações do jogador (`user://configuracoes.cfg`)

`scripts/client/settings.gd` guarda e confere as opções; `scripts/ui/settings_panel.gd` é a tela
(menu e Esc); o `GameClient` aplica (janela, câmera, `TerrainView.set_view_distance`/`set_shadows`,
sensibilidade). Nada disso vai pro servidor, menos a troca de senha da aba Conta.

## Contas (`<save>.contas.json`)

`scripts/net/accounts.gd`. Nome (sem diferença de maiúsculas) → nome como foi cadastrado, sal
aleatório e hash (PBKDF2-SHA256) da chave que o cliente manda. O cliente gera a chave com
PBKDF2 da senha, usando o nome como sal; com "Lembrar a senha", guarda só essa chave em
`user://cliente.cfg`. Fica fora do `world.json` pra trocar de mapa não apagar as senhas. Se o
arquivo estiver ilegível, o servidor não sobe (não pode virar "ninguém tem senha").

Formato 2: cada conta tem `perks` (o que ganhou com códigos): `beta`, `species` (liberadas) e
`codes` (já usados). Arquivo do formato 1 carrega igual, com `perks` vazio.

## Códigos de resgate (`<save>.codigos.json`)

`scripts/net/codes.gd` (`RedeemCodes`): gera (`DINO-XXXX-XXXX` com `Crypto`), confere (existe,
cancelado, vencido, usos, já usado por essa conta, 5 erros por minuto) e gasta. O que cada código
dá fica em `scripts/sim/rewards.gd` (`Rewards`): uma entrada em `TYPES` + um caso em `validate`,
`describe` e `apply` pra criar outra. O `GameServer` junta os três (códigos, contas e mundo),
confere quem é admin (`--admins`, padrão `GameConfig.DEFAULT_ADMINS`) e grava os arquivos.
A escolha de espécie (login novo e renascer) passa por `Species.choice_error`: espécie `locked`
precisa ter sido liberada; `beta` precisa de acesso beta. Arquivo ilegível: o servidor não sobe.

## Save (`world.json`)

`format`, `version`, `seed`, `map_size`, `world_time`, `next_id`, `bots[]`, `carcasses[]`, `nests{}`, `bush_food[]`,
`players{nome: {alive, dino}}`, `respawn_queue[]`. Os jogadores conectados são gravados
como estão naquele instante; quem está offline fica congelado no registro.

- Formato 2 (v0.2) grava `map_size`; o formato 1 (v0.1) não tinha e é lido como 512 m.
- Formato 3: os dinos têm `growth_boost_s` (boost de crescimento que falta); antes valia 0.
  Quem morre leva o boost pro próximo dino (o registro de morto guarda o campo).
- Formato 4 (v0.3): os dinos têm `injuries` ({"sangramento"/"fratura"/"mordida_funda": segundos
  que faltam}); save antigo carrega sem ferimentos. Morrer zera os ferimentos.
- Formato 5 (v0.4): `nests` = `{list: [{id, owner, species, pos, eggs: [{slot, ready}], hatch_at,
  laid, bot_slot}], lay_ready: {nome: world_time}}` (`Nests.to_save`). Save do formato 4 carrega
  sem ninhos e sem recarga; os dinos vêm iguais. Trocar de mapa (`adopt_players`) não leva os
  ninhos (eles são do lugar), só os dinos.
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
