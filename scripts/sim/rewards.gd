class_name Rewards
extends RefCounted
## O que um código de resgate pode dar (recomendação aprovada pelo Marcelo, 28/10).
## Pra criar uma recompensa nova: uma entrada em TYPES, um caso em validate, describe e apply.
##
## De propósito NÃO existe "level" nem "virar adulto na hora": chegar no adulto é a parte
## difícil (design, seção 9) e quem morre recomeça jovem.
##
## `perks` é o que a conta ganhou (Accounts.perks): {"beta": bool, "species": [ids]}.
## O boost de crescimento fica no dino do jogador (WorldSim.add_growth_boost).

## id -> {"name": texto pro admin, "param": "" | "minutes" | "species"}
const TYPES := {
	"boost_crescimento": {"name": "Boost de crescimento", "param": "minutes"},
	"acesso_beta": {"name": "Acesso beta", "param": ""},
	"liberar_especie": {"name": "Liberar espécie", "param": "species"},
}
## Limites do parâmetro de boost, em minutos.
const BOOST_MIN_MINUTES := 5
const BOOST_MAX_MINUTES := 600


static func ids() -> Array:
	return TYPES.keys()


static func display_name(reward: String) -> String:
	return String(TYPES.get(reward, {}).get("name", reward))


## Parâmetro padrão pra recompensa (o que o painel de admin já mostra preenchido).
static func default_param(reward: String) -> String:
	match String(TYPES.get(reward, {}).get("param", "")):
		"minutes":
			return str(GameConfig.GROWTH_BOOST_DEFAULT_MIN)
		"species":
			return Species.IDS[0]
	return ""


## "" se a recompensa e o parâmetro valem; senão o motivo.
static func validate(reward: String, param: String) -> String:
	if not TYPES.has(reward):
		return "Recompensa desconhecida: \"%s\"." % reward
	match String(TYPES[reward]["param"]):
		"minutes":
			if not param.is_valid_int():
				return "Diga quantos minutos de boost."
			var m := int(param)
			if m < BOOST_MIN_MINUTES or m > BOOST_MAX_MINUTES:
				return "O boost vai de %d a %d minutos." % [BOOST_MIN_MINUTES, BOOST_MAX_MINUTES]
		"species":
			if not Species.is_valid(param):
				return "Espécie desconhecida: \"%s\"." % param
	return ""


## Texto curto do que o código dá ("Boost de crescimento (60 min)").
static func describe(reward: String, param: String) -> String:
	match reward:
		"boost_crescimento":
			return "Boost de crescimento (%s min)" % param
		"liberar_especie":
			return "Liberar %s" % Species.display_name(param)
	return display_name(reward)


## Entrega a recompensa e devolve a mensagem pro jogador. Confira com validate antes.
static func apply(reward: String, param: String, player_name: String, world: WorldSim, perks: Dictionary) -> String:
	match reward:
		"boost_crescimento":
			var total := world.add_growth_boost(player_name, float(param) * 60.0)
			return "Boost de crescimento: +%d%% de velocidade por mais %s min (total: %d min). Só gasta enquanto você cresce." % [
				roundi((GameConfig.GROWTH_BOOST_MULT - 1.0) * 100.0), param, ceili(total / 60.0)]
		"acesso_beta":
			perks["beta"] = true
			return "Acesso beta liberado: você pode escolher as espécies em teste."
		"liberar_especie":
			var list: Array = perks.get("species", [])
			if not list.has(param):
				list.append(param)
			perks["species"] = list
			return "%s liberado: escolha ele quando nascer de novo." % Species.display_name(param)
	return ""
