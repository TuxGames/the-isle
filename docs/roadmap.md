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

## v0.2: população e distância (próximo)

1. **Congelar bots longe dos jogadores** (faixas de distância do Marcelo, contando o jogador
   mais próximo; histerese pra não ficar liga/desliga na borda).
2. **Diretor de população**: concentrar bots perto dos jogadores; espalhar quando eles estão
   separados; carnívoros com fome → mais herbívoros na área.
3. Subir o padrão pra ~70 bots e aumentar o mapa (precisa da etapa 1).
4. Testar o servidor no Lenovo de verdade (CPU/RAM com 5 jogadores + 70 bots).

## v0.3: ferimentos e rastro

- Lista de ferimentos montada com o Marcelo (fratura, sangramento...) com penalidades
  e tempos de cura por espécie e por atacante.
- Habilidade de faro: pegadas/cheiro em amarelo por alguns segundos.

## v0.4: reprodução

- Parceiro, ninho, ovos, filhotes; comer ovos de outros ninhos.

## v0.5: clima e estações

- Calendário 9X/X, ciclo de ~80 h jogadas, neve por altitude, seca, rios que encolhem,
  raio só em bots.

## Paralelo (Marcelo)

- Modelos e animações de dinossauro (Fab, Sketchfab, itch.io), conferindo a licença.
  Formato ideal para o Godot: **.glb** com as animações dentro.
- Lista final de espécies e valores de equilíbrio.
