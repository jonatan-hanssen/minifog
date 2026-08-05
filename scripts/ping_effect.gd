extends Node2D

@export var start_radius: float = 10.0
@export var end_radius: float = 80.0
@export var duration: float = 2.0
@export var color: Color = Color.RED

var radius: float
var alpha: float = 1.0


func _ready() -> void:
	radius = start_radius

	var tween := create_tween()
	tween.set_parallel(true)

	# Expand the circle
	tween.tween_property(self, "radius", end_radius, duration)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)

	# Fade out as it expands
	tween.tween_property(self, "alpha", 0.0, duration)

	tween.finished.connect(queue_free)

	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var draw_color := color
	draw_color.a *= alpha
	
	draw_arc(
		Vector2.ZERO,
		radius,
		0,
		TAU,
		64,
		draw_color,
		3.0
	)
