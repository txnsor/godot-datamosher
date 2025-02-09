# All done with the help of (...):
#		Digvijaysinh Gohil, Sphynx, Godot Documentation & Discord
# general purpose fragment shader boilerplate
# - mari

############################################################################

@tool
class_name MotionVectorEffect extends CompositorEffect

# boiler plate variables

var rd : RenderingDevice
var sampler : RID
var shader : RID
var pipeline : RID

# user defined constants 

@export var shaderpath : String = "res://shaders/compute_test.glsl"
@export var WORKGROUP_X : int = 8
@export var WORKGROUP_Y : int = 8

############################################################################

# entry point
func _init() -> void:
	# enables motion vector usage
	needs_motion_vectors = true
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	# call compute on render thread
	RenderingServer.call_on_render_thread(init_compute)

# prevent mem leaks
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and shader.is_valid():
		# obj is about to be deleted
		# free up to avoid mem leaks
		RenderingServer.free_rid(shader)
		# pipeline will be released if shader is released
		

############################################################################

# initialize the compute shader
func init_compute():
	# init rendering device ref
	rd = RenderingServer.get_rendering_device()
	# set up sampler
	var sampler_state : RDSamplerState = RDSamplerState.new()
	sampler_state.min_filter  = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler = rd.sampler_create(sampler_state)
	if not rd: 
		push_error("LOAD_ERROR: RenderingDevice failed to initialize")
		return # return if null
	# initialize glsl file path
	var glsl_file : RDShaderFile = load(shaderpath)
	# null check
	if not glsl_file:
		push_error("LOAD_ERROR: Shader file does not exist")
		return
	# process file into spirv
	shader = rd.shader_create_from_spirv(glsl_file.get_spirv())
	if not shader:
		push_error("LOAD_ERROR: Shader failed to compile to spirv")
		return
	# init pipeline ref
	pipeline = rd.compute_pipeline_create(shader)
	if not shader:
		push_error("LOAD_ERROR: Pipeline failed to initialize")
		return

# helper function
func get_uniform(params : RID, binding : int = 0, uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE, isSampler = false) -> RDUniform:
	var uniform : RDUniform = RDUniform.new()
	uniform.uniform_type = uniform_type
	uniform.binding = binding
	if sampler: uniform.add_id(sampler)
	uniform.add_id(params)
	if not uniform:
		push_error("UNIFORM_ERROR: Uniform of binding " + str(binding) + "failed to initialize")
	return uniform


# called on render thread every frame
func _render_callback(effect_callback_type: int, render_data: RenderData) -> void:
	if Engine.is_editor_hint(): return
	if not rd: 
		push_error("RENDER_CALLBACK_ERROR: RenderingDevice uninitialized, failed to render")
		return # null check
	if not effect_callback_type == CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		push_error("RENDER_CALLBACK_ERROR: Render thread tried to load shader type other than POST_TRANSPARENT")
		return

	# init scene buffer
	var scene_buffers : RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	if not scene_buffers: 
		push_error("RENDER_CALLBACK_ERROR: Scene buffers failed to initialize")
		return # null check
	# init scene data
	var scene_data : RenderSceneDataRD = render_data.get_render_scene_data()
	if not scene_data: 
		push_error("RENDER_CALLBACK_ERROR: Scene data failed to initialize")
		return # null check
	
	# init workgroups
	var size = scene_buffers.get_internal_size()
	if size.x == 0 or size.y == 0: 
		push_error("RENDER_CALLBACK_ERROR: Scene buffers have size 0")
		return # null check
	
	# NOTE: this will change depending on # of workgrounds (specifically, the magic number '8'
	
	# set up compute shader
	var x_groups : int = (size.x - 1) / WORKGROUP_X + 1
	var y_groups : int = (size.y - 1) / WORKGROUP_Y + 1
	var z_groups : int = 1
	
	var push_constants : PackedFloat32Array = PackedFloat32Array()

	
	# for each view
	for view in scene_buffers.get_view_count():
		# get textures (screen, motion, depth)
		var screen_texture : RID = scene_buffers.get_color_layer(view)
		var motion_texture : RID = scene_buffers.get_velocity_layer(view)
		var depth_texture : RID = scene_buffers.get_depth_layer(view)
		
		if not screen_texture.is_valid():
			push_error("VIEW_PASS_ERROR: Screen Texture failed to load")
			return
		if not motion_texture.is_valid():
			push_error("VIEW_PASS_ERROR: Motion Texture failed to load")
			return
		if not depth_texture.is_valid():
			push_error("VIEW_PASS_ERROR: Depth Texture failed to load")
			return
			
		
		
		# turn them into image uniforms (implicit error checking in helper functions)
		var uniform_screen : RDUniform = get_uniform(screen_texture)
		var uniform_motion : RDUniform = get_uniform(motion_texture)
		# depth is different for some reason (TEXTURE_USAGE_BIT)
		var uniform_depth : RDUniform = get_uniform(depth_texture, 1, RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, true)
		
		# into sets to send to the compute list
		var color_uniform_set : RID = UniformSetCacheRD.get_cache(shader, 0, [uniform_screen])
		var motion_uniform_set : RID = UniformSetCacheRD.get_cache(shader, 1, [uniform_motion])
		# TODO: fix-- depth is not passed as uniform texture, needs storage bit changed
		var depth_uniform_set : RID = UniformSetCacheRD.get_cache(shader, 2, [uniform_depth])
		
		if not color_uniform_set.is_valid() or not motion_uniform_set.is_valid() or not depth_uniform_set.is_valid():
			push_error("UNIFORM_SET_ERROR: One or more uniform sets is invalid")
		
		# get inv_view_matrix, proj_matrix
		var inv_view_matrix = scene_data.get_cam_transform()
		var proj_matrix = scene_data.get_cam_projection()
		
		# set up push constants
		
		# TODO: fix-- push_constants is not the correct size, one of the following is failing out for some reason (?)
		
		# inv view
		push_constants.push_back(inv_view_matrix.basis.x.x)
		push_constants.push_back(inv_view_matrix.basis.x.y)
		push_constants.push_back(inv_view_matrix.basis.x.z)
		push_constants.push_back(0.0)
		push_constants.push_back(inv_view_matrix.basis.y.x)
		push_constants.push_back(inv_view_matrix.basis.y.y)
		push_constants.push_back(inv_view_matrix.basis.y.z)
		push_constants.push_back(0.0)
		push_constants.push_back(inv_view_matrix.basis.z.x)
		push_constants.push_back(inv_view_matrix.basis.z.y)
		push_constants.push_back(inv_view_matrix.basis.z.z)
		push_constants.push_back(0.0)
		push_constants.push_back(inv_view_matrix.origin.x)
		push_constants.push_back(inv_view_matrix.origin.y)
		push_constants.push_back(inv_view_matrix.origin.z)
		push_constants.push_back(1.0)
		# projection matrix
		push_constants.push_back(proj_matrix.x.x)
		push_constants.push_back(proj_matrix.x.y)
		push_constants.push_back(proj_matrix.x.z)
		push_constants.push_back(proj_matrix.x.w)
		push_constants.push_back(proj_matrix.y.x)
		push_constants.push_back(proj_matrix.y.y)
		push_constants.push_back(proj_matrix.y.z)
		push_constants.push_back(proj_matrix.y.w)
		push_constants.push_back(proj_matrix.z.x)
		push_constants.push_back(proj_matrix.z.y)
		push_constants.push_back(proj_matrix.z.z)
		push_constants.push_back(proj_matrix.z.w)
		push_constants.push_back(proj_matrix.w.x)
		push_constants.push_back(proj_matrix.w.y)
		push_constants.push_back(proj_matrix.w.z)
		push_constants.push_back(proj_matrix.w.w)
		# x, y
		push_constants.append(size.x)
		push_constants.append(size.y)
		# time (TODO)
		push_constants.append(0.0)
		
		
		# create compute list
		var compute_list : int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, color_uniform_set, 0)
		rd.compute_list_bind_uniform_set(compute_list, motion_uniform_set, 1)
		rd.compute_list_bind_uniform_set(compute_list, depth_uniform_set, 2)
		rd.compute_list_set_push_constant(compute_list, push_constants.to_byte_array(), 144)
		# submit compute list
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
		rd.compute_list_end()
