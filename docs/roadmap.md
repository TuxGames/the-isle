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
- Códigos de resgate com painel de admin (Tux e Marcelo): esperando o Marcelo dizer o que um
  código pode dar.

## v0.3: ferimentos e rastro

- Ferimentos (R, design seção 6): sangramento, fratura e mordida funda, com penalidades e
  tempos de cura.
- Habilidade de faro: pegadas/cheiro em amarelo por alguns segundos.

## v0.4: reprodução

- Parceiro (bot ou jogador, R), ninho, ovos, filhotes; comer ovos de outros ninhos.

## v0.5: clima e estações

- Calendário 9X/X, ciclo de ~80 h jogadas, neve por altitude, seca, rios que encolhem,
  raio só em bots.
- Dia e noite (R): dia de 1 h jogada (40 min claro + 20 min de noite); neve derrete aos poucos (R).

## Paralelo (Marcelo)

- Modelos e animações de dinossauro (Fab, Sketchfab, itch.io), conferindo a licença.
  Formato ideal para o Godot: **.glb** com as animações dentro.
- Lista final de espécies e valores de equilíbrio.
