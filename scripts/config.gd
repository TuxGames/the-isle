class_name GameConfig
extends RefCounted
## Constantes globais do jogo. Valores de equilíbrio das espécies ficam em data/species.gd.

## Mude sempre que o protocolo de rede ou o formato do save mudar.
## Cliente e servidor com versões diferentes não se conectam.
const VERSION := "0.2.1"

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 5

## Semente do mapa v0.1. Servidor e clientes geram o mesmo terreno a partir dela.
const WORLD_SEED := 20261014

## Lado do mapa em metros quando o servidor não escolhe outro (--map-size=N, de 256 a 8192).
## O tamanho final ainda é decisão do Marcelo (1, 2 ou 4 km); até lá fica o mapa da v0.1.
const DEFAULT_MAP_SIZE := 512.0

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

## Diretor de população (design, seção 3; ver sim/population_director.gd).
## O comportamento foi decidido pelo Marcelo; TODOS os números abaixo são provisórios.
## Jogadores a menos disso de alguém do grupo contam como um grupo só ("juntos").
const DIRECTOR_GROUP_DIST := 200.0
## "Área" de um grupo: até essa distância do jogador mais próximo dele.
const DIRECTOR_AREA_RADIUS := 260.0
## Parte da população-alvo que o diretor quer nas áreas dos jogadores, dividida igualmente
## entre os grupos (juntos = tudo perto deles; separados = um pedaço pra cada). O resto fica solto.
const DIRECTOR_NEAR_SHARE := 0.6
## Carnívoro jogador com fome abaixo disso puxa herbívoros pra área dele.
const DIRECTOR_HUNGRY := 50.0
## Área com mais que essa fração de herbívoros (e pelo menos DIRECTOR_MIN_LOCAL bots) puxa carnívoros.
const DIRECTOR_HERB_EXCESS := 0.8
const DIRECTOR_MIN_LOCAL := 5
## Quanto a proporção geral pode sair de HERBIVORE_SHARE por causa do diretor (0,1 = 55% a 75%).
const DIRECTOR_SHARE_TOLERANCE := 0.1
## De quanto em quanto tempo (s de mundo) o diretor muda bots congelados de lugar, quantos por vez,
## e quanto tempo um bot que já mudou espera pra poder mudar de novo.
const DIRECTOR_INTERVAL_S := 5.0
const DIRECTOR_RELOCATE_MAX := 2
const DIRECTOR_RELOCATE_COOLDOWN_S := 300.0
## Só muda de lugar bot congelado a pelo menos isso de todos os jogadores (ninguém está vendo).
const DIRECTOR_SOURCE_MIN_DIST := 480.0
## O bot reaparece a pelo menos isso de todos os jogadores (mais longe que a simulação completa).
const DIRECTOR_RELOCATE_MIN_DIST := 180.0

## Crescimento (0 = filhote, 1 = adulto) com que o jogador começa / recomeça.
const PLAYER_START_GROWTH := 0.1

## Códigos de resgate (recomendação aprovada pelo Marcelo, 28/10). Quem cria e revoga códigos,
## por nome de conta, sem diferença de maiúsculas. O servidor troca com --admins=Nome1,Nome2.
const DEFAULT_ADMINS := ["Tux", "Marcelo"]
## Boost de crescimento: cresce esse tanto mais rápido enquanto durar. O tempo só gasta
## enquanto o dino está crescendo de verdade (online, alimentado e ainda não adulto).
const GROWTH_BOOST_MULT := 1.5
## Duração padrão de um código de boost, em minutos (o admin pode escolher outra).
const GROWTH_BOOST_DEFAULT_MIN := 60

## Segundos de mundo até um bot morto ser reposto.
const BOT_RESPAWN_DELAY_S := 30.0
## Segundos de mundo até uma carcaça sumir (se não for comida antes).
const CARCASS_LIFETIME_S := 900.0
