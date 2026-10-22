# Design do jogo — decisões consolidadas

Fonte: conversas do Marcelo (idealizador) com o ChatGPT em 13–14/10/2026, mais as decisões
de engenharia tomadas em 20/10/2026 com o Tux.

**Regra de ouro deste documento:** aqui só entra o que o Marcelo *decidiu*. Sugestões que o
ChatGPT fez e o Marcelo não confirmou (ou corrigiu depois) ficam na seção "Em aberto" ou não
entram. Quando o Marcelo mudar de ideia, atualiza aqui primeiro, código depois.

Status de cada item: ✅ implementado · 🟡 parcial · ⬜ futuro

> Nome do jogo: a definir. "The Isle" é o nome do jogo comercial que serviu de inspiração —
> serve como nome do repositório, não como nome final.

---

## 1. Formato do jogo

| Decisão | Status |
|---|---|
| Jogo próprio, inspirado em The Isle (não é mod nem servidor do The Isle) | ✅ |
| Instalado no PC (não roda no navegador) | ✅ |
| Máximo de **5 jogadores** simultâneos | ✅ |
| Servidor dedicado num PC separado ligado 24h (Lenovo IdeaPad S145: i5 8ª geração, 8 GB RAM, HD 1 TB — specs lidas de etiqueta, confirmar) | ✅ (roda headless) |
| Os jogadores só renderizam; o servidor cuida da simulação | ✅ |
| Referência visual: The Isle | ⬜ (v0.1 usa formas simples no lugar dos modelos) |

## 2. Tempo do mundo e logout

| Decisão | Status |
|---|---|
| **Sem nenhum jogador conectado, o mundo inteiro fica parado** (nada envelhece, cura, passa fome, muda de estação) | ✅ |
| Com pelo menos 1 jogador conectado o mundo roda — quem voltar depois pode encontrar o mundo mudado | ✅ |
| **Ao sair, o dino do jogador é deslogado**: some do mundo, não pode ser atacado, não cura, não passa fome, não cresce — volta exatamente igual | ✅ |
| Ao morrer, o jogador **obrigatoriamente recomeça jovem** | ✅ |

## 3. População de bots

| Decisão | Status |
|---|---|
| População média **~70 bots**, **máximo 100** | 🟡 (v0.1 testa com 16; o limite é configurável) |
| Bots têm acesso a todas as espécies que o jogador tem | ✅ |
| Bem mais herbívoros que carnívoros, "mas não muito mais" | ✅ (65% / 35%) |
| Carnívoros também se atacam entre si | ✅ |
| **Hitbox plausível**: só toma dano se a mordida realmente acertar | ✅ |
| A maioria dos bots fica congelada (longe dos jogadores) | ⬜ v0.2 |
| **Bot morreu → obrigatoriamente entra outro** (não precisa ser da mesma espécie) | ✅ |
| Jogadores juntos → concentra bots perto deles; separados → espalha, sempre com população considerável perto de cada um | ⬜ |
| Jogadores carnívoros com fome → mais herbívoros na área; herbívoro demais → mais carnívoros | ⬜ |

## 4. IA

| Decisão | Status |
|---|---|
| Animal ataca ou foge de acordo com o % de vida (pouca vida → foge) | ✅ |
| Comportamento orgânico/natural, sem exagero | 🟡 |

## 5. Distância e carregamento do mapa

| Decisão | Status |
|---|---|
| Mapa grande, mas só carrega a área num raio grande em volta de cada jogador | ⬜ |
| Simulação por faixas de distância (exemplo do Marcelo: >15 células estático; ~10 começa a ativar; ≤5 normal) | ⬜ v0.2 |
| Bot longe congelado: ferido continua ferido, luta congela | ⬜ v0.2 |
| A distância considera o jogador mais próximo, não só o host | ⬜ v0.2 |

## 6. Ferimentos e cura

| Decisão | Status |
|---|---|
| Recuperação diferente por espécie e por tipo/grau de ferimento | ⬜ |
| Exemplo: animal pequeno mordido por um muito grande pode quebrar osso → demora mais | ⬜ |
| Cura acelerada: ~10 min dependendo do ferimento, nada de horas | 🟡 (v0.1: cura genérica de vida) |
| Lista de ferimentos: **vai ser montada com o Marcelo** | ⬜ |

## 7. Fome, sede e metabolismo

| Decisão | Status |
|---|---|
| Fome vem de **desgaste físico** + tempo sem comer; sede vem de tempo sem beber | ✅ |
| Crescendo → mais fome (moderado, nada absurdo) | ✅ |
| Grande come **mais quantidade**; pequeno come **mais vezes, em menor quantidade** | ✅ |
| Cura e fome têm que ser compatíveis (não pode curar em 2 meses e ter fome em 5 min) | ✅ |
| Nada 100% realista — não pode ficar chato | ✅ |
| Morte é rara/demorada: fome zerada não mata na hora | ✅ |

## 8. Reprodução e ciclo de vida

| Decisão | Status |
|---|---|
| Nascer, crescer, reproduzir e morrer — **reprodução é obrigatória** | ⬜ |
| Encontrar parceiro e construir ninho | ⬜ |
| Dá pra comer ovos de outros ninhos e filhotes | ⬜ |

## 9. Progressão do jogador

| Decisão | Status |
|---|---|
| O jogo favorece o jogador de acordo com a fase: filhote = tranquilo com algum perigo; médio = mais perigo; grande = não impossível | 🟡 (v0.1: filhote nasce longe de carnívoros e é percebido mais tarde pelos bots) |
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
| Ciclo completo longo: **~70–90 horas jogadas** (só conta com alguém online) | 🟡 (o relógio do mundo já existe e pausa) |
| Neve depende do relevo: altitude neva em certos períodos; às vezes neva em tudo (baixadas menos) | ⬜ |
| Escassez com causa plausível (chuva forte, seca...) | ⬜ |
| Seca: rio pequeno seca, rio gigante só diminui | ⬜ |
| Morte por raio **só para bots**, nunca para jogadores | ⬜ |

---

## Decisões de engenharia (Tux + Claude, 20/10/2026)

- **Engine: Godot 4** (versão de referência: 4.7.2). O Marcelo aceitou.
- **GDScript**, servidor autoritativo para tudo que importa (vida, fome, sede, mordida,
  morte, bots, relógio). O **movimento do próprio dino é calculado no PC do jogador** e
  enviado ao servidor: é um jogo de 5 amigos, anti-cheat não importa, e assim o controle
  fica suave mesmo com ping.
- Identidade do jogador = **nome** (sem login). Mesmo nome = mesmo dino salvo.
- Mapa v0.1: **512 m × 512 m** gerado por código com semente fixa (servidor e clientes
  geram o mesmo terreno), com um rio atravessando. Mapa definitivo vem depois.
- Dados de equilíbrio (espécies, metabolismo) ficam em código legível
  (`scripts/data/`), fáceis de ajustar.
- Rede entre amigos: o servidor fica em casa → provavelmente atrás de CGNAT. Plano:
  **Tailscale** (ou ZeroTier/Radmin) em todos os PCs.

## Valores de equilíbrio da v0.1 (provisórios — ajustar jogando)

| Espécie | Tipo | Massa adulta | Vida adulta | Dano adulto | Crescer até adulto |
|---|---|---|---|---|---|
| Carnotaurus | carnívoro | 1.500 kg | 1.200 | 140 (mordida) | 60 min jogados |
| Triceratops | herbívoro (defensivo) | 6.000 kg | 2.200 | 160 (chifrada) | 90 min jogados |
| Dryosaurus | herbívoro (foge) | 90 kg | 250 | 15 (coice) | 30 min jogados |

- Tempo pra esvaziar o estômago andando: Carnotaurus adulto ~40 min, Triceratops ~57 min,
  Dryosaurus ~20 min, filhotes menos (comem mais vezes).
- Fome ou sede zerada: para de curar, fôlego recupera pela metade e a vida cai devagar
  (~17 min de vida cheia até morrer).
- Cura (bem alimentado): vida cheia em ~8 min; descansando, ~4 min.

## Em aberto (perguntar ao Marcelo)

- Lista de ferimentos (tipos, penalidades, tempo de cura por espécie).
- Lista final de espécies e quantas no total.
- Tempo de crescimento real de cada espécie.
- "Começar jovem": jovem mesmo ou filhote/ovo?
- Reprodução entre jogador e bot vale?
- Proteção contra sair do jogo no meio da luta (sugestão do ChatGPT, não decidida).
- Neve acumulada derrete aos poucos depois da nevasca? (pergunta ficou sem resposta)
- Tamanho do mapa final.
