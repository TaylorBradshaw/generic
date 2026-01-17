extends CharacterBody3D

func sphere(color: Color) -> MeshInstance3D:
    var sphere = MeshInstance3D.new()
    var mesh = SphereMesh.new()
    mesh.height = 0.01
    mesh.radius = mesh.height / 2.0
    var material = StandardMaterial3D.new()
    material.albedo_color = color
    mesh.material = material
    sphere.mesh = mesh
    sphere.position.z = -1
    return sphere

var debug_head = Node3D.new()
var debug_camera_rotation = Node3D.new()
var debug_recoil_rotation = Node3D.new()
var debug_target_rotation = Node3D.new()

func _ready() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    # Debug
    self.add_child(debug_head)
    debug_head.position = camera.position
    debug_head.add_child(debug_camera_rotation)
    debug_camera_rotation.add_child(sphere(Color.GREEN))
    debug_head.add_child(debug_recoil_rotation)
    debug_recoil_rotation.add_child(sphere(Color.RED))
    debug_head.add_child(debug_target_rotation)
    debug_target_rotation.add_child(sphere(Color.YELLOW))


### Constants
var DEGREE_TO_RADIAN = (PI / 180.0)
var RADIAN_TO_DEGREE = (180.0 / PI)


### Camera ###
func move_towards_zero(initial: Vector3, difference: Vector3) -> Vector3:
    difference = difference.clamp(-initial.abs(), initial.abs())
    difference *= ((difference.sign() * initial.sign()).clampf(-1.0, 0.0) * -1)
    return difference

@onready var camera : Camera3D = $Camera3D
var look_rotation = Vector3.ZERO

var target_recoil_rotation = Vector3.ZERO
var recoil_rotation = Vector3.ZERO
var camera_recoil_rotation = Vector3.ZERO
var look_input = Vector3.ZERO

func _input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        var raw_input = -event.screen_relative / Vector2(get_window().size) * 3
        look_input = Vector3(raw_input.y, raw_input.x, 0.0)
        
        var recoil_correction = move_towards_zero(recoil_rotation, look_input)
        recoil_rotation += recoil_correction
        
        var look_step = look_input - recoil_correction
        look_rotation += look_step
        look_rotation.x = clampf(look_rotation.x, deg_to_rad(-90.0), deg_to_rad(90.0)) # Good!
        
        target_recoil_rotation += move_towards_zero(target_recoil_rotation, look_input)


### Movement ###
const SPEED = 5.0
const JUMP_VELOCITY = 4.5

func _physics_process(delta: float) -> void:
    # Add the gravity.
    if not is_on_floor():
        velocity += get_gravity() * delta

    # Handle jump.
    if Input.is_action_just_pressed("jump") and is_on_floor():
        velocity.y = JUMP_VELOCITY

    # Get the input direction and handle the movement/deceleration.
    # As good practice, you should replace UI actions with custom gameplay actions.
    var input_dir := Input.get_vector("left", "right", "up", "down")
    var direction := (camera.global_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
    if direction:
        velocity.x = direction.x * SPEED
        velocity.z = direction.z * SPEED
    else:
        velocity.x = move_toward(velocity.x, 0, SPEED)
        velocity.z = move_toward(velocity.z, 0, SPEED)

    move_and_slide()

### Main Loop ###
func _process(delta: float) -> void:
    if Input.is_action_pressed("fire"):
        fire()
    
    process_recoil(delta) 
    process_weapon_sway(delta)
    process_weapon_aim(delta)
    
    var updated_rotation = look_rotation + recoil_rotation
    updated_rotation.y = fmod(updated_rotation.y, 2 * PI)
    camera.basis = Basis.from_euler(updated_rotation)
    
    # Debug
    debug_camera_rotation.basis = Basis.from_euler(look_rotation)
    debug_recoil_rotation.basis = Basis.from_euler(look_rotation + recoil_rotation)
    debug_target_rotation.basis = Basis.from_euler(look_rotation + target_recoil_rotation)


### Recoil ###
func process_recoil(delta: float) -> void:
    if target_recoil_rotation == Vector3.ZERO and recoil_rotation == Vector3.ZERO:
        return
    # Move target recoil towards zero
    var recoil_return_speed = target_recoil_rotation * delta #TODO: this value affects the recoil magnitude limit, very strange
    target_recoil_rotation -= target_recoil_rotation * recoil_return_speed
    # Move recoil rotation towards target recoil
    var snappiness = delta * 24
    recoil_rotation = lerp(recoil_rotation, target_recoil_rotation, snappiness)

var can_fire : bool = true
func fire():
    if not can_fire:
        return
    can_fire = false
    # TODO: spawn bullet
    recoil()
    await get_tree().create_timer(0.1).timeout
    can_fire = true

func recoil():
    # Define direction based on unit circle
    var direction = deg_to_rad(90)
    var direction_stddev = deg_to_rad(12) # 10%
    direction = randfn(direction, direction_stddev)
    var magnitude = 1.0 / 10.0
    var magnitude_stddev = magnitude / 10.0 # 10%
    magnitude = randfn(magnitude, magnitude_stddev)
    # Determine recoil amount per-axis
    var recoil_x = -cos(direction) * magnitude # negative since -Z is forward in Godot
    var recoil_y = sin(direction) * magnitude
    var recoil_z = 0.0 # ignoring for now
    # Note: Basis uses order YXZ
    target_recoil_rotation += Vector3(recoil_y, recoil_x, recoil_z)


### Weapon ###
@onready var weapon_holder: Node3D = $Camera3D/weapon_holder
@onready var weapon: Node3D = $Camera3D/weapon

func process_weapon_sway(delta: float) -> void:
    var max_weapon_sway = weapon.rotation.abs() + Vector3(2.5, 2.5, 1.5) * DEGREE_TO_RADIAN
    var weapon_sway = weapon.rotation.lerp(look_input, delta * 5)
    weapon.rotation = weapon_sway.clamp(-max_weapon_sway, max_weapon_sway)

@onready var ads: Camera3D = $Camera3D/weapon/ads_camera
func process_weapon_aim(delta: float) -> void:
    var aim_speed = delta * 15
    var aim_fov = 25.0
    if Input.is_action_pressed("aim"):
        weapon.position = weapon.position.lerp(-ads.position, aim_speed)
        camera.fov = lerp(camera.fov, ads.fov, aim_speed)
    else:
        weapon.global_position = weapon.global_position.lerp(weapon_holder.global_position, aim_speed)
        camera.fov = lerp(camera.fov, 75.0, aim_speed)
