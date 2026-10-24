# Dino Survival (nome provisório)

Jogo de sobrevivência com dinossauros pra até 5 amigos, inspirado em The Isle.
Feito em **Godot 4.7** com servidor dedicado.

- Ideia e game design: **Marcelo**
- Programação: **Tux** + Claude Code

**Status: v0.1, protótipo jogável.** Mapa pequeno com rio, 3 espécies (Carnotaurus,
Triceratops, Dryosaurus) feitas de formas simples, bots que caçam, fogem e revidam,
fome/sede/crescimento, mordida com hitbox de verdade, multiplayer com servidor dedicado.
O que vem depois: [`docs/roadmap.md`](docs/roadmap.md).

## Jogar

1. Baixe o `.zip` da última versão em **[Releases](../../releases)** e extraia.
2. **Sozinho, pra testar:** abra `DinoSurvival.exe`, digite um nome e uma senha e clique em
   **"Testar sozinho"**.
3. **Com os amigos:** um PC roda o servidor (`iniciar_servidor.bat`) e todo mundo entra
   pelo IP dele. O passo a passo, com Tailscale, está no `LEIA-ME.txt` dentro do zip.

Controles: WASD andar · Shift correr · mouse câmera · clique morder · E (segurar)
comer/beber · C descansar · Enter chat/comandos · Esc menu.

### Por que Tailscale?

A internet de casa no Brasil quase sempre usa CGNAT, e aí abrir porta no roteador não
adianta. O Tailscale (grátis até 100 aparelhos) cria uma rede privada entre os PCs: cada um
recebe um IP `100.x.x.x` e o jogo conecta direto, sem mexer no roteador. Alternativas:
ZeroTier ou Radmin VPN.

### Servidor 24h no notebook

- Deixe o Lenovo na tomada com o **modo de conservação de bateria** ligado (Lenovo Vantage →
  Energia). Sem isso, a bateria estufa ficando sempre a 100%.
- Desative a suspensão automática do Windows.
- Trocar o HD por um SSD barato ajuda muito.
- O servidor não desenha nada. Nos testes, 70 bots custaram ~2 ms por passo de simulação.
- Pra saber se o notebook aguenta, dê dois cliques em `testar_desempenho.bat` (vem no zip).
  Leva cerca de 1 minuto e mostra CPU, RAM, upload e um veredito.

## Desenvolver

Precisa do **Godot 4.7.2** (versão padrão, não a .NET). Abra o `project.godot` no Godot.

```bash
tools/test.sh                     # compilação + testes de unidade + teste de rede
godot --headless --path . -- --server --dev --bots=30      # servidor local
godot --path . -- --connect=127.0.0.1 --name=Tux           # cliente direto, sem menu
tools/export.sh                   # gera o zip pra Windows em build/
```

Antes de mexer, leia:

- [`CLAUDE.md`](CLAUDE.md): regras do projeto (vale pra humanos e pro Claude Code)
- [`docs/design.md`](docs/design.md): decisões de design do Marcelo e o status de cada uma
- [`docs/arquitetura.md`](docs/arquitetura.md): como o código está organizado e o protocolo de rede
- [`docs/roadmap.md`](docs/roadmap.md): versões e próximos passos

> "The Isle" é um jogo comercial da Afterthought que serviu de inspiração. Este projeto não
> usa nenhum arquivo, modelo ou código dele.
