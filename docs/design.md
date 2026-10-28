# Design do jogo: decisões consolidadas

Fonte: conversas do Marcelo (idealizador) com o ChatGPT em 13–14/10/2026, mais as decisões
de engenharia tomadas com o Tux em 20–21/10/2026.

**Regra de ouro deste documento:** aqui só entra o que o Marcelo *decidiu*. Sugestões que o
ChatGPT fez e o Marcelo não confirmou (ou corrigiu depois) ficam em "Em aberto" ou não
entram. Quando o Marcelo mudar de ideia, atualiza aqui primeiro e no código depois.

Status de cada item: ✅ implementado e testado · 🟡 parcial · ⬜ futuro

**(R)** = recomendação do Claude que o Marcelo aprovou em 28/10/2026 ("vai fazendo do jeito que
você recomendar, com a possibilidade de mudar no futuro de maneira simples"). Todo número de uma
decisão (R) fica em `scripts/config.gd` ou `scripts/data/species.gd`, com comentário: mudar é
trocar o valor ali.

> Nome do jogo: a definir. "The Isle" é o jogo comercial que serviu de inspiração.
> É o nome do repositório, não o nome final.

---

## 1. Formato do jogo

| Decisão | Status |
|---|---|
| Jogo próprio, inspirado em The Isle (não é mod nem servidor do The Isle) | ✅ |
| Instalado no PC (não roda no navegador) | ✅ (.exe para Windows) |
| Máximo de **5 jogadores** simultâneos | ✅ |
| Servidor dedicado num PC separado ligado 24h (Lenovo IdeaPad S145: i5 8ª geração, 8 GB RAM, HD 1 TB; specs lidas da etiqueta, falta confirmar) | ✅ roda sem tela (`--headless`); ainda não testado no Lenovo (o `testar_desempenho.bat` mede CPU, RAM e upload e mostra o processador, o que confirma as specs) |
| Os jogadores só desenham; o servidor cuida da simulação | ✅ (exceção: o movimento do próprio dino, ver engenharia) |
| Referência visual: The Isle | ⬜ (v0.1 usa formas simples no lugar dos modelos) |

## 2. Tempo do mundo e logout

| Decisão | Status |
|---|---|
| **Sem nenhum jogador conectado, o mundo inteiro fica parado** (nada envelhece, cura, passa fome, muda de estação) | ✅ |
| Com pelo menos 1 jogador conectado o mundo roda, e quem voltar depois pode encontrar o mundo mudado | ✅ |
| **Ao sair, o dino do jogador é deslogado**: some do mundo, não pode ser atacado, não cura, não passa fome, não cresce. Volta exatamente igual | ✅ (vale até reiniciando o servidor) |
| (R) Exceção: quem sai até 10 s depois de levar um golpe deixa o dino mais 10 s no mundo, parado e vulnerável (não dá pra fugir de uma briga fechando o jogo). Voltar nesse tempo assume o mesmo dino | ✅ `COMBAT_LOGOUT_S` |
| Ao morrer, o jogador **obrigatoriamente recomeça jovem** | ✅ |

## 3. População de bots

| Decisão | Status |
|---|---|
| População média **~70 bots**, **máximo 100** | ✅ padrão 70 (`DEFAULT_BOT_TARGET`, `--bots=N` até 100). Carga testada com 70 e 100 |
| Bots têm acesso a todas as espécies que o jogador tem | ✅ (as 3 que existem) |
| Bem mais herbívoros que carnívoros, "mas não muito mais" | ✅ (65% / 35%) |
| Carnívoros também se atacam entre si | ✅ (carnívoro com fome ataca carnívoro menor; canibalismo só morrendo de fome) |
| **Hitbox plausível**: só toma dano se a mordida realmente acertar | ✅ |
| A maioria dos bots fica congelada (longe dos jogadores) | ✅ (ver seção 5). No mapa de 2 km com 70 bots e o diretor de população: 16 a 37 congelados, conforme os jogadores estão espalhados ou juntos (`--bench`) |
| **Bot morreu → obrigatoriamente entra outro** (não precisa ser da mesma espécie) | ✅ entra 30 s depois, fora da vista dos jogadores, mantendo os 65/35 (v0.4: 1 em cada 4 reposições vira um ninho de bot, cujos ovos chocam como filhotes; ver seção 8) |
| Jogadores juntos → concentra bots perto deles; separados → espalha, sempre com população considerável perto de cada um | ✅ diretor de população: cada grupo de jogadores (a até 200 m um do outro) quer 60% da população dividida pelo número de grupos, na área de 260 m em volta. Age na reposição e mudando de lugar bots congelados que ninguém vê. (R) números em `config.gd` (seção "Diretor de população") |
| Jogadores carnívoros com fome → mais herbívoros na área; herbívoro demais → mais carnívoros | ✅ "com fome" = fome abaixo de 50; "herbívoro demais" = mais de 80% da área. A proporção geral só sai 10% dos 65/35. (R) números em `config.gd` |

## 4. IA

| Decisão | Status |
|---|---|
| Animal ataca ou foge de acordo com o % de vida (pouca vida → foge) | ✅ |
| Comportamento orgânico/natural, sem exagero | 🟡 vaga em manada, bebe, come, descansa, caça, foge, revida. Falta ajustar jogando |

## 5. Distância e carregamento do mapa

| Decisão | Status |
|---|---|
| Mapa grande, mas só carrega a área num raio grande em volta de cada jogador | ✅ o cliente só desenha até ~1,1 km em volta do jogador, com menos detalhe longe |
| (R) Tamanho do mapa: **2 km** de lado (uns 7 min andando de um lado ao outro) | ✅ `DEFAULT_MAP_SIZE` e `--map-size=2048` no `iniciar_servidor.bat`. Trocar o tamanho leva os dinos dos jogadores junto (lugar novo, mesmo dino); só os bots recomeçam |
| Simulação por faixas de distância (exemplo do Marcelo: >15 células estático; ~10 começa a ativar; ≤5 normal) | ✅ com células de 32 m: até 160 m roda normal (20 Hz); mais longe roda a 10 Hz; congela acima de 480 m e só acorda a 320 m (histerese). (R) células de 32 m |
| Bot longe congelado: ferido continua ferido, luta congela | ✅ e enquanto congelado ninguém enxerga, persegue ou morde ele |
| A distância considera o jogador mais próximo, não só o host | ✅ |

## 6. Ferimentos e cura

| Decisão | Status |
|---|---|
| Recuperação diferente por espécie e por tipo/grau de ferimento | 🟡 (v0.3: cada tipo tem seu tempo; ritmo por espécie em `injury_heal` no species.gd, hoje 1,0 em todas até jogar) |
| Exemplo: animal pequeno mordido por um muito grande pode quebrar osso → demora mais | ✅ (fratura, v0.3) |
| Cura acelerada: ~10 min dependendo do ferimento, nada de horas | ✅ (vida cheia em 8 min, 4 min descansando; ferimentos saram em 3 a 10 min, metade descansando) |
| (R) Lista de ferimentos: **sangramento**, **fratura** e **mordida funda**; descansar sara mais rápido. Vale pra jogadores e bots, fica no save e congela com quem sai do jogo. Números finais abaixo | ✅ v0.3 |

Ferimentos da v0.3 (números em `scripts/config.gd`, seção "Ferimentos"):

| Ferimento | Quando abre | O que faz | Dura |
|---|---|---|---|
| Sangramento | golpe que tira mais de 15% da vida máxima | não cura e perde 5% da vida máxima por minuto (15% no total); quem morre assim morre de "sangramento" | 3 min |
| Osso quebrado (fratura) | golpe de um bicho com pelo menos 3x a massa (ex.: carnotauro adulto no dryosaurus, tricerátops adulto no carnotauro) | anda a 60% da velocidade, não corre e manca | 10 min |
| Mordida funda | golpe que tira mais de 25% da vida máxima, ou mais de 10% na cabeça ou no pescoço | a vida cura pela metade do ritmo | 6 min |

Descansando parado, os ferimentos saram 2x mais rápido. Golpe novo renova o ferimento (nunca encurta).
No HUD: "Sangrando 2:10 · Osso quebrado 8:40".

## 7. Fome, sede e metabolismo

| Decisão | Status |
|---|---|
| Fome vem de **desgaste físico** + tempo sem comer; sede vem de tempo sem beber | ✅ (descansar 0,5x · parado 0,75x · andar 1x · correr 2x) |
| Crescendo → mais fome (moderado, nada absurdo) | ✅ (+25%) |
| Grande come **mais quantidade**; pequeno come **mais vezes, em menor quantidade** | ✅ |
| Cura e fome têm que ser compatíveis (não pode curar em 2 meses e ter fome em 5 min) | ✅ |
| Nada 100% realista, senão fica chato | ✅ |
| Morte é rara/demorada: fome zerada não mata na hora | ✅ (17 min de vida cheia até morrer) |

## 8. Reprodução e ciclo de vida

| Decisão | Status |
|---|---|
| Nascer, crescer, reproduzir e morrer. **Reprodução é obrigatória** | ✅ v0.4 (ver a interpretação (R) abaixo) |
| (R) "Obrigatória" = faz parte do ciclo de vida de todo dino, bot ou jogador: os bots se reproduzem sozinhos e o jogador ganha uma vantagem ao reproduzir (renascer filhote no próprio ninho). **Não tem punição** pra quem não reproduz | ✅ |
| Encontrar parceiro e construir ninho | ✅ tecla **N** (ninho) e **R** (parceiro) |
| (R) O parceiro pode ser bot ou jogador (com 5 jogadores, exigir parceiro jogador travaria algo que é obrigatório) | ✅ bot aceita ou recusa na hora; jogador tem 15 s pra apertar R de volta |
| Dá pra comer ovos de outros ninhos e filhotes | ✅ qualquer carnívoro (jogador segurando E, bot com fome que passa perto); herbívoro não. Ninho de dono offline pode ser saqueado |
| (R) Bots também se reproduzem: 25% das reposições de bot viram um ninho de bot com ovos, fora da vista dos jogadores (é o que dá ovo pros carnívoros comerem) | ✅ `BOT_NEST_SHARE` |
| (R) Parte dos bots já nasce adulta (~31%, antes quase nenhum), pra ter parceiro bot por perto | ✅ `BOT_SPAWN_GROWTH_MAX` |

Reprodução da v0.4 (R), números em `scripts/config.gd` (seção "Reprodução") e `clutch`/`egg_kg` em
`species.gd`. Todo tempo é tempo de mundo: com ninguém online nada choca nem anda.

| Etapa | Regra |
|---|---|
| Quem pode | adulto (o mesmo "adulto" do HUD), comida e água a partir de 50%, sem sangramento |
| Ninho | segurar **N** parado por 8 s, em terra firme (fora d'água) e sem ladeira forte (até ~19°). Um ninho por jogador; fazer outro abandona o antigo (não dá com ovos chocando). Fica no save |
| Parceiro | com o ninho pronto, chegar perto (4 m além dos dois corpos) de um adulto da **mesma espécie**, estando a até 40 m do próprio ninho, e apertar **R**. Bot aceita se estiver alimentado (50%), sem fugir/brigar/caçar e sem recarga. Jogador recebe o aviso na tela e tem 15 s pra apertar R |
| Postura | os ovos aparecem no ninho de quem pediu: Dryosaurus 4, Carnotaurus 3, Triceratops 2. Recarga de 2 h entre posturas (o bot parceiro também fica 2 h sem aceitar) |
| Incubação | 20 min de mundo |
| Choco | um ovo fica pronto pro dono: se ele morrer, a tela de morte mostra **"Nascer no ninho"** e ele recomeça filhote ali (continua valendo "morreu → recomeça jovem"). Os outros viram bots filhotes, até o máximo de 100 bots (cheio, o ovo espera). O ovo pronto fica esperando o dono até ser usado ou comido |
| Comer ovo | carnívoro segurando E com a boca no ovo por 3 s; dá comida (`egg_kg`: Dryosaurus 3 kg, Carnotaurus 6 kg, Triceratops 10 kg; enche um filhote, pouco pra um adulto). Bot carnívoro com fome sente ovo a até 25 m. O dono recebe o aviso |
| Ninho de bot | uma reposição de bot em cada 4 vira ninho com os ovos da espécie que a reposição escolheria, onde o diretor de população poria o bot. Enquanto tem ovo, o ninho vale um bot na conta da reposição. Só acontece com jogador no mundo |
| Fim | o ninho some quando acabam os ovos |

HUD: "Ninho: 3 ovos · chocam em 12:30", a recarga da postura ("Nova postura em 1:42:10") e o aviso
"Fulano quer fazer ninho com você · aperte R (12 s)". O ninho aparece como um anel marrom com os
ovos (o ovo pronto pro dono é dourado).

## 9. Progressão do jogador

| Decisão | Status |
|---|---|
| O jogo favorece o jogador de acordo com a fase: filhote = tranquilo com algum perigo; médio = mais perigo; grande = não impossível | 🟡 (filhote nasce longe de carnívoros e os bots só percebem ele mais perto) |
| T-Rex, Espinossauro e Giganotossauro adultos dominam com facilidade (chegar no adulto é a parte difícil) | ⬜ (espécies ainda não existem) |
| (R) Espécies: as 3 de hoje; as próximas entram junto com os modelos 3D, começando por T-Rex, Espinossauro e Giganotossauro | 🟡 |
| (R) Ao nascer ou renascer, começa **filhote** (10% do tamanho de adulto) | ✅ `PLAYER_START_GROWTH` |
| (R) Tempo jogado até virar adulto: Dryosaurus 1 h, Carnotaurus 2 h, Triceratops 3 h | ✅ `grow_minutes` em `species.gd` |
| (R) Triceratops x Carnotaurus fica como está (trike adulto inteiro é perigoso; o carnotauro caça os menores e os feridos) | ✅ |
| Carnotauro (médio) vive em perigo constante, mas sem exagero | 🟡 |
| Tem que parecer orgânico e o jogador tem que se sentir confortável | 🟡 |

## 10. Rastro

| Decisão | Status |
|---|---|
| Habilidade de faro ativável por um momento, mostrando pegadas/cheiro | ✅ tecla **F** |
| Visual simples (ex.: rastro amarelo), nada de gráfico pesado | ✅ marcas amarelas no chão; carcaça com carne = mancha laranja |
| Mostra as pegadas dos outros dinos (bots e jogadores) dos últimos **2 min**, uma a cada **3 m** andados; as mais velhas mais apagadas. As próprias não aparecem (R) | ✅ |
| O rastro fica **8 s** na tela; recarga de **30 s**, conferida no servidor (R) | ✅ |
| Alcance por espécie (R): Carnotaurus **80 m**, Dryosaurus **60 m**, Triceratops **40 m** | ✅ `smell_radius` em `species.gd` |
| As pegadas envelhecem com o tempo do mundo: com o mundo parado (ninguém online) não somem; bot congelado não deixa pegada; teleporte (`/tp`, nascer) não deixa rastro | ✅ |
| Bots não usam o faro | ✅ |

Números em `config.gd` (seção "Faro") e `smell_radius` em `species.gd`. As pegadas ficam só na
memória do servidor: reiniciar o servidor apaga o rastro.

## 11. Clima e estações

| Decisão | Status |
|---|---|
| Inverno com neve: mais fome, corre menos, água congela, instinto de caça reduzido | ✅ (R) fome x1,3; corrida x0,85 onde o chão está branco (vale pros bots); a água congela nos trechos do rio com neve nas margens; bot carnívoro só sai pra caçar com a fome abaixo de 40 (normal: 60) |
| Inverno: menos população de tudo, mas sem mortandade excessiva | ✅ (R) a população-alvo de bots cai pra 80%; ninguém é morto pra isso, só repõe menos. Na primavera volta ao normal |
| Verão: mais comida pros herbívoros → mais herbívoros → carnívoros crescem tranquilos | ✅ (R) arbustos rebrotam 50% mais rápido e a reposição de bots mira 70% de herbívoros (dentro dos limites do diretor: 55% a 75%) |
| Duração: períodos favoráveis = **9X**; desfavoráveis = **X a 2X**. Predomina verão, com outono/primavera e alguns "meses" de inverno | ✅ (R) primavera 14 h, verão 42 h, outono 12 h, inverno 12 h (favorável 56 h ≈ 9X, inverno ≈ 2X, com X ≈ 6 h) |
| Ciclo completo longo: **~70–90 horas jogadas** (só conta com alguém online) | ✅ (R) ano de 80 h. O clima sai do tempo do mundo, que para sem ninguém online |
| Neve depende do relevo: altitude neva em certos períodos; às vezes neva em tudo (baixadas menos) | ✅ neve fraca desce a linha de neve das montanhas até os morros (a baixada fica verde); nevasca (rara) neva em tudo, e as baixadas pegam menos (no máximo metade na beira do rio). No inverno os picos ficam brancos mesmo sem nevar |
| A água congela, mas o rio da baixada nunca congela inteiro (beber nunca fica impossível) | ✅ (R) os 30% mais baixos do rio nunca congelam; os bots procuram água aberta |
| Escassez com causa plausível (chuva forte, seca...) | ✅ (R) chuva forte (tempestade, ou chuva mais de 20 min seguidos): arbustos rebrotam a 60%; seca: a 40% |
| Seca: rio pequeno seca, rio gigante só diminui | ✅ (R) em metade dos anos, nas últimas 6 h do verão (sem chuva): o rio baixa até ficar com 60% da largura e os pontos de beber vão junto. O mapa não tem água pequena (poças, lagos, afluentes), então só o rio encolhe |
| Morte por raio **só para bots**, nunca para jogadores | ✅ (R) só em tempestade, com 5% de chance por minuto; atinge um bot ativo (nunca jogador nem bot congelado), que morre de "raio" e vira carcaça. Clarão e risco de luz na tela |
| (R) Dia e noite: um dia dura 1 h jogada (40 min claro + 20 min de noite) | ✅ amanhecer e entardecer suaves (4 min); a noite é escura mas dá pra jogar (lua e luz azulada). Relógio do HUD: claro das 05:00 às 21:00 |
| (R) Neve acumulada derrete aos poucos depois da nevasca | ✅ derrete toda em 2 h de mundo sem nevar |

Clima da v0.5 (números em `config.gd`, seção "Clima"; todos (R)):

| Tempo | Primavera | Verão | Outono | Inverno |
|---|---|---|---|---|
| Limpo | 40% | 55% | 30% | 25% |
| Nublado | 30% | 25% | 35% | 30% |
| Chuva | 22% | 12% | 25% | — |
| Tempestade (com raio) | 8% | 8% | 10% | — |
| Neve | — | — | — | 37% |
| Nevasca | — | — | — | 8% |

- O tempo muda a cada 20 min de mundo. O primeiro bloco de um mundo novo é sempre limpo.
- Neve acumulada: neve fraca enche até 60% em 40 min (a linha de neve vai de 50 m até ~14 m de
  altura: só montanhas e morros); nevasca enche tudo em 15 min; sem nevar, derrete em 2 h.
- No HUD: "Dia 12 · Verão · 14:20" e "Tempo: Chuva" (ou "Limpo · seca").
- Comandos de dev (servidor `--dev`): `/time inverno`, `/time 22:00`, `/time +30m` (só pra
  frente), `/time seca`; `/weather nevasca 20` (força por N min, só até o servidor reiniciar;
  `/weather auto` volta ao normal); `/clima` (estado completo); `/raio` (cai um raio num bot).
- Como funciona: o clima é calculado da semente do mapa + tempo do mundo, igual no servidor e
  nos jogadores. Não precisou de mensagem nova na rede nem de mudar o save.

## 12. Códigos de resgate (R)

Ideia do Tux (24/10). As recompensas são recomendação aprovada pelo Marcelo (28/10); tudo fica em
`scripts/sim/rewards.gd` e `config.gd`, pra mudar fácil.

| Decisão | Status |
|---|---|
| Admins (criam e cancelam códigos no jogo): **Tux e Marcelo**, por nome de conta (`DEFAULT_ADMINS`; o servidor troca com `--admins=Nome1,Nome2`) | ✅ aba Admin das configurações, só aparece pra admin; o servidor confere tudo |
| O jogador resgata na aba **Conta**; cada conta usa um mesmo código uma vez só | ✅ |
| Código: `DINO-XXXX-XXXX`, sem 0/O/1/I; escolhe quantas pessoas podem usar e por quantos dias vale | ✅ 5 códigos errados num minuto bloqueiam a conta por 1 minuto |
| **Boost de crescimento**: +50% de velocidade por 60 min (o admin escolhe de 5 a 600 min); só gasta enquanto o dino cresce, não se perde ao sair nem ao morrer | ✅ |
| **Acesso beta**: libera as espécies marcadas `beta` | ✅ (hoje nenhuma espécie é beta) |
| **Liberar espécie**: libera uma espécie marcada `locked` | ✅ (hoje nenhuma é trancada) |
| **Não existe** recompensa de "level" nem de virar adulto na hora: chegar no adulto é a parte difícil (seção 9) e quem morre recomeça jovem | ✅ |

---

## Decisões de engenharia (Tux + Claude)

- **Engine: Godot 4.7.2**, GDScript. O Marcelo aceitou.
- Renderizador **Compatibilidade** (OpenGL): roda em qualquer PC, inclusive com vídeo integrado.
  Dá pra trocar pra Forward+ quando entrarem modelos e efeitos pesados.
- Servidor autoritativo para tudo que importa (vida, fome, sede, mordida, morte, bots, relógio).
  O **movimento do próprio dino é calculado no PC do jogador** e enviado ao servidor: é um jogo
  de 5 amigos, anticheat não importa, e assim o controle fica suave mesmo com ping.
- Identidade do jogador = **nome + senha** (Tux, 24/10/2026). O primeiro a entrar com um nome
  define a senha dele (vale pra quem já tinha dino salvo). A senha não viaja: o jogo manda uma
  chave derivada dela, e o servidor guarda só um hash, em `<save>.contas.json`. 5 senhas erradas
  seguidas bloqueiam o nome por 1 minuto.
- Mapa gerado por código com semente fixa (servidor e clientes geram o mesmo terreno), com um
  rio atravessando e montanhas na borda. O **tamanho é escolhido no servidor** (`--map-size`,
  padrão 2 km) e vai pros clientes no login; rio, arbustos e água escalam junto. Com 512 m o
  terreno é exatamente o da v0.1.
- Os modelos da v0.1 são montados **a partir das próprias esferas da hitbox**: o que se vê é
  exatamente o que a mordida acerta. Saem quando entrarem modelos 3D de verdade.
- Save do servidor: um JSON (`world.json`), gravado a cada 30 s, a cada saída e a cada morte.
- Rede entre amigos: o servidor fica em casa, provavelmente atrás de CGNAT. Plano:
  **Tailscale** (ou ZeroTier/Radmin) em todos os PCs. Ver README.

## Valores de equilíbrio (ajustar jogando)

| Espécie | Tipo | Massa adulta | Vida adulta | Dano adulto | Crescer até adulto |
|---|---|---|---|---|---|
| Carnotaurus | carnívoro | 1.500 kg | 1.200 | 140 (mordida) | 2 h jogadas (R) |
| Triceratops | herbívoro (revida) | 6.000 kg | 2.200 | 160 (chifrada) | 3 h jogadas (R) |
| Dryosaurus | herbívoro (foge) | 90 kg | 250 | 15 (coice) | 1 h jogada (R) |

- Dano por parte atingida: cabeça 1,25x · pescoço 1,2x · peito 1,05x · tronco 1x · pernas 0,9x · cauda 0,6x.
- Vida e dano escalam com o tamanho (filhote de carnotauro morde com ~10% da força do adulto).
- Tempo pra esvaziar o estômago andando: Carnotaurus adulto ~40 min, Triceratops ~57 min,
  Dryosaurus ~20 min. Filhotes esvaziam mais rápido (no máximo 2x mais rápido).
- Fome ou sede zerada: para de curar, o fôlego recupera pela metade e a vida cai devagar
  (~17 min de vida cheia até morrer).
- Cura (bem alimentado): vida cheia em ~8 min; descansando, ~4 min.
- Ferimentos: ver a tabela da seção 6 (sangramento 3 min, fratura 10 min, mordida funda 6 min).

## Em aberto (perguntar ao Marcelo)

Nada pendente. Em 28/10/2026 o Marcelo mandou seguir as recomendações do Claude em tudo que estava aqui. Elas
viraram decisões (R) nas seções acima. O questionário (página privada do Tux no claude.ai:
https://claude.ai/artifact/PYs4dFwZ2Lbkp6Cv7x14Q7) continua lá caso ele queira mudar alguma.
