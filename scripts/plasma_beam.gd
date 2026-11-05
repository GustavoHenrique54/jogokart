class_name PlasmaBeam
extends Node3D
## Projétil da habilidade de dano do ET de Varginha: "Feixe Telecinético (Pulso Ufológico)".
## Onda psíquica concentrada disparada em linha reta (skillshot) a partir dos calombos na cabeça.
## Ao acertar o kart adversário: causa curto-circuito que trava as rodas de ferro, faz o kart quicar,
## perde 40% da velocidade de descida e o empurra levemente para o lado.
## Se errar, bate na vegetação/cerca sem causar efeito na pista.

const SPEED := 52.0
const LIFETIME := 2.5

var direction := Vector3.FORWARD
var shooter_id: int = 0

var _alive_timer := 0.0
var _exploded := false

@onready var mesh: MeshInstance3D = $Mesh
@onready var light: OmniLight3D = $Light
@onready var trail_particles: CPUParticles3D = $TrailParticles
@onready var explosion_particles: CPUParticles3D = $ExplosionParticles


func _ready() -> void:
	top_level = true


func setup(from_pos: Vector3, shoot_dir: Vector3, shooter_peer_id: int) -> void:
	global_position = from_pos
	direction = shoot_dir.normalized()
	shooter_id = shooter_peer_id
	look_at(global_position + direction, Vector3.UP)


func _physics_process(delta: float) -> void:
	if _exploded:
		return

	_alive_timer += delta
	if _alive_timer >= LIFETIME:
		_explode(false)
		return

	var step := direction * SPEED * delta
	var target_pos := global_position + step

	# Raycast para detecção precisa de impacto em linha reta
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, target_pos, 7)
	var hit := space.intersect_ray(query)

	if not hit.is_empty():
		global_position = hit.position
		var hit_collider: Object = hit.collider
		var target_kart: Kart = null
		if hit_collider.has_meta("kart"):
			target_kart = hit_collider.get_meta("kart")
		elif hit_collider is Kart:
			target_kart = hit_collider

		if target_kart and target_kart.peer_id == shooter_id:
			global_position = target_pos
			return

		if target_kart:
			# Acerto direto no kart oponente
			_explode(true)
			target_kart.apply_telekinetic_hit(global_position, direction)
		else:
			# Bateu em cerca, árvore, rocha ou asfalto: dissipa sem afetar a pista
			_explode(false)
		return

	# Checa proximidade com outros karts
	for k in get_tree().get_nodes_in_group("karts"):
		var kart := k as Kart
		if not kart or kart.peer_id == shooter_id:
			continue
		var dist := global_position.distance_to(kart.ball.global_position)
		if dist < 1.75:
			_explode(true)
			kart.apply_telekinetic_hit(global_position, direction)
			return

	global_position = target_pos


func _explode(hit_kart: bool) -> void:
	if _exploded:
		return
	_exploded = true
	mesh.visible = false
	trail_particles.emitting = false
	explosion_particles.emitting = true
	light.light_energy = 5.0 if hit_kart else 2.5
	light.omni_range = 9.0 if hit_kart else 4.5

	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.35)
	await get_tree().create_timer(0.45).timeout
	queue_free()
