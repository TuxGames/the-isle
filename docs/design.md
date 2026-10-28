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
| **Bot morreu → obrigatoriamente entra outro** (não precisa ser da mesma espécie) | ✅ entra 30 s depois, fora da vista dos jogadores, mantendo os 65/35 |
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
| Recuperação diferente por espécie e por tipo/grau de ferimento | ⬜ |
| Exemplo: animal pequeno mordido por um muito grande pode quebrar osso → demora mais | ⬜ |
| Cura acelerada: ~10 min dependendo do ferimento, nada de horas | 🟡 (v0.1: cura genérica de vida, cheia em 8 min, 4 min descansando) |
| (R) Lista de ferimentos (detalhes e números ajustados ao implementar): **sangramento** (golpe que tira mais de 15% da vida: perde vida devagar por ~3 min), **fratura** (mordida de um bicho pelo menos 3x mais pesado: anda mais devagar e não corre por ~10 min) e **mordida funda** (cura pela metade por ~6 min). Descansar sara mais rápido | ⬜ v0.3 |

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
| Nascer, crescer, reproduzir e morrer. **Reprodução é obrigatória** | 🟡 crescer e morrer ✅; reprodução ⬜ |
| Encontrar parceiro e construir ninho | ⬜ |
| (R) O parceiro pode ser bot ou jogador (com 5 jogadores, exigir parceiro jogador travaria algo que é obrigatório) | ⬜ v0.4 |
| Dá pra comer ovos de outros ninhos e filhotes | 🟡 filhotes podem ser caçados; ovos ⬜ |

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
| Habilidade de faro ativável por um momento, mostrando pegadas/cheiro | ⬜ |
| Visual simples (ex.: rastro amarelo), nada de gráfico pesado | ⬜ |

## 11. Clima e estações

| Decisão | Status |
|---|---|
| Inverno com neve: mais fome, corre menos, água congela, instinto de caça reduzido | ⬜ |
| Inverno: menos população de tudo, mas sem mortandade excessiva | ⬜ |
| Verão: mais comida pros herbívoros → mais herbívoros → carnívoros crescem tranquilos | ⬜ |
| Duração: períodos favoráveis = **9X**; desfavoráveis = **X a 2X**. Predomina verão, com outono/primavera e alguns "meses" de inverno | ⬜ |
| Ciclo completo longo: **~70–90 horas jogadas** (só conta com alguém online) | 🟡 o relógio do mundo existe, aparece no HUD e pausa; estações ⬜ |
| Neve depende do relevo: altitude neva em certos períodos; às vezes neva em tudo (baixadas menos) | ⬜ |
| Escassez com causa plausível (chuva forte, seca...) | ⬜ |
| Seca: rio pequeno seca, rio gigante só diminui | ⬜ |
| Morte por raio **só para bots**, nunca para jogadores | ⬜ |
| (R) Dia e noite: um dia dura 1 h jogada (40 min claro + 20 min de noite) | ⬜ v0.5 |
| (R) Neve acumulada derrete aos poucos depois da nevasca | ⬜ v0.5 |

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

## Em aberto (perguntar ao Marcelo)

Nada pendente. Em 28/10/2026 o Marcelo mandou seguir as recomendações do Claude em tudo que estava aqui. Elas
viraram decisões (R) nas seções acima. O questionário (página privada do Tux no claude.ai:
https://claude.ai/artifact/PYs4dFwZ2Lbkp6Cv7x14Q7) continua lá caso ele queira mudar alguma.
