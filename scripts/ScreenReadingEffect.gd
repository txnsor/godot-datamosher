# screen reading shader setup

@tool
extends CompositorEffect
class_name ScreenReadingEffect

@export var script_path: String = "res://shaders/datamosher.glsl"
@export var buffer_path: String = "res://shaders/buffer_frame.glsl"
@export var WORKGROUP_X : int = 8
@export var WORKGROUP_Y : int = 8

var rd: RenderingDevice
var shader: RID
var sampler: RID
var pipeline: RID
var parameters: RID 

var buffer_shader: RID
var buffer_pipeline: RID

var context : StringName = "previous_frame"
var texture : StringName = "texture"

func _init() -> void:
	rd = RenderingServer.get_rendering_device()
	RenderingServer.call_on_render_thread(_initialize_compute)

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if shader.is_valid():
			rd.free_rid(shader)
		if buffer_shader.is_valid():
			rd.free_rid(buffer_shader)
		if parameters.is_valid():
			rd.free_rid(parameters)

func _initialize_compute() -> void:
	rd = RenderingServer.get_rendering_device()
	if not rd:
		return
		
	var sampler_state: RDSamplerState = RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler = rd.sampler_create(sampler_state)

	var shader_file := load(script_path)
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()

	shader = rd.shader_create_from_spirv(shader_spirv)
	if shader.is_valid():
		pipeline = rd.compute_pipeline_create(shader)
		
	shader_file = load(buffer_path)
	shader_spirv = shader_file.get_spirv()
	buffer_shader = rd.shader_create_from_spirv(shader_spirv)
	if buffer_shader.is_valid():
		buffer_pipeline = rd.compute_pipeline_create(buffer_shader)

# helper
func get_uniform_img(image: RID, binding: int = 0) -> RDUniform:
	var unif : RDUniform = RDUniform.new();
	unif.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	unif.binding = binding
	unif.add_id(image)
	
	return unif

func _render_callback(p_effect_callback_type: EffectCallbackType, p_render_data: RenderData) -> void:
	if (not rd) or (Engine.is_editor_hint()):
		return

	var render_scene_buffers := p_render_data.get_render_scene_buffers()
	var render_scene_data = p_render_data.get_render_scene_data()
	
	if  not render_scene_buffers or not render_scene_data:
		return;
		
	var size: Vector2i = render_scene_buffers.get_internal_size()
	if size.x == 0 and size.y == 0:
		return

	@warning_ignore("integer_division")
	var x_groups := (size.x - 1) / WORKGROUP_X + 1
	@warning_ignore("integer_division")
	var y_groups := (size.y - 1) / WORKGROUP_Y + 1
	var z_groups := 1
	
	# check for previous frame
	if render_scene_buffers.has_texture(context, texture):
		var tex_format : RDTextureFormat = render_scene_buffers.get_texture_format(context, texture)
		if tex_format.width != size.x or tex_format.height != size.y:
			# clears all texture under this context
			render_scene_buffers.clear_context(context)
	else:
		var usage_bits : int = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		render_scene_buffers.create_texture(context, texture, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, usage_bits, RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, true)
		Global.refresh_frame = true

	var view_count: int = render_scene_buffers.get_view_count()
	for view in view_count:
		var color_image = render_scene_buffers.get_color_layer(view)
		var depth_image = render_scene_buffers.get_depth_layer(view)
		var motion_image = render_scene_buffers.get_velocity_layer(view)
		var previous_image = render_scene_buffers.get_texture(context, texture)
		
		var inv_view_matrix = render_scene_data.get_cam_transform()
		var projection_matrix = render_scene_data.get_cam_projection()
		var render_size = render_scene_buffers.get_internal_size()
		
		# init params
		var params = PackedFloat32Array()
		# push the camera transformation matrix and projection matrix
		params.push_back(inv_view_matrix.basis.x.x)
		params.push_back(inv_view_matrix.basis.x.y)
		params.push_back(inv_view_matrix.basis.x.z)
		params.push_back(0.0)
		params.push_back(inv_view_matrix.basis.y.x)
		params.push_back(inv_view_matrix.basis.y.y)
		params.push_back(inv_view_matrix.basis.y.z)
		params.push_back(0.0)
		params.push_back(inv_view_matrix.basis.z.x)
		params.push_back(inv_view_matrix.basis.z.y)
		params.push_back(inv_view_matrix.basis.z.z)
		params.push_back(0.0)
		params.push_back(inv_view_matrix.origin.x)
		params.push_back(inv_view_matrix.origin.y)
		params.push_back(inv_view_matrix.origin.z)
		params.push_back(1.0)
		params.push_back(projection_matrix.x.x)
		params.push_back(projection_matrix.x.y)
		params.push_back(projection_matrix.x.z)
		params.push_back(projection_matrix.x.w)
		params.push_back(projection_matrix.y.x)
		params.push_back(projection_matrix.y.y)
		params.push_back(projection_matrix.y.z)
		params.push_back(projection_matrix.y.w)
		params.push_back(projection_matrix.z.x)
		params.push_back(projection_matrix.z.y)
		params.push_back(projection_matrix.z.z)
		params.push_back(projection_matrix.z.w)
		params.push_back(projection_matrix.w.x)
		params.push_back(projection_matrix.w.y)
		params.push_back(projection_matrix.w.z)
		params.push_back(projection_matrix.w.w)
		# push the viewport resolution
		params.push_back(size.x)
		params.push_back(size.y)
		# push the current time
		params.push_back(Time.get_ticks_msec())
		
		# when frame is not refreshed
		if not Global.refresh_frame:
			# UNIFORM SETUP
			var uniform = get_uniform_img(color_image)
			var color_set := UniformSetCacheRD.get_cache(shader, 0, [uniform])
			# depth is a sampler for some reason idfk
			uniform = RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
			uniform.binding = 0
			uniform.add_id(sampler)
			uniform.add_id(depth_image)
			var depth_set := UniformSetCacheRD.get_cache(shader, 1, [uniform])
			#print_debug(motion_image)
			uniform = get_uniform_img(motion_image)
			# TODO: err here
			var motion_set := UniformSetCacheRD.get_cache(shader, 2, [uniform])
			var prev_set := UniformSetCacheRD.get_cache(shader, 3, [get_uniform_img(previous_image)])
			# init params
			if parameters.is_valid():
				rd.buffer_update(parameters, 0, params.size() * 4, params.to_byte_array())
			else:
				parameters = rd.storage_buffer_create(params.size() * 4, params.to_byte_array())
			uniform = RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.binding = 0
			uniform.add_id(parameters)
			var parameter_set := UniformSetCacheRD.get_cache(shader, 4, [uniform])
			# bind to compute list
			var compute_list := rd.compute_list_begin()
			rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
			rd.compute_list_bind_uniform_set(compute_list, color_set, 0)
			rd.compute_list_bind_uniform_set(compute_list, depth_set, 1)
			rd.compute_list_bind_uniform_set(compute_list, motion_set, 2)
			rd.compute_list_bind_uniform_set(compute_list, prev_set, 3)
			rd.compute_list_bind_uniform_set(compute_list, parameter_set, 4)
			rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
			rd.compute_list_end()
		# when frame is refreshed
		var color_set = UniformSetCacheRD.get_cache(buffer_shader, 0, [get_uniform_img(color_image)])
		var buffer_set = UniformSetCacheRD.get_cache(buffer_shader, 1, [get_uniform_img(previous_image)])
		# Run Loop Frame compute shader
		var compute_list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, buffer_pipeline)
		rd.compute_list_bind_uniform_set(compute_list, color_set, 0)
		rd.compute_list_bind_uniform_set(compute_list, buffer_set, 1)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
		rd.compute_list_end()
		
		Global.refresh_frame = false
