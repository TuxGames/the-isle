class_name Combat
extends RefCounted
## Hitbox: o golpe só causa dano se a área do ataque realmente encostar no corpo do alvo.
## Corpo = esferas da tabela de espécies. Ataque = segmento vertical (a boca pode baixar).


## Esferas do corpo em coordenadas do mundo: [[centro, raio, parte], ...]
static func body_spheres(d: Dino) -> Array:
	var s := d.scale()
	var basis := Basis(Vector3.UP, d.yaw)
	var out := []
	for part in d.spec()["body"]:
		var local: Vector3 = part[0]
		var r: float = part[1]
		out.append([d.pos + basis * (local * s), r * s, part[2]])
	return out


## Segmento do golpe: [topo, base, raio].
static func attack_segment(d: Dino) -> Array:
	var sp := d.spec()
	var s := d.scale()
	var local: Vector3 = sp["attack_point"]
	var reach_down: float = sp["attack_reach_down"]
	var radius: float = sp["attack_radius"]
	var top := d.pos + Basis(Vector3.UP, d.yaw) * (local * s)
	var bottom := top - Vector3(0.0, local.y * s * reach_down, 0.0)
	return [top, bottom, radius * s]


static func _point_segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Se o golpe do atacante acerta o alvo agora, devolve a parte atingida; senão "".
## Quando acerta mais de uma esfera, vale a mais "funda" (mais dentro do golpe).
static func hit_part(attacker: Dino, target: Dino) -> String:
	if attacker == target or not target.alive:
		return ""
	var seg := attack_segment(attacker)
	var top: Vector3 = seg[0]
	var bottom: Vector3 = seg[1]
	var radius: float = seg[2]
	var best_part := ""
	var best_pen := 0.0
	for sphere in body_spheres(target):
		var c: Vector3 = sphere[0]
		var r: float = sphere[1]
		var pen := radius + r - _point_segment_distance(c, top, bottom)
		if pen > best_pen:
			best_pen = pen
			best_part = sphere[2]
	return best_part


## Escolhe o alvo atingido entre os candidatos (o mais perto da ponta do golpe).
## Devolve {"target": Dino, "part": String} ou {} se errou.
static func resolve_attack(attacker: Dino, candidates: Array) -> Dictionary:
	var seg := attack_segment(attacker)
	var top: Vector3 = seg[0]
	var best := {}
	var best_d := INF
	for c in candidates:
		var t: Dino = c
		var part := hit_part(attacker, t)
		if part == "":
			continue
		var d := top.distance_to(t.pos)
		if d < best_d:
			best_d = d
			best = {"target": t, "part": part}
	return best


static func damage(attacker: Dino, part: String) -> float:
	var base: float = attacker.spec()["damage"]
	var mult: float = Species.PART_DAMAGE.get(part, 1.0)
	return base * attacker.size_factor() * mult


## Usado pela IA: o alvo está a uma distância em que vale tentar o golpe?
static func in_reach(attacker: Dino, target: Dino) -> bool:
	return hit_part(attacker, target) != ""
