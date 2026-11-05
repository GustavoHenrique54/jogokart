class_name FireOrb
extends Node3D
## Projétil da habilidade de dano do Boitatá: "Labareda Voraz".

const SPEED := 42.0
const LIFETIME := 3.0
const EXPLOSION_RADIUS := 3.2

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
		_explode()
		return

	var step := direction * SPEED * delta
	var target_pos := global_position + step

	# Raycast para detecção de colisão precisa
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
			# Ignora quem atirou
			global_position = target_pos
			return

		_explode()
		if target_kart:
			target_kart.apply_damage_effect("fire", global_position, 14.0)
		return

	# Checa proximidade com outros karts
	for k in get_tree().get_nodes_in_group("karts"):
		var kart := k as Kart
		if not kart or kart.peer_id == shooter_id:
			continue
		var dist := global_position.distance_to(kart.ball.global_position)
		if dist < 2.0:
			_explode()
			kart.apply_damage_effect("fire", global_position, 14.0)
			return

	global_position = target_pos


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	mesh.visible = false
	trail_particles.emitting = false
	explosion_particles.emitting = true
	light.light_energy = 3.5
	light.omni_range = 8.0

	# Aplica dano em área nos karts próximos
	for k in get_tree().get_nodes_in_group("karts"):
		var kart := k as Kart
		if not kart or kart.peer_id == shooter_id:
			continue
		var dist := global_position.distance_to(kart.ball.global_position)
		if dist <= EXPLOSION_RADIUS:
			var force := lerpf(16.0, 5.0, dist / EXPLOSION_RADIUS)
			kart.apply_damage_effect("fire", global_position, force)

	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.45)
	await get_tree().create_timer(0.6).timeout
	queue_free()

