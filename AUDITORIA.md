# Auditoria de segurança, qualidade e eficiência

- **Projeto:** Dino Survival (`TuxGames/the-isle`), versão 0.5.0
- **Commit auditado:** `9a1ca4d` (todas as referências `arquivo:linha` valem para ele)
- **Data:** 09/11/2026
- **Modo:** somente leitura. Nenhum código, config ou dependência foi alterado; o único arquivo criado é este.
- **Como foi verificado:** leitura integral de `scripts/` (34 arquivos, 9.784 linhas), `tools/`, `.github/` e `docs/`, leitura dirigida de `tests/`, e conferência de comportamentos da engine no código-fonte do Godot na tag `4.7.2-stable` (só leitura). **Nada foi executado**: o Godot não está instalado neste ambiente (ver seção 6).

## 0. Contexto e modelo de ameaça

| Item | O que é |
|---|---|
| Stack | Godot 4.7.2, GDScript, multiplayer de alto nível sobre ENet (UDP 7777), servidor dedicado autoritativo |
| Entrada | `scenes/main.tscn` → `scripts/main.gd`: `--server`/headless, `--test-client`, `--bench` ou cliente com menu |
| "Endpoints" | 12 RPCs cliente → servidor, todas em `scripts/net/net.gd`: `c_login`, `c_password`, `c_set_password`, `c_state`, `c_action` (atacar, comer, descansar, renascer, comando dev, chat), `c_redeem_code`, `c_staff_create_code`, `c_staff_list_codes`, `c_staff_revoke_code`, `c_sniff`, `c_mate`, `c_nest` |
| Dados | Sem banco. No servidor: `world.json` (mundo e dinos dos jogadores), `world.contas.json` (nome, sal, hash, perks), `world.codigos.json`. No cliente: `cliente.cfg` (nome, endereço, chave da senha) e `configuracoes.cfg` |
| Integração externa | Só uma: `api.github.com` (aviso de versão nova) |
| Dependências | Nenhuma de terceiros (sem addons, sem gerenciador de pacotes) |
| Deploy | `tools/export.sh` + `.github/workflows/release.yml` geram o zip do Windows em Releases; o servidor é o `iniciar_servidor.bat` num notebook, alcançado por Tailscale |
| Testes | `tools/test.sh`: compilação, 149 funções de teste de unidade e um teste de rede de ponta a ponta; a CI roda a cada push |

O projeto declara que é um jogo entre até 5 amigos, sem anticheat, com o movimento do próprio dino calculado no cliente. Respeitei essa decisão: trapaça de movimento aparece como risco aceito (S-09), não como falha. Considerei três atores:

1. **Jogador autenticado com cliente modificado.** O código do cliente é este repositório, então modificar é trivial.
2. **Qualquer máquina que alcance a porta UDP.** O servidor escuta em todas as interfaces (S-07), então isso inclui a rede local, não só o tailnet. Criar conta é livre (S-03), logo "não autenticado" vira "autenticado" com um pacote.
3. **Falhas operacionais** no notebook: queda de energia, disco cheio, janela fechada no meio de um save.

A escala de severidade foi calibrada pela regra do próprio projeto ("os amigos não podem perder o dino"): **alta** = perda ou corrupção persistente do mundo ou dos dinos, ou qualquer jogador conseguir quebrar o servidor de forma que sobrevive a um reinício; **média** = indisponibilidade ou escalada de privilégio limitada; **baixa** = endurecimento. Não há achado crítico: nada aqui dá execução de código, vazamento de senha em claro ou acesso à máquina.

## 1. Resumo executivo

| Eixo | Nota | Justificativa |
|---|---|---|
| Segurança | **5/10** | A base é boa: toda RPC confere se o peer está logado, as de admin conferem o papel, a senha nunca trafega, o hash tem sal e comparação em tempo constante, os códigos saem de CSPRNG. O que derruba a nota é a falta de validação do que chega pela rede (um `NaN` quebra o servidor inteiro), o modo dev ligado no pacote distribuído, admin definido por um nome que qualquer um pode registrar primeiro, e ausência de limite de taxa e de prazo para login. |
| Qualidade | **7/10** | Arquitetura limpa (simulação sem rede nem tela), documentação acima da média, 149 testes de unidade mais um teste de rede real, CI verde no commit auditado. Perde pontos na robustez do save (arquivo ilegível é sobrescrito, gravação não é atômica no Windows, sem backup), num executor de testes que conta erro de script como "ok", e em documentação defasada. |
| Eficiência | **7/10** | Simulação por distância, grade espacial para os dinos, terreno em pedaços com nível de detalhe e uma ferramenta de benchmark própria. Os pontos fracos são a busca de arbustos que varre o mapa inteiro a cada passo (a grade pronta não é usada no servidor), o snapshot global sem área de interesse e o cliente sem compartilhamento de malhas. |

### Os 5 maiores riscos

1. **S-01: uma posição `NaN` em `c_state` contamina todos os jogadores online e vai para o save.** O cliente oficial dos outros jogadores propaga o valor inválido para a própria posição no quadro seguinte. Sem `--dev` não há como consertar pelo jogo; os dinos atingidos não conseguem comer nem beber.
2. **Q-01 e Q-02: o save do mundo é o único arquivo que, se ficar ilegível, é trocado por um mundo novo e sobrescrito**, inclusive no encerramento limpo do servidor. A gravação ignora erro de escrita e, no Windows, apaga o arquivo antigo antes de mover o novo. Não existe backup.
3. **S-02: o `iniciar_servidor.bat` distribuído liga o modo dev, e os comandos dev não conferem admin nem limites.** Qualquer jogador trava o relógio do mundo para sempre com `/time +1e300`, cria bots sem teto (eles vão para o save) ou vira adulto na hora.
4. **S-03, S-04 e S-05: identidade e disponibilidade do login.** Admin é quem registrar primeiro o nome "Tux" ou "Marcelo"; qualquer um tranca a conta de outro mandando 5 senhas erradas por minuto; 8 conexões que nunca fazem login esgotam as vagas do servidor.
5. **E-01 e E-02: custos que crescem com a área do mapa e com a população.** A busca de arbustos e o snapshot global estão dentro do orçamento em 2 km com 70 bots (segundo o README), mas escalam mal e o snapshot já passa do tamanho de um pacote UDP.

## 2. Tabela de achados

| ID | Eixo | Severidade | Confiança | Local | Título |
|---|---|---|---|---|---|
| S-01 | Segurança | alta | média | `scripts/net/game_server.gd:403-418` | `c_state` aceita `NaN`: contamina jogadores, bots e o save |
| S-02 | Segurança | alta | alta | `tools/windows/iniciar_servidor.bat:12`, `scripts/net/game_server.gd:477-558` | Modo dev ligado por padrão, sem checagem de admin nem limites |
| S-03 | Segurança | média | alta | `scripts/net/accounts.gd:83-85`, `scripts/config.gd:206` | Admin e contas por nome de quem chegar primeiro; criação ilimitada |
| S-04 | Segurança | média | alta | `scripts/net/accounts.gd:77-90` | Bloqueio por nome permite trancar a conta de outro; força bruta viável |
| S-05 | Segurança | média | alta | `scripts/net/game_server.gd:77`, `131-132` | Conexão sem login nunca expira: 8 conexões esgotam o servidor |
| S-06 | Segurança | média | alta | `scripts/net/game_server.gd:164-170`, `446-449` | RPCs sem limite de taxa, de tamanho nem filtro de caracteres |
| S-07 | Segurança | baixa | alta | `scripts/net/net.gd:252-258`, `scripts/net/game_server.gd:76-81` | Transporte sem criptografia, chave reutilizável, escuta em todas as interfaces |
| S-08 | Segurança | baixa | alta | `scripts/ui/hud.gd:589-601`, `scripts/net/accounts.gd:23-24` | Chave equivalente à senha em texto puro no cliente; derivação fraca |
| S-09 | Segurança | baixa | alta | `scripts/net/game_server.gd:403-418` | Movimento sem nenhuma conferência (risco aceito pelo projeto) |
| S-10 | Segurança | baixa | média | `.github/workflows/release.yml:14-15`, `71-93` | Cadeia de build: binários sem checagem de hash, token de escrita amplo |
| S-11 | Segurança | baixa | alta | `scripts/net/game_server.gd:283`, `298`, `338` | Códigos de resgate ficam em claro no log do servidor |
| Q-01 | Qualidade | alta | alta | `scripts/net/game_server.gd:43-65`, `790-797`, `811-814` | Save ilegível ou ausente vira mundo novo e o original é sobrescrito |
| Q-02 | Qualidade | média | alta | `scripts/net/game_server.gd:741-752` | Gravação não atômica no Windows, erro de escrita ignorado, sem backup |
| Q-03 | Qualidade | média | alta | `tests/run_tests.gd:32-38`, `tools/test.sh:8-9` | Teste de unidade que quebra com erro de script conta como "ok" |
| Q-04 | Qualidade | média | média | `scripts/sim/world_sim.gd:784-812` | `load_save` não valida: um registro ruim aborta antes de carregar os jogadores |
| Q-05 | Qualidade | baixa | alta | `scripts/net/game_server.gd:173-179` | Sessão fantasma: o dono com a senha certa fica barrado pelo próprio nome |
| Q-06 | Qualidade | baixa | alta | `scripts/net/game_server.gd:86`, `109-117` | Snapshot oscila entre 10 e 15 Hz por causa do acumulador zerado |
| Q-07 | Qualidade | baixa | alta | vários | Documentação defasada, código morto, funções longas |
| E-01 | Eficiência | média | alta | `scripts/sim/world_sim.gd:199-224`, `scripts/sim/bot_brain.gd:278-279` | Busca de arbusto varre todos os arbustos a cada passo |
| E-02 | Eficiência | média | alta | `scripts/net/game_server.gd:645-688` | Snapshot global sem área de interesse, acima do tamanho de um pacote |
| E-03 | Eficiência | baixa | alta | `scripts/net/game_server.gd:736-737` | Save completo e síncrono em toda saída, morte, renascimento e resgate |
| E-04 | Eficiência | baixa | média | `scripts/client/dino_view.gd:157-205` | Cliente cria malhas e materiais exclusivos para cada dino do mapa |
| E-05 | Eficiência | baixa | alta | `scripts/sim/world_sim.gd:465-469`, `scripts/world/terrain.gd:80-118` | Rebrota percorre todos os arbustos 20 vezes por segundo; terreno gerado na thread principal |
| E-06 | Eficiência | baixa | alta | `tools/check.sh:13-20`, `tools/test.sh:8-9` | CI abre um Godot por arquivo e roda os testes de unidade duas vezes |

## 3. Detalhe dos achados

### Segurança

#### S-01: `c_state` aceita `NaN`: contamina jogadores, bots e o save

- **Severidade:** alta · **Confiança:** média (cadeia confirmada por leitura do projeto e da engine; não executada)
- **Local:** `scripts/net/game_server.gd:403-418`, `scripts/world/terrain.gd:191-192`, `scripts/client/game_client.gd:706-722`, `scripts/sim/bot_brain.gd:345-350`

```gdscript
# game_server.gd:410-418
var p := sim.terrain.clamp_to_play_area(pos)
p.y = Movement.ground_y(sim.terrain, p.x, p.z, d.body_height(), sim.water_level)
...
d.pos = p
d.yaw = wrapf(yaw, -PI, PI)
```

- **Problema:** não há nenhuma conferência de que `pos` e `yaw` são números finitos. `clamp_to_play_area` usa `clampf`, e o `CLAMP` do Godot devolve `NaN` quando recebe `NaN` (`core/typedefs.h:152-154`: `m_a < m_min ? m_min : (m_a > m_max ? m_max : m_a)`, e toda comparação com `NaN` é falsa). Infinito é contido pelo clamp; `NaN` não.
- **Cenário:** um jogador logado manda `c_state(seq, Vector3(NAN, 0, NAN), 0, 0)` com um cliente modificado. A partir daí:
  1. O servidor guarda `d.pos` com `NaN` e o próximo snapshot leva o valor para todos (`build_snapshot`, linha 665).
  2. No cliente **oficial** de cada outro jogador, `_push_out_of_others` calcula `dist` como `NaN`; as duas condições de saída (`dist >= r or dist < 0.001`) são falsas, então `my_pos.x += push.x` soma `NaN` na posição do próprio jogador. Esse cliente passa a mandar `NaN` no próximo `c_state`, e o servidor guarda. Um pacote basta para atingir todos os jogadores vivos online.
  3. Todo bot que estiver caçando, brigando ou fugindo de um dino com `NaN` também é contaminado em `BotBrain._steer` (`v` vira `NaN` e `b.pos += b.forward() * v * dt`).
  4. No save seguinte (até 30 s), o `JSON.stringify` do Godot 4.7.2 grava `NaN` como `null` (`core/io/json.cpp:79-88`), então a posição corrompida persiste.
- **Impacto:** todos os dinos atingidos ficam sem conseguir comer nem beber (as buscas por distância falham com `NaN`) e a câmera dos jogadores quebra. Reentrar não resolve, porque o registro salvo tem a posição inválida. Com `--dev` ligado, `/tp` conserta um jogador, mas ele é recontaminado no quadro seguinte se ainda houver outro dino com `NaN` no mundo. Na prática o conserto é parar o servidor e editar o `world.json` à mão; sem isso os dinos morrem de fome e recomeçam jovens, que é exatamente o que o projeto diz que não pode acontecer.
- **O que é HIPÓTESE:** (a) dentro de `Terrain.height_at`, `int(NaN)` é comportamento indefinido em C++; em x86-64 minha análise indica índice válido e nenhum erro, mas não rodei. Num servidor exportado (release) a checagem de índice é compilada fora, então o valor é guardado de qualquer forma. (b) O que acontece ao recarregar `null`: ver Q-04.
- **Correção sugerida:** recusar na entrada e blindar os pontos de propagação.

```gdscript
# game_server.gd, início de on_state
if not (pos.is_finite() and is_finite(yaw)):
    return
```

  No cliente, ignorar entidades com posição não finita em `_on_snapshot` e em `_push_out_of_others`. Em `Dino.from_dict`, trocar posição inválida por um ponto de nascimento em vez de aceitar. Acrescentar um teste de unidade e uma etapa no teste de rede que mandem `NaN`.

#### S-02: modo dev ligado por padrão, sem checagem de admin nem limites

- **Severidade:** alta · **Confiança:** alta
- **Local:** `tools/windows/iniciar_servidor.bat:12`, `scripts/net/game_server.gd:477-558`, `scripts/sim/climate.gd:652-659` e `683-691`

```bat
DinoSurvival.console.exe --headless -- --server --port=7777 --bots=70 --map-size=2048 --dev "--save=..."
```

```gdscript
# game_server.gd:478 (única condição para todos os comandos)
if not dev_mode:
# climate.gd:657-658 (/time +N, sem teto)
if num.is_valid_float() and num.to_float() > 0.0:
    return num.to_float() * float(units[suffix])
# game_server.gd:546 (/spawn, sem conferir BOT_MAX)
var b := sim.spawn_bot(sp_id, clampf(g, 0.0, 1.0))
```

- **Problema:** o servidor que vai no zip dos amigos sobe com `--dev`, e `_dev_command` não chama `is_admin`. Qualquer conta usa todos os comandos pelo chat do cliente oficial. É uma escolha consciente do protótipo (o LEIA-ME documenta os comandos), mas três deles têm efeito global, persistente e sem volta.
- **Cenário e impacto:**
  - `/time +1e300`: `world_time` vira 3,6e303 e `world_time += dt` deixa de alterar o valor. O relógio do mundo para de vez: dia, estação, incubação, recargas e validade das carcaças deixam de funcionar como projetado. O valor vai para o save e `/time` só anda para a frente, então o conserto é editar o `world.json` à mão.
  - `/spawn` repetido por um cliente com script: cada chamada cria um bot, sem teto. O custo da simulação e o tamanho do snapshot crescem até o servidor travar, e como os bots vão para o save e `load_save` carrega todos (`world_sim.gd:788-794`), o servidor continua travado depois de reiniciar.
  - `/grow 1`: adulto instantâneo, o que `scripts/sim/rewards.gd:6-7` diz que não deve existir.
- **Correção sugerida:** tirar `--dev` do `iniciar_servidor.bat` (pode existir um `iniciar_servidor_teste.bat` à parte). Mesmo em dev, exigir `is_admin` para os comandos de efeito global (`/time`, `/weather`, `/spawn`, `/hatch todos`, `/raio`). Limitar o salto de `/time` (por exemplo, um ano de mundo) e recusar valor não finito; limitar `/spawn` a `BOT_MAX`.

#### S-03: admin e contas por nome de quem chegar primeiro; criação ilimitada

- **Severidade:** média · **Confiança:** alta
- **Local:** `scripts/net/accounts.gd:83-85`, `scripts/config.gd:206`, `scripts/net/game_server.gd:71-74`, `179-183`, `252-253`

```gdscript
# accounts.gd:83-85
if not accounts.has(n):
    accounts[n] = _new_record(player_name.strip_edges(), key, now)
    return Result.CREATED
# config.gd:206
const DEFAULT_ADMINS := ["Tux", "Marcelo"]
```

- **Problema:** ser admin é ter o nome "Tux" ou "Marcelo", e um nome pertence a quem entrar primeiro com ele. Além disso não há teto nem intervalo para criar contas: cada login com nome novo grava uma conta em `contas.json` e um registro em `world.json`, que nunca são removidos.
- **Cenário:** num servidor novo (ou com caminho de save novo, já que as contas ficam ao lado do save), quem alcançar a porta antes do Marcelo entra como "Marcelo", define a senha e passa a ser admin: cria códigos de boost de até 600 minutos com 100 usos, libera espécies, cancela códigos dos outros. Também dá para registrar antes os nomes dos amigos que ainda não entraram. Um script que conecta, cria conta e sai em laço faz os dois arquivos crescerem sem limite, e o save completo é regravado a cada saída (E-03).
- **Detalhe latente:** em `on_login` a conta é criada e gravada (linhas 180-183) antes da conferência de espécie (192-193). Hoje nenhuma espécie é trancada, então o caminho não é alcançável; quando for, um login recusado deixará a conta criada.
- **Correção sugerida:** exigir um código de entrada do servidor (`--join-code=...`) para criar conta, ou um modo fechado depois que os amigos se registrarem. Guardar o papel de admin no registro da conta em vez de derivar do nome, e reservar os nomes de admin. Limitar o total de contas e a criação por endereço. Mover a criação para depois de todas as conferências.

#### S-04: bloqueio por nome permite trancar a conta de outro; força bruta viável

- **Severidade:** média · **Confiança:** alta
- **Local:** `scripts/net/accounts.gd:21`, `26-27`, `77-90`, `183-189`

```gdscript
if lock_seconds_left(n, now) > 0.0:
    return Result.LOCKED          # antes de conferir a chave
```

- **Problema:** as tentativas erradas são contadas por nome, não por origem, e o bloqueio é conferido antes da chave. Enquanto o nome está bloqueado, o dono com a senha certa também é recusado.
- **Cenário:** uma conexão manda 5 pares `c_password` + `c_login` errados para "Tux" (cabem no 1 s antes do servidor desconectar) e repete a cada 60 s. O Tux não entra mais. No sentido inverso, o limite permite 7.200 tentativas por dia por nome, e a senha mínima é de 4 caracteres sem regra de composição: uma senha de 4 dígitos cai em menos de dois dias.
- **Correção sugerida:** contar por nome e endereço (`multiplayer.multiplayer_peer.get_peer(id).get_remote_address()`), com atraso crescente só para a origem que errou. Subir `MIN_PASSWORD` para 8. Avisar o dono, no login seguinte, de que houve tentativas erradas.

#### S-05: conexão sem login nunca expira

- **Severidade:** média · **Confiança:** alta
- **Local:** `scripts/net/game_server.gd:77`, `131-132`

```gdscript
var err := peer.create_server(port, GameConfig.MAX_PLAYERS + 3)   # 8 vagas
func _on_peer_connected(id: int) -> void:
    _log("conexão nova (peer %d), aguardando login" % id)         # e mais nada
```

- **Problema:** o servidor só derruba um peer depois de um login recusado. Quem conecta e nunca manda `c_login` fica para sempre.
- **Cenário:** 8 conexões ENet ociosas ocupam todas as vagas; ninguém mais conecta. Como nenhuma delas está logada, o mundo ainda fica pausado.
- **Correção sugerida:** em `_on_peer_connected`, um timer de 5 a 10 s que desconecta o peer se ele ainda não estiver em `peers`. A alternativa nativa é `SceneMultiplayer.auth_callback` com `auth_timeout`, que autentica antes de o peer contar como conectado.

#### S-06: RPCs sem limite de taxa, de tamanho nem filtro de caracteres

- **Severidade:** média · **Confiança:** alta
- **Local:** `scripts/net/game_server.gd:164`, `169-170`, `196`, `446-449`; `scripts/net/accounts.gd:42-43`

```gdscript
reason = "Versão diferente: o servidor está na %s e o seu jogo na %s." % [GameConfig.VERSION, version]
...
_log("login recusado (peer %d, \"%s\"): %s" % [peer_id, player_name, reason])
```

- **Problema e cenários:**
  - **Chat sem limite de taxa.** Cada `c_action(CHAT)` vira uma RPC confiável para todos. Um cliente que manda milhares por segundo enche a fila de todos; cada mensagem cria um `Label` e um `Tween` no HUD dos outros.
  - **Texto sem limite de tamanho antes do login.** `version` é devolvida ao peer e escrita no log sem ser cortada. Um peer não autenticado pode mandar textos enormes repetidamente e encher o log e o disco.
  - **Quebra de linha e caracteres de controle** passam em nomes (até 16 caracteres) e no chat (até 200). Dá para forjar linhas no log do servidor e mensagens que parecem do sistema na tela dos outros ("X morreu"). O HUD usa `Label`, não `RichTextLabel`, então não há injeção de BBCode.
  - **Chave com sinal.** `is_valid_key` usa `is_valid_hex_number`, que aceita `+` ou `-` no começo (`core/string/ustring.cpp:4770`). Uma chave assim não decodifica e vira a chave vazia. Só afeta quem a criar com cliente modificado.
- **Correção sugerida:** um balde de fichas por peer (por exemplo, 5 mensagens de chat a cada 3 s e um teto de ações por segundo), cortar todo texto na entrada (`version.substr(0, 16)`), remover caracteres de controle, restringir nomes a letras, números, espaço, `_` e `-`, validar a chave com `^[0-9a-f]{64}$` e desconectar quem insistir.

#### S-07: transporte sem criptografia, chave reutilizável, escuta em todas as interfaces

- **Severidade:** baixa (com Tailscale) · **Confiança:** alta
- **Local:** `scripts/net/net.gd:252-258`, `scripts/net/game_server.gd:76-81`, `scripts/client/game_client.gd:227-229`
- **Problema:** o ENet é criado sem DTLS. O login é o envio de uma chave fixa (`c_password`), sem desafio: quem capturar o pacote reenvia e entra na conta. O endereço de escuta padrão do ENet no Godot é `*` (`modules/enet/enet_multiplayer_peer.cpp:486`), então o servidor atende também na rede local, e o `server_relay` do multiplayer vem ligado (`modules/multiplayer/scene_multiplayer.h:123`), o que deixa um cliente mandar pacotes a outro através do servidor.
- **Cenário:** dentro do Tailscale o tráfego já vai cifrado e o risco é pequeno. Em rede local (inclusive o "Testar sozinho", que abre um servidor com `--dev` na porta 7777 em todas as interfaces), qualquer máquina da rede conecta e quem observa o tráfego captura a chave.
- **Correção sugerida:** opção `--bind=<IP do Tailscale>` com `peer.set_bind_ip()`, e `127.0.0.1` no servidor do "Testar sozinho". `(multiplayer as SceneMultiplayer).server_relay = false`. Para o login, desafio e resposta com um número aleatório do servidor; ou DTLS do próprio ENet.

#### S-08: chave equivalente à senha em texto puro no cliente; derivação fraca

- **Severidade:** baixa · **Confiança:** alta
- **Local:** `scripts/ui/hud.gd:124-126` e `589-601`, `scripts/net/accounts.gd:23-24` e `37-39`
- **Problema:** "Lembrar a senha neste PC" vem marcado e grava a chave em `user://cliente.cfg`. A chave é equivalente à senha para este jogo. A derivação usa 20.000 iterações de PBKDF2-SHA256 no cliente e 1.000 no servidor (a recomendação atual da OWASP para PBKDF2-SHA256 é 600.000), e o sal é só `"dino-survival:" + nome`, igual em qualquer servidor.
- **Impacto:** quem copiar o `cliente.cfg` entra na conta. Quem obtiver `contas.json` quebra senhas curtas offline. Um servidor malicioso recebe uma chave que vale em qualquer outro servidor onde a pessoa use o mesmo nome e senha. O LEIA-ME já avisa para não reutilizar senha, o que reduz o dano.
- **Correção sugerida:** deixar "lembrar" desmarcado por padrão, ou guardar um token de sessão emitido pelo servidor em vez da chave. Incluir um identificador aleatório do servidor no sal. Subir as iterações rodando a derivação fora da thread principal.

#### S-09: movimento sem nenhuma conferência (risco aceito pelo projeto)

- **Severidade:** baixa · **Confiança:** alta
- **Local:** `scripts/net/game_server.gd:401-418`
- **Problema:** decisão documentada em `docs/design.md`. Registro aqui o alcance real: o cliente pode mandar qualquer posição a cada pacote (teleporte para morder e sair, para comida, para fora de uma briga) e o servidor confia nos bits `CF_MOVING` e `CF_SPRINT`. Sem `CF_MOVING`, `moving_speed` fica 0 mesmo com o dino se deslocando: o fôlego não gasta correndo, a fome anda no ritmo de parado, o descanso cura em dobro em movimento e dá para fazer ninho andando. Somado ao snapshot global (E-02), o cliente conhece a posição de todos no mapa.
- **Correção sugerida (barata, sem virar anticheat):** calcular `moving_speed` pelo deslocamento que o servidor já mede, independente do bit, e devolver um `s_teleport` quando o deslocamento passar de `sprint × tempo × folga`.

#### S-10: cadeia de build

- **Severidade:** baixa · **Confiança:** média (não vi as configurações do repositório no GitHub)
- **Local:** `.github/workflows/release.yml:14-15`, `24`, `71-73`, `90-93`, `129-130`; `.github/workflows/testes.yml`; `export_presets.cfg:30`
- **Problema:** o editor do Godot e os modelos de exportação são baixados com `curl` e guardados em cache sem conferir hash; é com eles que sai o `.exe` que os amigos executam. O workflow de release dá `contents: write` ao job inteiro, incluindo a etapa que roda os testes, e o `actions/checkout` deixa o token na configuração do git. As ações são fixadas por tag (`@v4`), não por commit. O `testes.yml` não declara `permissions`. O `.exe` não é assinado, e as notas de release ensinam a clicar em "Executar assim mesmo". `gh release create ... || gh release upload --clobber` troca o arquivo de uma release existente se a criação falhar.
- **Correção sugerida:** conferir o SHA-512 publicado pelo Godot antes de descompactar; `permissions: contents: read` no nível do workflow e `contents: write` só num job de publicação separado; `persist-credentials: false`; fixar ações por SHA; publicar o hash do zip nas notas; tirar o `--clobber`.

#### S-11: códigos de resgate em claro no log

- **Severidade:** baixa · **Confiança:** alta
- **Local:** `scripts/net/game_server.gd:283-284`, `298-299`, `338`
- **Problema:** o servidor imprime o código inteiro ao criar, resgatar e cancelar. Quem receber o log para ajudar a depurar recebe os códigos ainda válidos.
- **Correção sugerida:** registrar só os 4 últimos caracteres.

### Qualidade

#### Q-01: save ilegível ou ausente vira mundo novo e o original é sobrescrito

- **Severidade:** alta · **Confiança:** alta
- **Local:** `scripts/net/game_server.gd:43`, `52-65`, `790-797`, `811-814`

```gdscript
# _read_save
if typeof(parsed) != TYPE_DICTIONARY:
    _log("AVISO: save ilegível em %s, começando mundo novo" % save_path)
    return {}
# _notification
if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
    if sim != null:
        save()
```

- **Problema:** para contas e códigos, arquivo ilegível impede o servidor de subir ("não pode virar ninguém tem senha"). Para o mundo, que guarda o crescimento de todos, o tratamento é o oposto: `{}` → mundo novo → o primeiro `save()` grava por cima. O save de mapa diferente é posto de lado com outro nome (`_set_aside_save`); o ilegível não.
- **Cenário:** o `world.json` fica truncado (ver Q-02). No próximo início o console mostra um AVISO e o servidor sobe com mundo novo e nenhum registro de jogador. O arquivo original, que talvez desse para recuperar à mão, é sobrescrito na primeira saída de um jogador, 30 s depois do primeiro login, ou **no encerramento limpo do servidor** (`_notification` salva ao sair, mesmo sem ninguém ter entrado), que é a reação natural de quem viu o aviso. Todos recomeçam como filhotes; as contas continuam. Não verifiquei se fechar a janela do console no Windows chega a entregar essa notificação; se não entregar, o arquivo sobrevive até o primeiro login.
- **Correção sugerida:** recusar a subida como já é feito para as contas, ou renomear o arquivo para `world.ilegivel-<hora>.json` antes de criar o mundo novo, e tentar o `.bak` automaticamente (Q-02).

#### Q-02: gravação não atômica no Windows, erro de escrita ignorado, sem backup

- **Severidade:** média · **Confiança:** alta
- **Local:** `scripts/net/game_server.gd:741-752`

```gdscript
f.store_string(JSON.stringify(data))      # o retorno (bool) é ignorado
f.close()
var err := DirAccess.rename_absolute(tmp_global, path_global)
```

- **Problema:** o comentário diz que "um desligamento no meio não estraga o save", mas:
  - `FileAccess.store_string` devolve `false` quando a escrita falha (`core/io/file_access.cpp:816`). O código ignora, e com disco cheio o `.tmp` truncado é renomeado por cima do save bom.
  - No Windows, que é a plataforma do servidor, o `rename` do Godot **apaga o destino e depois move** (`drivers/windows/dir_access_windows.cpp:340-346`). Há um intervalo em que `world.json` não existe; se o processo morrer ali, o próximo início não acha save, cria mundo novo e o primeiro save trunca o `.tmp`, que era a única cópia boa.
  - Não há descarga para o disco antes do rename, nem cópias anteriores. Qualquer bug que corrompa o estado é persistido em até 30 s, sem volta.
  - Uma falha ao salvar só aparece no console; os jogadores seguem jogando sem saber que nada está sendo gravado.
  - O mesmo vale para `contas.json`: se sumir nessa janela, todo nome volta a ser de quem chegar primeiro (S-03), inclusive os dinos salvos dos outros.
  - Os três arquivos são gravados em sequência sem transação (linhas 280-282); uma queda no meio pode deixar um código resgatado duas vezes.
- **Correção sugerida:** conferir o retorno de `store_string` e `f.get_error()`, chamar `f.flush()`, e trocar a sequência por: gravar `.tmp`, renomear o atual para `.bak`, renomear o `.tmp` para o definitivo. Na leitura, tentar o definitivo, depois o `.tmp`, depois o `.bak`. Guardar cópias com data (por exemplo, uma por hora das últimas 24 h). Avisar no chat quando o save falhar.

#### Q-03: teste de unidade que quebra com erro de script conta como "ok"

- **Severidade:** média · **Confiança:** alta
- **Local:** `tests/run_tests.gd:32-38`, `tools/test.sh:8-9`

```gdscript
var before := failures
suite.call(mname, self)
if failures == before:
    passes += 1
```

- **Problema:** um teste só falha se chamar `check` com falso. Se a função de teste parar no meio por erro de script (método que não existe, índice inválido, `null`), nenhum `check` posterior roda, `failures` não muda e o teste é contado como aprovado. O `tools/test.sh` decide pelo código de saída e não procura `SCRIPT ERROR` na saída dos testes de unidade; o `net_test.sh:126` procura, mas só nos logs do teste de rede.
- **Impacto:** uma regressão que quebra o código antes das asserções passa na CI e chega à release automática.
- **Correção sugerida:** no `test.sh`, falhar se a saída contiver `SCRIPT ERROR`. No executor, exigir ao menos um `check` por teste.

#### Q-04: `load_save` não valida, e um registro ruim aborta antes de carregar os jogadores

- **Severidade:** média · **Confiança:** média
- **Local:** `scripts/sim/world_sim.gd:784-812`, `scripts/sim/dino.gd:145-146`

```gdscript
for bd in data.get("bots", []):          # linhas 788-794
    var d := Dino.from_dict(bd)
    d.is_bot = true
...
player_records = data.get("players", {}).duplicate(true)   # só na linha 809
```

- **Problema:** `player_records`, o dado mais valioso, é o último a ser carregado. `Dino.from_dict` faz `float(p[0])` sem conferir o tipo, e `float(null)` não tem construtor (`core/variant/variant_construct.cpp:264-289`).
- **Cenário:** um bot ou carcaça com campo inválido no save (o `null` de S-01, ou uma edição manual). Num servidor rodado pelo binário do editor, que é o modo documentado no `CLAUDE.md` e usado nos testes, o erro interrompe `from_dict`, depois `load_save`, e a linha 809 nunca roda. `start` segue em frente, o log mostra "jogadores salvos=0" e o save seguinte grava o mundo sem ninguém.
- **O que é HIPÓTESE:** no `.exe` exportado (release) a VM não confere esse erro (`modules/gdscript/gdscript_vm.cpp:1751-1758` está sob `DEBUG_ENABLED`); o valor fica indefinido e a carga provavelmente continua com posições erradas. Não executei nenhum dos dois casos.
- **Correção sugerida:** carregar `player_records` primeiro; validar cada entrada (tipo e finitude) e pular a inválida com uma linha no log; conferir se `format` é maior que `SAVE_FORMAT`; teste de unidade com um save malformado.

#### Q-05: sessão fantasma barra o próprio dono

- **Severidade:** baixa · **Confiança:** alta
- **Local:** `scripts/net/game_server.gd:173-179`
- **Problema:** "Já tem alguém com o nome" é conferido antes da senha. Quando a conexão de um jogador cai sem aviso, o servidor só percebe pelo tempo limite do ENet; até lá o dono, com a senha certa, não consegue voltar.
- **Correção sugerida:** se o nome está online e a senha confere, derrubar a sessão antiga e passar o dino para a nova.

#### Q-06: snapshot oscila entre 10 e 15 Hz

- **Severidade:** baixa · **Confiança:** alta
- **Local:** `scripts/net/game_server.gd:86`, `109-117`
- **Problema:** com `Engine.max_fps = 30`, cada quadro soma cerca de 33,3 ms e o limiar do snapshot é 66,7 ms. Como o acumulador é zerado em vez de descontar o intervalo, qualquer variação faz o envio cair para o terceiro quadro (100 ms). O mesmo ocorre com `s_self_stats` (entre 7,5 e 10 Hz).
- **Correção sugerida:** `_snap_accum -= intervalo` (guardando o resto), ou escolher taxas que dividam 30.

#### Q-07: documentação defasada, código morto, funções longas

- **Severidade:** baixa · **Confiança:** alta
- **Itens:**
  - `tools/windows/LEIA-ME.txt:1` diz "protótipo v0.1"; a versão é 0.5.0.
  - `docs/arquitetura.md:233` diz que o tamanho padrão do mapa é 512 m; o código usa `GameConfig.DEFAULT_MAP_SIZE`, 2048 (`game_server.gd:45`).
  - `README.md:52` mostra `--connect=127.0.0.1 --name=Tux` como entrada direta; sem `--password` e sem chave lembrada o cliente para no menu pedindo a senha.
  - Sem uso: `Species.get_data`, `Species.is_locked`, `Species.is_beta`, `Rewards.default_param`, `WeatherView.ready_to_use`; `Accounts.has_account` só é usada em teste.
  - `scripts/main.gd:22` carrega `res://tests/net_scenario.gd`, que o preset do Windows exclui (`export_presets.cfg:11`): `--test-client` no jogo exportado quebra.
  - `WorldSim.choose_bot_species` (`world_sim.gd:490-492`) tem as três espécies escritas à mão; espécie nova exige lembrar de mexer ali.
  - Funções longas: `BotBrain.think` (138 linhas), `Hud._build_game` (98), `GameServer._dev_command` (86), `BotBrain._act` (86). O `game_server.gd` acumula rede, persistência, contas, códigos e comandos de dev, e `_dev_command` mexe em regra de jogo, o que o `CLAUDE.md` pede para não fazer nesse arquivo.
  - Nenhum `push_error`, `push_warning` ou `assert` em `scripts/`: todo erro é um `print`, sem separação de nível.

### Eficiência

#### E-01: busca de arbusto varre todos os arbustos a cada passo

- **Severidade:** média · **Confiança:** alta no código, média na magnitude (não medi)
- **Local:** `scripts/sim/world_sim.gd:199-211` e `214-224`, chamadas em `scripts/sim/world_sim.gd:344` e `scripts/sim/bot_brain.gd:278-279`

```gdscript
func bush_in_reach(d: Dino) -> int:
    ...
    for i in terrain.bushes.size():
```

- **Problema:** `Terrain` já tem uma grade de arbustos (`bushes_near`, `terrain.gd:229-237`), criada "pra achar os arbustos perto de um ponto sem olhar todos". O cliente usa (`game_client.gd:796`); o servidor não.
- **Impacto:** o mapa padrão de 2 km tem 3.840 arbustos (`terrain.gd:122-123`). Um herbívoro bot no estado "eat" chama `bush_in_reach` a cada passo, andando até a comida ou comendo; quando está comendo, `_interact` chama de novo no mesmo passo. Um jogador herbívoro segurando E dispara uma varredura por passo mesmo sem arbusto por perto. São 20 passos por segundo, com uma chamada de função e um `Vector2` por arbusto. O README cita cerca de 2 ms por passo com 70 bots, então hoje cabe; mas o custo cresce com a área: 4 km têm 15.360 arbustos e 8 km (o máximo aceito por `--map-size`) têm 61.440, 16 vezes o padrão.
- **Correção sugerida:** em `bush_in_reach`, iterar `terrain.bushes_near(m, reach)`. Em `nearest_bush_with_food`, buscar em raios crescentes na grade.

#### E-02: snapshot global sem área de interesse

- **Severidade:** média · **Confiança:** alta nos números, média no efeito da fragmentação (comportamento do ENet não verificado aqui)
- **Local:** `scripts/net/game_server.gd:645-688`
- **Problema:** todo snapshot leva todos os dinos e carcaças do mapa, 32 bytes por entidade, para todos os jogadores, 15 vezes por segundo. Bots congelados (a mais de 480 m de todo mundo) não se movem e mesmo assim são reenviados inteiros.
- **Impacto:** com 75 entidades são 2,4 KB por snapshot, e com 105 são 3,4 KB: de 36 a 50 KB/s por jogador e de 1,4 a 2 Mbit/s de upload do notebook com 5 jogadores. O pacote passa do tamanho de um datagrama (cerca de 1,4 KB), então é fragmentado num canal não confiável, onde a perda de um fragmento descarta o snapshot inteiro. O cliente ainda cria e anima uma `DinoView` para cada entidade do mapa (E-04), e o mapa todo fica visível para um cliente modificado (S-09).
- **Correção sugerida:** por ordem de retorno: não reenviar bot congelado enquanto ele não mudar; mandar entidades distantes a uma taxa menor; quantizar (posição em `int16`, yaw e flags em 1 byte cada reduz a cerca de 12 bytes por entidade).

#### E-03: save completo e síncrono em cada evento

- **Severidade:** baixa · **Confiança:** alta
- **Local:** `scripts/net/game_server.gd:736-737`, chamado nas linhas 126, 153, 282, 473 e 630
- **Problema:** além do save a cada 30 s, toda saída, morte, renascimento e resgate serializa o mundo inteiro (bots, 3.840 valores de arbusto, ninhos, jogadores) em JSON e grava na thread da simulação. No mapa de 2 km o arquivo é pequeno (estimo cerca de 100 KB); cresce com a área do mapa e com o número de contas (S-03).
- **Correção sugerida:** marcar "sujo" e gravar no máximo uma vez a cada poucos segundos; montar o dicionário na thread principal e escrever o arquivo em `WorkerThreadPool`.

#### E-04: cliente cria malhas e materiais exclusivos para cada dino do mapa

- **Severidade:** baixa · **Confiança:** média (não medi quadros por segundo)
- **Local:** `scripts/client/dino_view.gd:157-205`, `scripts/client/game_client.gd:374-405`
- **Problema:** cada `DinoView` cria de 15 a 20 `MeshInstance3D`, cada um com um recurso de malha novo, e 4 materiais novos. Nada é compartilhado entre dinos da mesma espécie, então o renderizador não agrupa nada. Como o snapshot é global, isso vale para todas as entidades do mapa, e o `_process` de animação roda para todas, visíveis ou não.
- **Correção sugerida:** cache de malhas e materiais por espécie e parte (o piscar de dano e a cor de morto podem ser parâmetros por instância); `visibility_range_end`; não animar o que está fora da distância de visão.

#### E-05: rebrota percorre todos os arbustos 20 vezes por segundo; terreno gerado na thread principal

- **Severidade:** baixa · **Confiança:** alta
- **Local:** `scripts/sim/world_sim.gd:465-469`, `scripts/world/terrain.gd:80-118`
- **Problema:** `_regrow_bushes` faz 76.800 iterações por segundo em GDScript no mapa padrão (1,2 milhão em 8 km), embora quase todos os arbustos estejam cheios. A geração do terreno é um laço duplo em GDScript na thread principal: 0,5 s em 2 km e 1,4 s em 4 km segundo `docs/arquitetura.md:240`, no servidor e no cliente (que congela ao receber o `s_welcome`).
- **Correção sugerida:** manter um conjunto dos arbustos incompletos, ou calcular a comida na leitura a partir do instante em que o arbusto foi comido. Gerar o terreno numa thread com tela de carregamento.

#### E-06: CI abre um Godot por arquivo e roda os testes de unidade duas vezes

- **Severidade:** baixa · **Confiança:** alta
- **Local:** `tools/check.sh:13-20`, `tools/test.sh:8-9`
- **Problema:** o `check.sh` inicia o Godot uma vez para cada um dos 51 arquivos `.gd`; o `test.sh` roda a suíte de unidade duas vezes (uma pela saída, outra pelo código de saída). A execução total é de cerca de 2 min 40 s, então o ganho é pequeno, mas cresce com o projeto. O `net_test.sh` depende de `sleep 2` fixo para o servidor subir, o que pode falhar numa máquina lenta.
- **Correção sugerida:** uma execução só com `tee` e `PIPESTATUS`; esperar o servidor pela linha "servidor ouvindo" no log em vez do `sleep`.

## 4. Quick wins (menos de 1 hora cada)

| # | O que fazer | Resolve |
|---|---|---|
| 1 | `if not (pos.is_finite() and is_finite(yaw)): return` em `on_state`; ignorar posição não finita em `_on_snapshot` e `_push_out_of_others` | S-01 |
| 2 | Tirar `--dev` do `iniciar_servidor.bat`; limitar o salto de `/time` e o `/spawn` a `BOT_MAX` | S-02 |
| 3 | Renomear o save ilegível para `world.ilegivel-<hora>.json` (ou não subir) em vez de seguir com mundo novo | Q-01 |
| 4 | Conferir o retorno de `store_string` e manter um `.bak` antes do rename | Q-02 |
| 5 | Carregar `player_records` antes dos bots em `load_save` | Q-04 |
| 6 | Timer de 10 s em `_on_peer_connected` para derrubar quem não fez login | S-05 |
| 7 | `tools/test.sh` falhar quando a saída dos testes de unidade tiver `SCRIPT ERROR` | Q-03 |
| 8 | Usar `terrain.bushes_near` em `bush_in_reach` | E-01 |
| 9 | Cortar `version` e demais textos na entrada; intervalo mínimo entre mensagens de chat | S-06 |
| 10 | `server_relay = false`; `permissions: contents: read` no `testes.yml` | S-07, S-10 |
| 11 | Registrar só o final dos códigos no log | S-11 |
| 12 | Corrigir "v0.1" no LEIA-ME, o padrão de 512 m na arquitetura e o exemplo do README | Q-07 |

Os itens 1 a 7 somam poucas horas e cobrem os três achados de severidade alta e os dois caminhos de perda de save.

## 5. Plano de correção, por impacto e esforço

**Fase 0: antes da próxima sessão com os amigos (meio dia).** Quick wins 1 a 7. Nenhum muda o protocolo nem o formato do save. Como a release só sai com `VERSION` nova, vale subir para 0.5.1 e publicar; enquanto isso, basta apagar `--dev` do `.bat` no notebook.

**Fase 1: na semana (1 a 2 dias).**

| Item | Impacto | Esforço |
|---|---|---|
| Cópias com data do save e leitura com queda para `.tmp` e `.bak` (Q-02) | alto | pequeno |
| Testes de entrada hostil: `NaN`, textos grandes, RPC antes do login, save malformado, servidor sem `--dev` (S-01, S-06, Q-04) | alto | médio |
| Registro de conta com código de entrada e admin gravado na conta (S-03) | médio | médio |
| Bloqueio por nome e endereço, senha mínima de 8 (S-04) | médio | pequeno |
| Limite de taxa por peer e filtro de caracteres (S-06) | médio | pequeno |
| Exigir admin nos comandos dev de efeito global (S-02) | médio | pequeno |
| Derrubar a sessão antiga quando o dono volta com a senha certa (Q-05) | baixo | pequeno |

**Fase 2: nas próximas versões.**

| Item | Impacto | Esforço |
|---|---|---|
| Snapshot sem os congelados, com taxa por distância e quantização (E-02); muda o protocolo, sobe `VERSION` | médio | médio |
| Cache de malhas e materiais por espécie no cliente (E-04) | médio | médio |
| `--bind`, desafio e resposta no login ou DTLS (S-07); "lembrar" com token (S-08) | baixo | médio |
| Hash dos binários do Godot, permissões mínimas e ações por SHA na CI (S-10) | baixo | pequeno |
| Conferência barata de deslocamento no servidor (S-09) | baixo | pequeno |
| Save com debounce e escrita em thread (E-03); rebrota sob demanda (E-05); acumuladores (Q-06); CI (E-06) | baixo | pequeno |

## 6. Limites da auditoria

**O que não foi verificado, e por quê:**

- **Nenhum teste, linter ou analisador foi executado localmente.** O Godot não está instalado neste ambiente e a regra era não instalar nada sem avisar. `gdlint`, `shellcheck` e `actionlint` também não estão disponíveis. Como evidência indireta, a CI do GitHub está verde no commit auditado: Testes nº 24 e Release nº 5, ambos concluídos com sucesso em 28/10/2026 sobre `9a1ca4d`.
- **Nenhuma prova de conceito foi rodada.** S-01, S-02 e Q-04 foram confirmados por leitura do projeto e do código-fonte do Godot `4.7.2-stable`, não por execução. Os pontos que dependem de comportamento indefinido da engine estão marcados como HIPÓTESE dentro de cada achado.
- **Comportamento do `.exe` exportado (release) com dados inválidos.** Nesse tipo de build a VM do GDScript não confere vários erros; o resultado exato só se conhece executando.
- **Desempenho não foi medido.** O `--bench` não foi rodado; as magnitudes de E-01 a E-05 são estimativas a partir do código e dos números do README e da documentação. O desempenho de renderização do cliente não foi medido.
- **Internos do ENet** (fragmentação, tamanho máximo de pacote, tempos limite) não foram conferidos no código da biblioteca.
- **CVEs do Godot 4.7.2** não foram consultados. Não há outras dependências para auditar.
- **Windows.** Não verifiquei se fechar a janela do console entrega a notificação que dispara o save final, nem o comportamento do firewall.
- **Fora do repositório:** configuração do Tailscale (ACLs, quem está no tailnet), configurações do repositório no GitHub (proteção de branch, permissão padrão do token, secret scanning) e o conteúdo real dos arquivos de save e de contas no notebook.
- **Equilíbrio do jogo** (números de `species.gd` e `config.gd`) não fez parte do escopo.
- **Testes:** li o executor, a lista de casos e o roteiro de rede; não revisei asserção por asserção os 3.881 linhas de `tests/`.

**O que foi verificado e está correto:**

- Toda RPC `c_*` confere `peers.has(peer_id)` antes de agir; as de admin passam por `_staff_name` (`game_server.gd:345-353`). Nenhuma RPC aceita identificador de alvo vindo do cliente, então não há acesso a recurso de outro jogador por troca de id.
- As RPCs `s_*` são `authority`: um cliente não consegue forjar mensagem do servidor para outro (`modules/multiplayer/scene_rpc_interface.cpp:258-263`).
- A VM confere os tipos dos argumentos das RPCs também em release (`modules/gdscript/gdscript_vm.cpp:597-603`).
- A senha não trafega nem é gravada; o hash usa sal aleatório de 16 bytes e a comparação é em tempo constante (`accounts.gd:166-180`).
- Os códigos de resgate saem de `Crypto.generate_random_bytes`, sem viés (256 é múltiplo de 32), com 32^8 combinações e limite de tentativas por conta.
- `allow_object_decoding` fica desligado (padrão da engine); os saves são JSON puro; não há `str_to_var`, `bytes_to_var`, `Expression` nem `load()` com caminho vindo da rede.
- Nome de jogador nunca vira caminho de arquivo; `OS.create_process` recebe só argumentos fixos; `OS.shell_open` só abre URL que começa com `https://github.com/`.
- **Segredos:** nenhum no código nem no histórico do git. As únicas ocorrências são senhas fixas de teste em `tests/net_scenario.gd:113-115` e `tools/screenshot.sh:30`, usadas contra servidores temporários locais; `export_presets.cfg` não tem credenciais.
- Regras do projeto conferidas no código: o mundo não anda sem ninguém logado (`game_server.gd:97-99`), raio só atinge bot (`climate.gd:595-609`), quem sai fica congelado (`world_sim.gd:691-700`).

**Itens do roteiro que não se aplicam a este projeto:** injeção de SQL, XSS, CSRF, SSTI, SSRF, upload de arquivos, CORS, cookies, cabeçalhos de segurança, redirecionamento aberto, consultas N+1, índices e migrações de banco. Não há servidor web, banco de dados nem mecanismo de templates.
