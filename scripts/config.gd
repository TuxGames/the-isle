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

## Crescimento (0 = filhote, 1 = adulto) com que o jogador começa / recomeça.
const PLAYER_START_GROWTH := 0.1

## Segundos de mundo até um bot morto ser reposto.
const BOT_RESPAWN_DELAY_S := 30.0
## Segundos de mundo até uma carcaça sumir (se não for comida antes).
const CARCASS_LIFETIME_S := 900.0
