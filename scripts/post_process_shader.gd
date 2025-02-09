# All done with the help of Digvijaysinh Gohil on Youtube
# i have no idea how to really understand most of the boilerplate here
# - mari

@tool
class_name PostProcess extends CompositorEffect
# low-level device
var rd : RenderingDevice
# unique shader ID
var shader : RID
# pipeline
var pipeline : RID

const LOCAL_SIZE_X : float = 8
const LOCAL_SIZE_Y : float = 8
const LOCAL_SIZE_Z : float = 1

# entry point
func _init() -> void:
	RenderingServer.call_on_render_thread(initialize_compute_shader)

# called on render thread every frame
func _render_callback(effect_callback_type: int, render_data: RenderData) -> void:
	if not rd: return # null check
	var scene_buffers : RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	if not scene_buffers: return # null check
	# init workgroups
	var size : Vector2i = scene_buffers.get_internal_size()
	if size.x == 0 or size.y == 0: return # null check
	# TODO: check if this is right (it works)
	var x_groups : int = size.x / LOCAL_SIZE_X + 1.0
	var y_groups : int = size.y / LOCAL_SIZE_Y + 1.0
	var push_constants : PackedFloat32Array = PackedFloat32Array()
	push_constants.append(size.x)
	push_constants.append(size.y)
	push_constants.append(0.0)
	push_constants.append(0.0)
	
	for view in scene_buffers.get_view_count():
		# just in case VR is used
		var screen_texture : RID = scene_buffers.get_color_layer(view)
		# get screen tex and pass as UNIFORM of type IMAGE
		var uniform : RDUniform = RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = 0
		uniform.add_id(screen_texture)
		
		var image_uniform_set : RID = UniformSetCacheRD.get_cache(shader, 0, [uniform])
		
		# create compute list
		var compute_list : int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, image_uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, push_constants.to_byte_array(), push_constants.size() * 4)
		# submit compute list
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()
	
# prevent mem leaks
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and shader.is_valid():
		# obj is about to be deleted
		# free up to avoid mem leaks
		RenderingServer.free_rid(shader)
		# pipeline will be released if shader is released

# compute shader
func initialize_compute_shader() -> void:
	# init rendering device ref
	rd = RenderingServer.get_rendering_device()
	if not rd: return # return if null
	# initialize glsl file path
	var glsl_file : RDShaderFile = load("res://shaders/compute_test.glsl")
	shader = rd.shader_create_from_spirv(glsl_file.get_spirv())
	# init pipeline ref
	pipeline = rd.compute_pipeline_create(shader)
