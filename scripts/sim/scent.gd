class_name ScentTrail
extends RefCounted
## Pegadas e cheiro pro faro (design, seção 10). Roda no servidor, dentro do WorldSim.
##
## Cada dino que anda deixa uma pegada a cada SCENT_SPACING_M metros, com o world_time da hora.
## Como o world_time para sem ninguém online, as pegadas também não envelhecem com o mundo
## parado. Bot congelado não anda, então não deixa pegada. Pegadas mais velhas que
## SCENT_MAX_AGE_S somem, e nunca guarda mais que SCENT_MAX_PRINTS (as mais velhas saem antes).
## Não vai pro save: depois de reiniciar o servidor o rastro recomeça.

## Floats por item na resposta do faro: x, z, idade (s), índice da espécie, tipo (KIND_*).
const STRIDE := 5
const KIND_PRINT := 0
const KIND_CARCASS := 1

# Pegadas em ordem de tempo (as mais velhas primeiro), a partir de _start.
var _x := PackedFloat32Array()
var _z := PackedFloat32Array()
var _t := PackedFloat32Array()
var _species := PackedInt32Array()
var _owner := PackedInt32Array()
var _start := 0
## id do dino -> onde ele deixou a última pegada (ou onde foi visto pela primeira vez).
var _last := {}


func count() -> int:
	return _x.size() - _start


## Chamado todo passo, depois que todo mundo andou.
func record(world: WorldSim) -> void:
	var seen := {}
	for d: Dino in world.dinos.values():
		if not d.alive or d.sim_tier == WorldSim.SimTier.FROZEN:
			continue
		seen[d.id] = true
		if not _last.has(d.id):
			_last[d.id] = d.pos
			continue
		var last: Vector3 = _last[d.id]
		var dist := Movement.flat_distance(last, d.pos)
		if dist < GameConfig.SCENT_SPACING_M:
			continue
		_last[d.id] = d.pos
		# Pulo grande num passo é teleporte (spawn, /tp, diretor): não deixa rastro.
		if dist > GameConfig.SCENT_TELEPORT_M:
			continue
		add_print(d.pos, world.world_time, Species.index_of(d.species), d.id)
	for id in _last.keys():
		if not seen.has(id) and not world.dinos.has(id):
			_last.erase(id)
	prune(world.world_time)


func add_print(pos: Vector3, t: float, species_index: int, owner_id: int) -> void:
	_x.append(pos.x)
	_z.append(pos.z)
	_t.append(t)
	_species.append(species_index)
	_owner.append(owner_id)


## Tira o que passou da idade e o que passa do limite de memória.
func prune(now: float) -> void:
	var max_start := maxi(_start, _x.size() - GameConfig.SCENT_MAX_PRINTS)
	while _start < _x.size() and (_start < max_start or now - _t[_start] > GameConfig.SCENT_MAX_AGE_S):
		_start += 1
	# Compacta de vez em quando, pra não guardar o que já saiu.
	if _start > 1024 and _start * 2 > _x.size():
		_x = _x.slice(_start)
		_z = _z.slice(_start)
		_t = _t.slice(_start)
		_species = _species.slice(_start)
		_owner = _owner.slice(_start)
		_start = 0


## Pegadas num raio, até `max_age` segundos, sem as do dino `exclude_id`.
## Devolve STRIDE floats por pegada (x, z, idade, espécie, KIND_PRINT), da mais velha pra mais nova.
func query(center: Vector3, radius: float, now: float, max_age: float, exclude_id: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var r2 := radius * radius
	for i in range(_start, _x.size()):
		var age := now - _t[i]
		if age > max_age or _owner[i] == exclude_id:
			continue
		var dx := _x[i] - center.x
		var dz := _z[i] - center.z
		if dx * dx + dz * dz > r2:
			continue
		out.append_array(PackedFloat32Array([_x[i], _z[i], age, _species[i], KIND_PRINT]))
	return out
