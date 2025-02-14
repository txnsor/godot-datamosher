extends Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Global.MOSH_FLAG = 0.0

# returns a value according to the slope function for vals (0 - 1)
func mosh_slope(x: float) -> float:
	if (x < 0.25): return 0.0
	elif (x < 0.75): return 2.0*x - 0.5
	else: return 1.0

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Input.is_action_pressed("click"):
		Global.MOSH_FLAG = 0.997
	else:
		Global.MOSH_FLAG = 0
