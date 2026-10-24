class_name GameConfig
extends RefCounted
## Constantes globais do jogo. Valores de equilíbrio das espécies ficam em data/species.gd.

## Mude sempre que o protocolo de rede ou o formato do save mudar.
## Cliente e servidor com versões diferentes não se conectam.
const VERSION := "0.1.0"

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 5

## Semente do mapa v0.1. Servidor e clientes geram o mesmo terreno a partir dela.
const WORLD_SEED := 20261014

## Frequências (por segundo).
const SIM_HZ := 20.0
const SNAPSHOT_HZ := 15.0
const SELF_STATS_HZ := 10.0
const CLIENT_SEND_HZ := 20.0

const SAVE_INTERVAL_S := 30.0

## População de bots. Design: média ~70, máximo 100. O mapa da v0.1 é pequeno
## (512 m), então o padrão é menor; ajuste com --bots=N no servidor.
const DEFAULT_BOT_TARGET := 20
const BOT_MAX := 100
const HERBIVORE_SHARE := 0.65

## Simulação por distância (design, seção 5), contando o jogador mais próximo.
## Exemplo do Marcelo, em "células" de 32 m: até 5 normal, ~10 começa a ativar, mais de 15 parado.
## Até aqui o bot roda todo passo (20 Hz).
const SIM_FULL_DIST := 160.0
## Mais longe que SIM_FULL_DIST o bot roda 1 passo a cada N, com o tempo somado (fome e cura
## andam no mesmo ritmo, só a IA decide menos vezes).
const SIM_REDUCED_EVERY := 2
## Bot ativo congela quando todos os jogadores estão mais longe que isso.
const SIM_FREEZE_DIST := 480.0
## Bot congelado só acorda quando um jogador chega mais perto que isso. A folga até
## SIM_FREEZE_DIST é a histerese: o bot não fica liga/desliga na borda.
const SIM_WAKE_DIST := 320.0

## Crescimento (0 = filhote, 1 = adulto) com que o jogador começa / recomeça.
const PLAYER_START_GROWTH := 0.1

## Segundos de mundo até um bot morto ser reposto.
const BOT_RESPAWN_DELAY_S := 30.0
## Segundos de mundo até uma carcaça sumir (se não for comida antes).
const CARCASS_LIFETIME_S := 900.0
