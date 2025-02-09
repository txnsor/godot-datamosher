using Godot;
using System;

public partial class Player : CharacterBody3D {
	// EXPORT VARS

	// player max speed (m/s)
	[Export]
	public int MaxSpeed { get; set; } = 100;
	// player jump speed (m/s)
	[Export]
	public int JumpSpeed { get; set; } = 75;
	// player downward acceleration (m/s^2)
	[Export]
	public int VerticalAcceleration { get; set; } = 200;
	// player speed up acceleration (m/s^2)
	[Export]
	public float HorizontalAcceleration { get; set; } = 5.0f;
	// player slow down acceleration (m/s^2)
	[Export]
	public float HorizontalDeceleration { get; set; } = 12.0f;
	[Export]
	public float SensitivityMouse = 0.002f;
	
	private Vector3 _targetVelocity = Vector3.Zero;

	private Camera3D camera;

	public override void _Ready() {
		Input.MouseMode = Input.MouseModeEnum.Captured;
		camera = GetNode<Camera3D>("camera");
	}

	public override void _UnhandledInput(InputEvent @event) {
		// handle mouse rotation
		if (@event is InputEventMouseMotion mouseMotion) {
			RotateY(-mouseMotion.Relative.X * SensitivityMouse);
			camera.RotateX(-mouseMotion.Relative.Y * SensitivityMouse);
		}
		// quit on ESC
		if (Input.IsActionJustPressed("quit")) {
			GetTree().Quit();
		}
	}
    public override void _PhysicsProcess(double delta) {
		Godot.Vector3 velocity = Velocity;
		// jump and apply gravity
		if (!IsOnFloor()) {velocity.Y -= VerticalAcceleration*(float)delta;}
		if (Input.IsActionJustPressed("jump") && IsOnFloor()) {
			velocity.Y = JumpSpeed;
		}
		// get the input direction and handle movement
		Godot.Vector2 inputDirection = Input.GetVector("move_left", "move_right", "move_forward", "move_back");
		// get the transform basis (for prev rotation) and update based on [normalized] input
		Godot.Vector3 direction = (Transform.Basis * new Godot.Vector3(inputDirection.X, 0, inputDirection.Y)).Normalized();
		// move in direction
		if (direction != Godot.Vector3.Zero) {
			velocity.X = Mathf.Lerp(Velocity.X, direction.X * MaxSpeed, (float)HorizontalAcceleration*(float)delta);
			velocity.Z = Mathf.Lerp(Velocity.Z, direction.Z * MaxSpeed, (float)HorizontalAcceleration*(float)delta);
		} else {
			// ...or begin to slow down
			velocity.X = Mathf.Lerp(Velocity.X, 0.0f, (float)HorizontalDeceleration*(float)delta);
			velocity.Z = Mathf.Lerp(Velocity.Z, 0.0f, (float)HorizontalDeceleration*(float)delta);
		}
		Velocity = velocity;
		MoveAndSlide();
    }

}
