extends BaseTower

@export var damage: int = 40
@export var range: float = 48.0
@export var fire_rate: float = 1  # shots per second
@export var rotation_speed: float = 11.0  # Slower rotation due to heavy barrel
@export var angle_threshold: float = 0.2  # Base angle threshold for firing

var time_since_last_shot: float = 0.0
var current_target: BaseBug = null
var projectile_scene = preload("res://scenes/projectiles/heavy_projectile.tscn")

@onready var barrel = $Barrel
@onready var detection_area = $DetectionArea
@onready var power_manager = get_parent().get_node("PowerManager")

# Store the default rotation
var default_rotation: float = 0.0

func _ready():
	cost = 300
	power_usage = .5  # per shot
	durability = 150
	
	# Setup detection area
	var area = Area2D.new()
	area.name = "DetectionArea"
	var collision_shape = CollisionShape2D.new()
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = range * 16  # Convert to pixels
	collision_shape.shape = circle_shape
	area.add_child(collision_shape)
	add_child(area)
	
	# Connect detection area signals
	area.body_entered.connect(_on_detection_area_body_entered)
	area.body_exited.connect(_on_detection_area_body_exited)
	
	# Set collision masks
	area.collision_layer = 0
	area.collision_mask = 2  # Layer for bugs
	
	# Store default rotation
	default_rotation = barrel.rotation

func _process(delta):
	# Skip all processing if tower is being placed
	if modulate.a < 1.0:
		return
	time_since_last_shot += delta
	
	# Update target if it's no longer valid
	if current_target and (not is_instance_valid(current_target) or current_target.current_health <= 0):
		current_target = null
	
	# If we don't have a target, try to find one
	if not current_target:
		current_target = find_new_target()
	
	# Handle turret rotation
	if current_target and is_instance_valid(current_target):
		# Calculate desired rotation to face target
		var target_pos = current_target.global_position
		var direction = global_position.direction_to(target_pos)
		var distance = global_position.distance_to(target_pos)
		var desired_angle = direction.angle()
		
		# Smoothly rotate barrel
		barrel.rotation = lerp_angle(barrel.rotation, desired_angle, rotation_speed * delta)
		
		# Calculate angle difference accounting for wrap-around
		var angle_diff = abs(barrel.rotation - desired_angle)
		if angle_diff > PI:
			angle_diff = TAU - angle_diff
		
		# Calculate dynamic angle threshold based on distance
		var dynamic_threshold = angle_threshold
		if distance < 32:  # If closer than 32 pixels
			dynamic_threshold = 0.5  # Much more lenient when very close
		
		# Try to fire if conditions are met
		if time_since_last_shot >= 1.0 / fire_rate:
			# Always fire if target is very close, regardless of angle
			if distance < 16:
				attempt_fire()
			# Otherwise check angle threshold
			elif angle_diff < dynamic_threshold:
				attempt_fire()
	else:
		# Return to default rotation when no target
		barrel.rotation = lerp_angle(barrel.rotation, default_rotation, rotation_speed * delta)

func attempt_fire() -> void:
	if not power_manager:
		return
		
	# Check if we have enough power to fire
	if not power_manager.use_power(power_usage):
		return  # Not enough power to fire
		
	if current_target and is_instance_valid(current_target):
		# Create projectile
		var projectile = projectile_scene.instantiate()
		get_tree().root.add_child(projectile)
		
		# Calculate spawn position slightly in front of the barrel
		var spawn_offset = Vector2.RIGHT.rotated(barrel.rotation) * 8
		projectile.global_position = barrel.global_position + spawn_offset
		
		projectile.setup(damage, current_target)
		
		time_since_last_shot = 0.0

func _on_detection_area_body_entered(body: Node2D) -> void:
	if body is BaseBug:
		if body.special_ability == "Armored":
			# Always switch to armored targets
			current_target = body
		elif not current_target:
			current_target = body
		elif not current_target.special_ability == "Armored":
			# Switch to closer target only if current target isn't armored
			var current_distance = global_position.distance_to(current_target.global_position)
			var new_distance = global_position.distance_to(body.global_position)
			if new_distance < current_distance:
				current_target = body

func _on_detection_area_body_exited(body: Node2D) -> void:
	if body == current_target:
		current_target = find_new_target()

func find_new_target() -> BaseBug:
	var potential_targets = detection_area.get_overlapping_bodies()
	var closest_target: BaseBug = null
	var closest_distance = INF
	
	# First try to find an armored target
	for body in potential_targets:
		if body is BaseBug and is_instance_valid(body) and body.current_health > 0:
			if body.special_ability == "Armored":
				var distance = global_position.distance_to(body.global_position)
				if distance < closest_distance:
					closest_distance = distance
					closest_target = body
	
	# If no armored target found, find the closest target
	if not closest_target:
		closest_distance = INF
		for body in potential_targets:
			if body is BaseBug and is_instance_valid(body) and body.current_health > 0:
				var distance = global_position.distance_to(body.global_position)
				if distance < closest_distance:
					closest_distance = distance
					closest_target = body
	
	return closest_target

func get_attack_range() -> float:
	return range

func get_damage() -> int:
	return damage
