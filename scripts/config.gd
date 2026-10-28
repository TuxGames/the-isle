class_name GameConfig
extends RefCounted
## Constantes globais do jogo. Valores de equilíbrio das espécies ficam em data/species.gd.

## Mude sempre que o protocolo de rede ou o formato do save mudar.
## Cliente e servidor com versões diferentes não se conectam.
const VERSION := "0.3.0"

const DEFAULT_PORT := 7777

## Onde o jogo confere se saiu versão nova (menu inicial) e a página pra baixar.
const RELEASES_API := "https://api.github.com/repos/TuxGames/the-isle/releases/latest"
const RELEASES_PAGE := "https://github.com/TuxGames/the-isle/releases/latest"
const MAX_PLAYERS := 5

## Semente do mapa v0.1. Servidor e clientes geram o mesmo terreno a partir dela.
const WORLD_SEED := 20261014

## Lado do mapa em metros quando o servidor não escolhe outro (--map-size=N, de 256 a 8192).
## 2 km (uns 7 min andando de um lado ao outro): recomendação aprovada pelo Marcelo (28/10).
## Pra mudar: troque aqui e o --map-size do iniciar_servidor.bat. Os dinos dos jogadores vão
## junto pro mapa novo (WorldSim.adopt_players); só os bots recomeçam.
const DEFAULT_MAP_SIZE := 2048.0

## Frequências (por segundo).
const SIM_HZ := 20.0
const SNAPSHOT_HZ := 15.0
const SELF_STATS_HZ := 10.0
const CLIENT_SEND_HZ := 20.0

const SAVE_INTERVAL_S := 30.0

## População de bots. Design: média ~70, máximo 100. Ajuste com --bots=N no servidor.
const DEFAULT_BOT_TARGET := 70
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

## Quem sai do jogo até esse tempo depois de levar um golpe deixa o dino mais esse tempo no
## mundo, parado e vulnerável (não dá pra fugir de uma briga fechando o jogo). Recomendação
## aprovada pelo Marcelo (28/10). 0 desliga.
const COMBAT_LOGOUT_S := 10.0

## Faro (design, seção 10; números R). Cada dino que anda deixa uma pegada a cada
## SCENT_SPACING_M metros; elas duram SCENT_MAX_AGE_S de mundo (que para sem ninguém online).
## Raio do faro por espécie: `smell_radius` em species.gd.
const SCENT_SPACING_M := 3.0
const SCENT_MAX_AGE_S := 120.0
## Limite de pegadas guardadas no servidor (as mais velhas saem antes).
const SCENT_MAX_PRINTS := 8000
## Pulo maior que isso num passo é teleporte (spawn, /tp, diretor): não deixa rastro.
const SCENT_TELEPORT_M := 25.0
## Quanto tempo o rastro fica na tela e de quanto em quanto tempo dá pra farejar de novo.
const SNIFF_SHOW_S := 8.0
const SNIFF_COOLDOWN_S := 30.0

## Clima, estações e dia/noite (design, seção 11; ver sim/climate.gd). (R) recomendação aprovada
## pelo Marcelo: ajuste aqui. Tudo é tempo de MUNDO, que para quando ninguém está online. O clima
## é calculado da semente do mapa + tempo do mundo (servidor e cliente chegam no mesmo resultado).
## Dia de 1 h de mundo: 40 min claro + 20 min de noite. O mundo começa no nascer do sol.
const DAY_S := 3600.0
const NIGHT_S := 1200.0
## Amanhecer e entardecer: a luz sobe e desce suave ao longo desse tempo.
const TWILIGHT_S := 240.0
## Hora do relógio do HUD no nascer do sol (o dia de 1 h vira 24 h no relógio: 05:00 às 21:00 claro).
const CLOCK_SUNRISE_H := 5.0
## Estações em horas de mundo: primavera, verão, outono, inverno (ano de 80 h; o ano começa na
## primavera). Favorável (primavera + verão) = 56 h ≈ 9X; inverno = 12 h ≈ 2X, com X ≈ 6 h:
## predomina o verão, como o Marcelo pediu. Use múltiplos de 20 min (WEATHER_BLOCK_S).
const SEASON_HOURS := [14.0, 42.0, 12.0, 12.0]
## O tempo (limpo, chuva...) muda em blocos desse tamanho, sorteados pela semente do mapa.
## O primeiro bloco de um mundo novo é sempre limpo.
const WEATHER_BLOCK_S := 1200.0
## Peso de cada tempo por estação: [limpo, nublado, chuva, tempestade, neve, nevasca].
## Neve e nevasca só no inverno; nevasca é rara.
const WEATHER_CHANCES := [
	[40, 30, 22, 8, 0, 0],  # primavera
	[55, 25, 12, 8, 0, 0],  # verão
	[30, 35, 25, 10, 0, 0],  # outono
	[25, 30, 0, 0, 37, 8],  # inverno
]
## Neve acumulada (0 a 1): a "linha de neve" desce de SNOW_LINE_HIGH_M (0) até SNOW_LINE_LOW_M (1);
## acima dela o chão fica branco (de 0 a 100% em SNOW_FADE_M metros). Baixadas (abaixo de
## SNOW_LOWLAND_M) pegam menos: no rio, no máximo SNOW_LOWLAND_MIN.
const SNOW_LINE_HIGH_M := 50.0
const SNOW_LINE_LOW_M := -10.0
const SNOW_FADE_M := 10.0
const SNOW_LOWLAND_M := 12.0
const SNOW_LOWLAND_MIN := 0.5
## Neve fraca: acumula até SNOW_LIGHT_MAX (a linha desce até os morros) em SNOW_LIGHT_FILL_S.
## Nevasca: enche tudo (1,0) em BLIZZARD_FILL_S. No inverno os picos ficam brancos mesmo sem
## nevar (WINTER_SNOW_MIN). Sem nevar, a neve acumulada derrete toda em SNOW_MELT_S (2 h).
const SNOW_LIGHT_MAX := 0.6
const SNOW_LIGHT_FILL_S := 2400.0
const BLIZZARD_FILL_S := 900.0
const WINTER_SNOW_MIN := 0.2
const SNOW_MELT_S := 7200.0
## Inverno: fome x1,3; corrida x0,85 onde o chão está todo branco (proporcional à neve no chão);
## bot carnívoro só caça com a fome abaixo de WINTER_HUNT_HUNGER (normal: 60, em bot_brain.gd);
## a população-alvo de bots cai pra 80% (ninguém é morto pra isso: só repõe menos).
const WINTER_HUNGER_MULT := 1.3
const SNOW_SPRINT_MULT := 0.85
const WINTER_HUNT_HUNGER := 40.0
const WINTER_BOT_TARGET_MULT := 0.8
## A água congela no trecho do rio em que a neve nas margens passa de WATER_FREEZE_COVER. Os trechos
## mais baixos do rio (a baixada, RIVER_NEVER_FREEZE do comprimento) nunca congelam: sempre dá pra beber.
const WATER_FREEZE_COVER := 0.5
const RIVER_NEVER_FREEZE := 0.3
## Verão: arbustos rebrotam 50% mais rápido e a reposição de bots mira 70% de herbívoros
## (sempre dentro dos limites do diretor: HERBIVORE_SHARE ± DIRECTOR_SHARE_TOLERANCE).
const SUMMER_REGROW_MULT := 1.5
const SUMMER_HERBIVORE_SHARE := 0.7
## Seca: em DROUGHT_CHANCE dos anos, nas últimas DROUGHT_S do verão (sem chuva). O rio baixa até
## ficar com DROUGHT_RIVER_WIDTH da largura (leva DROUGHT_RAMP_S pra baixar e, no outono, o mesmo
## pra voltar) e os arbustos rebrotam a DROUGHT_REGROW_MULT. O mapa não tem água pequena
## (poças, lagos): só o rio encolhe.
const DROUGHT_CHANCE := 0.5
const DROUGHT_S := 21600.0
const DROUGHT_RAMP_S := 3600.0
const DROUGHT_RIVER_WIDTH := 0.6
const DROUGHT_REGROW_MULT := 0.4
## Chuva forte (tempestade, ou chuva há mais de um bloco seguido) encharca: rebrota x0,6.
const HEAVY_RAIN_REGROW_MULT := 0.6
## Raio: só em tempestade; a cada minuto de mundo, essa chance de cair um. Só mata BOT (nunca jogador).
const LIGHTNING_CHANCE_PER_MIN := 0.05

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

## Ferimentos (design, seção 6; ver sim/injuries.gd). (R) recomendação aprovada pelo Marcelo:
## ajuste aqui. Tempos em segundos de mundo; só correm com o dino no mundo (quem sai fica
## congelado com eles). Cada espécie sara no ritmo de "injury_heal" (species.gd).
## Sangramento: golpe que tira mais que essa fração da vida máxima. Enquanto sangra o bicho não
## cura e perde BLEED_LOSS_PER_MIN da vida máxima por minuto (3 min = 15% no total).
const BLEED_MIN_DAMAGE := 0.15
const BLEED_S := 180.0
const BLEED_LOSS_PER_MIN := 0.05
## Fratura: golpe de um bicho pelo menos FRACTURE_MASS_RATIO vezes mais pesado. Anda nessa
## fração da velocidade e não corre.
const FRACTURE_MASS_RATIO := 3.0
const FRACTURE_S := 600.0
const FRACTURE_SPEED_MULT := 0.6
## Mordida funda: golpe que tira mais que DEEP_MIN_DAMAGE da vida máxima, ou mais que
## DEEP_HEAD_DAMAGE na cabeça ou no pescoço. A cura de vida fica multiplicada por DEEP_HEAL_MULT.
const DEEP_MIN_DAMAGE := 0.25
const DEEP_HEAD_DAMAGE := 0.10
const DEEP_S := 360.0
const DEEP_HEAL_MULT := 0.5
## Descansando parado, os ferimentos saram tantas vezes mais rápido.
const INJURY_REST_MULT := 2.0

## Segundos de mundo até um bot morto ser reposto.
const BOT_RESPAWN_DELAY_S := 30.0
## Segundos de mundo até uma carcaça sumir (se não for comida antes).
const CARCASS_LIFETIME_S := 900.0
