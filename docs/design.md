# Design do jogo: decisões consolidadas

Fonte: conversas do Marcelo (idealizador) com o ChatGPT em 13–14/10/2026, mais as decisões
de engenharia tomadas com o Tux em 20–21/10/2026.

**Regra de ouro deste documento:** aqui só entra o que o Marcelo *decidiu*. Sugestões que o
ChatGPT fez e o Marcelo não confirmou (ou corrigiu depois) ficam em "Em aberto" ou não
entram. Quando o Marcelo mudar de ideia, atualiza aqui primeiro e no código depois.

Status de cada item (situação na **v0.1**): ✅ implementado e testado · 🟡 parcial · ⬜ futuro

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
| Ao morrer, o jogador **obrigatoriamente recomeça jovem** | ✅ |

## 3. População de bots

| Decisão | Status |
|---|---|
| População média **~70 bots**, **máximo 100** | 🟡 o padrão é 20 porque o mapa da v0.1 é pequeno (512 m); `--bots=N` vai até 100. Carga testada com 70 e 100 |
| Bots têm acesso a todas as espécies que o jogador tem | ✅ (as 3 que existem) |
| Bem mais herbívoros que carnívoros, "mas não muito mais" | ✅ (65% / 35%) |
| Carnívoros também se atacam entre si | ✅ (carnívoro com fome ataca carnívoro menor; canibalismo só morrendo de fome) |
| **Hitbox plausível**: só toma dano se a mordida realmente acertar | ✅ |
| A maioria dos bots fica congelada (longe dos jogadores) | 🟡 congelamento pronto (ver seção 5). No mapa de 512 m quase nada fica longe o bastante; com 2 km e 70 bots, 40 a 66 ficam congelados (`--bench --map-size=2048`) |
| **Bot morreu → obrigatoriamente entra outro** (não precisa ser da mesma espécie) | ✅ entra 30 s depois, fora da vista dos jogadores, mantendo os 65/35 |
| Jogadores juntos → concentra bots perto deles; separados → espalha, sempre com população considerável perto de cada um | ✅ diretor de população: cada grupo de jogadores (a até 200 m um do outro) quer 60% da população dividida pelo número de grupos, na área de 260 m em volta. Age na reposição e mudando de lugar bots congelados que ninguém vê. Números provisórios. No mapa de 512 m quase nada congela, então hoje só a reposição age |
| Jogadores carnívoros com fome → mais herbívoros na área; herbívoro demais → mais carnívoros | ✅ "com fome" = fome abaixo de 50; "herbívoro demais" = mais de 80% da área. A proporção geral só sai 10% dos 65/35. Números provisórios |

## 4. IA

| Decisão | Status |
|---|---|
| Animal ataca ou foge de acordo com o % de vida (pouca vida → foge) | ✅ |
| Comportamento orgânico/natural, sem exagero | 🟡 vaga em manada, bebe, come, descansa, caça, foge, revida. Falta ajustar jogando |

## 5. Distância e carregamento do mapa

| Decisão | Status |
|---|---|
| Mapa grande, mas só carrega a área num raio grande em volta de cada jogador | 🟡 pronto pra qualquer tamanho (`--map-size`, de 256 m a 8 km): o cliente só desenha ~1,1 km em volta do jogador, com menos detalhe longe. O padrão continua 512 m até o Marcelo decidir o tamanho |
| Simulação por faixas de distância (exemplo do Marcelo: >15 células estático; ~10 começa a ativar; ≤5 normal) | ✅ com células de 32 m: até 160 m roda normal (20 Hz); mais longe roda a 10 Hz; congela acima de 480 m e só acorda a 320 m (histerese). Metros escolhidos pelo Tux, falta o Marcelo confirmar |
| Bot longe congelado: ferido continua ferido, luta congela | ✅ e enquanto congelado ninguém enxerga, persegue ou morde ele |
| A distância considera o jogador mais próximo, não só o host | ✅ |

## 6. Ferimentos e cura

| Decisão | Status |
|---|---|
| Recuperação diferente por espécie e por tipo/grau de ferimento | ⬜ |
| Exemplo: animal pequeno mordido por um muito grande pode quebrar osso → demora mais | ⬜ |
| Cura acelerada: ~10 min dependendo do ferimento, nada de horas | 🟡 (v0.1: cura genérica de vida, cheia em 8 min, 4 min descansando) |
| Lista de ferimentos: **vai ser montada com o Marcelo** | ⬜ |

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
| Dá pra comer ovos de outros ninhos e filhotes | 🟡 filhotes podem ser caçados; ovos ⬜ |

## 9. Progressão do jogador

| Decisão | Status |
|---|---|
| O jogo favorece o jogador de acordo com a fase: filhote = tranquilo com algum perigo; médio = mais perigo; grande = não impossível | 🟡 (filhote nasce longe de carnívoros e os bots só percebem ele mais perto) |
| T-Rex, Espinossauro e Giganotossauro adultos dominam com facilidade (chegar no adulto é a parte difícil) | ⬜ (espécies ainda não existem) |
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

---

## Decisões de engenharia (Tux + Claude)

- **Engine: Godot 4.7.2**, GDScript. O Marcelo aceitou.
- Renderizador **Compatibilidade** (OpenGL): roda em qualquer PC, inclusive com vídeo integrado.
  Dá pra trocar pra Forward+ quando entrarem modelos e efeitos pesados.
- Servidor autoritativo para tudo que importa (vida, fome, sede, mordida, morte, bots, relógio).
  O **movimento do próprio dino é calculado no PC do jogador** e enviado ao servidor: é um jogo
  de 5 amigos, anticheat não importa, e assim o controle fica suave mesmo com ping.
- Identidade do jogador = **nome** (sem login). Mesmo nome = mesmo dino salvo.
- Mapa gerado por código com semente fixa (servidor e clientes geram o mesmo terreno), com um
  rio atravessando e montanhas na borda. O **tamanho é escolhido no servidor** (`--map-size`,
  padrão 512 m, o da v0.1) e vai pros clientes no login; rio, arbustos e água escalam junto.
  O mapa definitivo vem depois.
- Os modelos da v0.1 são montados **a partir das próprias esferas da hitbox**: o que se vê é
  exatamente o que a mordida acerta. Saem quando entrarem modelos 3D de verdade.
- Save do servidor: um JSON (`world.json`), gravado a cada 30 s, a cada saída e a cada morte.
- Rede entre amigos: o servidor fica em casa, provavelmente atrás de CGNAT. Plano:
  **Tailscale** (ou ZeroTier/Radmin) em todos os PCs. Ver README.

## Valores de equilíbrio da v0.1 (provisórios, ajustar jogando)

| Espécie | Tipo | Massa adulta | Vida adulta | Dano adulto | Crescer até adulto |
|---|---|---|---|---|---|
| Carnotaurus | carnívoro | 1.500 kg | 1.200 | 140 (mordida) | 60 min jogados |
| Triceratops | herbívoro (revida) | 6.000 kg | 2.200 | 160 (chifrada) | 90 min jogados |
| Dryosaurus | herbívoro (foge) | 90 kg | 250 | 15 (coice) | 30 min jogados |

- Dano por parte atingida: cabeça 1,25x · pescoço 1,2x · peito 1,05x · tronco 1x · pernas 0,9x · cauda 0,6x.
- Vida e dano escalam com o tamanho (filhote de carnotauro morde com ~10% da força do adulto).
- Tempo pra esvaziar o estômago andando: Carnotaurus adulto ~40 min, Triceratops ~57 min,
  Dryosaurus ~20 min. Filhotes esvaziam mais rápido (no máximo 2x mais rápido).
- Fome ou sede zerada: para de curar, o fôlego recupera pela metade e a vida cai devagar
  (~17 min de vida cheia até morrer).
- Cura (bem alimentado): vida cheia em ~8 min; descansando, ~4 min.

## Em aberto (perguntar ao Marcelo)

As perguntas abaixo estão num questionário pro Marcelo responder (página privada do Tux no
claude.ai: https://claude.ai/artifact/PYs4dFwZ2Lbkp6Cv7x14Q7). As respostas ficam no banco da
página, coleção `respostas`, documento `marcelo`. Quando chegarem, passe as decisões pra cá.

- Lista de ferimentos (tipos, penalidades, tempo de cura por espécie).
- Lista final de espécies e quantas no total.
- Tempo de crescimento real de cada espécie (os da tabela são de teste).
- "Começar jovem": jovem mesmo ou filhote/ovo? (v0.1 começa com 10% de crescimento)
- Reprodução entre jogador e bot vale?
- Proteção contra sair do jogo no meio da luta (sugestão do ChatGPT, não decidida).
- Neve acumulada derrete aos poucos depois da nevasca? (a pergunta ficou sem resposta)
- Tamanho do mapa final (pergunta 1 do questionário: 1, 2 ou 4 km). O código já aceita
  qualquer um; falta a escolha. Depois disso sobe o padrão de bots pra ~70 (roadmap v0.2, etapa 3).
- Tamanho da "célula" do exemplo das distâncias. Usamos 32 m (160 / 320 / 480 m). Está bom?
- Números do diretor de população (provisórios, em `config.gd`): o que é "juntos" (200 m),
  o tamanho da área de cada grupo (260 m), quanto da população fica perto dos jogadores (60%),
  o que é "com fome" (abaixo de 50) e "herbívoro demais" (mais de 80% da área), e quanto a
  proporção geral pode sair dos 65/35 por causa disso (10%).
- Equilíbrio: na v0.1 um triceratops adulto mata um carnotauro adulto parado com 6 chifradas
  na cabeça. Está bom assim?
- Ciclo de dia e noite (não foi discutido).
