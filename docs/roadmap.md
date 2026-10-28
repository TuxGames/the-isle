# Roadmap

## ✅ v0.1: protótipo jogável (outubro/2026)

- Mapa 512 m gerado por semente, com rio, arbustos e montanhas na borda
- 3 espécies com formas simples: Carnotaurus, Triceratops, Dryosaurus
- Movimento, corrida com fôlego, mordida com hitbox de verdade, comer, beber, descansar
- Fome/sede por desgaste físico, cura, crescimento; morreu → recomeça jovem
- Bots: vagam em manada, comem, bebem, descansam, caçam, revidam, fogem com pouca vida;
  bot morto é reposto mantendo 65% herbívoros
- Servidor dedicado headless (até 5 jogadores), login por nome, save em JSON
- Saiu → dino some e congela; sem ninguém online → mundo para
- Chat e comandos de dev (`/grow`, `/tp`, `/hp`, `/food`, `/kill`, `/spawn`, `/bots`)
- 34 testes de unidade + teste de rede com servidor e clientes reais

## v0.2: população e distância (em andamento)

1. ✅ **Congelar bots longe dos jogadores** (faixas de distância do Marcelo, contando o jogador
   mais próximo; histerese pra não ficar liga/desliga na borda). `/bots` mostra as faixas.
2. ✅ **Diretor de população**: concentrar bots perto dos jogadores; espalhar quando eles estão
   separados; carnívoros com fome → mais herbívoros na área. Age na reposição e mudando de lugar
   bots congelados.
3. ✅ **Aumentar o mapa** e subir o padrão pra ~70 bots: mapa de **2 km** e **70 bots** (R).
   Terreno desenhado por partes no cliente; trocar o tamanho leva os dinos dos jogadores
   junto. Com 2048 m e 70 bots o `--bench` deu ~3% de um núcleo.
4. Testar o servidor no Lenovo de verdade (CPU/RAM com 5 jogadores + 70 bots). A ferramenta
   está pronta (`testar_desempenho.bat` no zip, ou `--bench`); falta rodar no Lenovo e colar
   o resultado aqui.

Extras (pedidos do Tux):
- ✅ Login com senha (a conta guarda o seu dino; ninguém mais entra com o seu nome).
- ✅ Tela de configurações (menu e Esc): vídeo (tela cheia, VSync, limite de FPS, distância de
  visão, sombras, campo de visão), controles (sensibilidade, inverter vertical), interface (ajuda
  na tela) e Conta (trocar senha, esquecer a senha lembrada). Fica no PC do jogador.
- ✅ Códigos de resgate (R) com painel de admin (Tux e Marcelo): boost de crescimento, acesso
  beta e liberar espécie. Sem level e sem virar adulto na hora (design, seção 12).
- ✅ Aviso de versão nova: o menu confere a última Release no GitHub e mostra "Baixar"; o erro
  de "versão diferente" também leva pra página de downloads.

## v0.3: ferimentos e rastro

- ✅ Ferimentos (R, design seção 6): **sangramento** (golpe de mais de 15% da vida: não cura e
  perde vida por 3 min), **fratura** (golpe de um bicho 3x mais pesado: 60% da velocidade, sem
  correr e mancando por 10 min) e **mordida funda** (cura pela metade por 6 min). Descansar sara
  2x mais rápido. Valem pra bots e jogadores, vão pro save (formato 4) e congelam com quem sai.
  HUD mostra cada um com o tempo que falta; `/hurt` (dev) abre ou cura.
- ✅ Habilidade de faro (R, design seção 10): tecla F mostra por 8 s, em amarelo, as pegadas
  dos outros dinos dos últimos 2 min e as carcaças com carne, num raio por espécie (40 a 80 m);
  recarga de 30 s.

## v0.4: reprodução

- ✅ Reprodução (R, design seção 8): ninho segurando **N** (adulto, alimentado, sem sangrar,
  parado 8 s em chão firme), parceiro com **R** (bot aceita ou recusa; jogador tem 15 s pra
  confirmar), postura de 2 a 4 ovos por espécie, recarga de 2 h, incubação de 20 min de mundo.
  Um ovo fica pronto pro dono ("Nascer no ninho" na tela de morte, como filhote); os outros
  viram bots filhotes (até 100 bots). Carnívoro come ovo (jogador e bot com fome); 25% das
  reposições de bot viram ninho de bot. Ninhos no save (formato 5); `/nest`, `/eggs`, `/hatch` (dev).

## v0.5: clima e estações

- Calendário 9X/X, ciclo de ~80 h jogadas, neve por altitude, seca, rios que encolhem,
  raio só em bots.
- Dia e noite (R): dia de 1 h jogada (40 min claro + 20 min de noite); neve derrete aos poucos (R).

## Paralelo (Marcelo)

- Modelos e animações de dinossauro (Fab, Sketchfab, itch.io), conferindo a licença.
  Formato ideal para o Godot: **.glb** com as animações dentro.
- Lista final de espécies e valores de equilíbrio.
