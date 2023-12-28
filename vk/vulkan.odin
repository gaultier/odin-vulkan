package vk

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "vendor:sdl2"
import "vendor:vulkan"

ERR: c.int : c.int(sdl2.LogCategory.ERROR)
APP: c.int : c.int(sdl2.LogCategory.APPLICATION)

VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"}

REQUIRED_EXTENSIONS := [?]cstring{vulkan.KHR_SWAPCHAIN_EXTENSION_NAME}

SwapchainSupportDetails :: struct {
	capabilities:  vulkan.SurfaceCapabilitiesKHR,
	formats:       []vulkan.SurfaceFormatKHR,
	present_modes: []vulkan.PresentModeKHR,
}

Renderer :: struct {
	extent:                    vulkan.Extent2D,
	logical_device:            vulkan.Device,
	command_buffer:            vulkan.CommandBuffer,
	command_pool:              vulkan.CommandPool,
	render_pass:               vulkan.RenderPass,
	frame_buffers:             []vulkan.Framebuffer,
	pipeline:                  vulkan.Pipeline,
	physical_device:           vulkan.PhysicalDevice,
	image_format:              vulkan.Format,
	images:                    []vulkan.Image,
	swapchain:                 vulkan.SwapchainKHR,
	instance:                  vulkan.Instance,
	image_available_semaphore: vulkan.Semaphore,
	render_finished_semaphore: vulkan.Semaphore,
	in_flight_fence:           vulkan.Fence,
}

get_instance_extensions :: proc(window: ^sdl2.Window) -> []cstring {
	extension_count: u32 = 0
	if !sdl2.Vulkan_GetInstanceExtensions(window, &extension_count, nil) {
		sdl2.LogCritical(ERR, "Failed to get extensions count: %s", sdl2.GetError())
		os.exit(1)
	}
	extension_names := make([]cstring, extension_count)
	if !sdl2.Vulkan_GetInstanceExtensions(window, &extension_count, raw_data(extension_names)) {
		sdl2.LogCritical(ERR, "Failed to get extension names: %s", sdl2.GetError())
		os.exit(1)
	}

	return extension_names
}

enable_validation_layers :: proc() -> []cstring {
	layer_count: u32 = 0
	if r := vulkan.EnumerateInstanceLayerProperties(&layer_count, nil); r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to get layer count: %d", r)
		os.exit(1)
	}


	layers := make([]vulkan.LayerProperties, layer_count)
	defer delete(layers)

	if r := vulkan.EnumerateInstanceLayerProperties(&layer_count, raw_data(layers));
	   r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to get layer count: %d", r)
		os.exit(1)
	}

	outer: for name in VALIDATION_LAYERS {
		for layer in &layers {
			layerName := transmute(cstring)&layer.layerName[0]
			fmt.println(layerName)
			if name == layerName do continue outer
		}
		sdl2.LogCritical(ERR, "Validation layer not available: %s", name)
		os.exit(1)
	}

	sdl2.LogDebug(APP, "Validation layers enabled")
	return VALIDATION_LAYERS[:]
}

create_instance :: proc(window: ^sdl2.Window) -> vulkan.Instance {
	getInstanceProcAddr := sdl2.Vulkan_GetVkGetInstanceProcAddr()
	assert(getInstanceProcAddr != nil)

	vulkan.load_proc_addresses_global(getInstanceProcAddr)
	assert(vulkan.CreateInstance != nil)

	app_info: vulkan.ApplicationInfo = {
		sType              = .APPLICATION_INFO,
		applicationVersion = vulkan.MAKE_VERSION(0, 0, 1),
		engineVersion      = vulkan.MAKE_VERSION(0, 0, 1),
		apiVersion         = vulkan.MAKE_VERSION(1, 0, 0),
	}

	extension_names := get_instance_extensions(window)
	for e in extension_names {
		sdl2.LogDebug(APP, "Extension: %s", e)
	}

	create_info: vulkan.InstanceCreateInfo = {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = u32(len(extension_names)),
		ppEnabledExtensionNames = raw_data(extension_names),
	}

	when ODIN_DEBUG {
		layers := enable_validation_layers()
		create_info.enabledLayerCount = u32(len(layers))
		create_info.ppEnabledLayerNames = raw_data(layers)
	}

	instance: vulkan.Instance = {}
	assert(vulkan.CreateInstance != nil)
	if r := vulkan.CreateInstance(&create_info, nil, &instance); r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to get layer count: %d", r)
		os.exit(1)
	}

	vulkan.load_proc_addresses_instance(instance)
	return instance
}

pick_physical_device :: proc(
	instance: vulkan.Instance,
	surface: vulkan.SurfaceKHR,
) -> (
	vulkan.PhysicalDevice,
	SwapchainSupportDetails,
	bool,
) {
	assert(vulkan.EnumeratePhysicalDevices != nil)

	device_count: u32 = 0
	if r := vulkan.EnumeratePhysicalDevices(instance, &device_count, nil); r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to get layer count: %d", r)
		os.exit(1)
	}
	if device_count == 0 {
		sdl2.LogCritical(ERR, "No physical devices")
		os.exit(1)
	}

	devices := make([]vulkan.PhysicalDevice, device_count)

	if r := vulkan.EnumeratePhysicalDevices(instance, &device_count, raw_data(devices));
	   r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to get layer count: %d", r)
		os.exit(1)
	}

	for d in devices {
		details, suitable := is_device_suitable(d, surface)
		if !suitable do continue

		return d, details, true
	}

	return nil, {}, false
}

is_device_suitable :: proc(
	device: vulkan.PhysicalDevice,
	surface: vulkan.SurfaceKHR,
) -> (
	SwapchainSupportDetails,
	bool,
) {
	properties: vulkan.PhysicalDeviceProperties = {}
	vulkan.GetPhysicalDeviceProperties(device, &properties)

	features: vulkan.PhysicalDeviceFeatures = {}
	vulkan.GetPhysicalDeviceFeatures(device, &features)

	if !has_device_extension_support(device) do return {}, false

	is_gpu := properties.deviceType == .INTEGRATED_GPU || properties.deviceType == .DISCRETE_GPU

	swapchain_support_details := query_swapchain_support(device, surface)
	is_swapchain_suitable :=
		len(swapchain_support_details.formats) > 0 &&
		len(swapchain_support_details.present_modes) > 0

	return swapchain_support_details, is_gpu && is_swapchain_suitable
}

setup :: proc(window: ^sdl2.Window) -> Renderer {
	instance := create_instance(window)

	surface: vulkan.SurfaceKHR = {}
	if !sdl2.Vulkan_CreateSurface(window, instance, &surface) {
		sdl2.LogCritical(ERR, "Failed to create surface: %s", sdl2.GetError())
		os.exit(1)
	}

	physical_device, swapchain_support_details, found := pick_physical_device(instance, surface)
	if !found {
		sdl2.LogCritical(ERR, "Failed to find a suitable physical device")
		os.exit(1)
	}

	queue_family: u32 = 0
	queue_family, found = pick_queue_family(physical_device)
	if !found {
		sdl2.LogCritical(ERR, "Failed to find a suitable queue family")
		os.exit(1)
	}

	logical_device, queue := create_logical_device(physical_device, queue_family)

	swapchain, images, image_format, extent := create_swapchain(
		swapchain_support_details,
		logical_device,
		surface,
	)

	image_views := create_image_views(logical_device, images, image_format)
	render_pass := create_render_pass(logical_device, image_format)
	pipeline := create_graphics_pipeline(logical_device, extent, render_pass)
	frame_buffers := create_framebuffers(logical_device, image_views, render_pass, extent)
	command_pool := create_command_pool(logical_device)
	command_buffer := create_command_buffer(logical_device, command_pool)

	image_available_semaphore, render_finished_semaphore, in_flight_fence := create_sync_objects(
		logical_device,
	)

	return(
		Renderer {
			extent = extent,
			pipeline = pipeline,
			command_buffer = command_buffer,
			command_pool = command_pool,
			render_pass = render_pass,
			frame_buffers = frame_buffers,
			instance = instance,
			swapchain = swapchain,
			images = images,
			image_format = image_format,
			logical_device = logical_device,
			physical_device = physical_device,
			image_available_semaphore = image_available_semaphore,
			render_finished_semaphore = render_finished_semaphore,
			in_flight_fence = in_flight_fence,
		} \
	)
}

pick_queue_family :: proc(device: vulkan.PhysicalDevice) -> (u32, bool) {
	count: u32 = 0
	vulkan.GetPhysicalDeviceQueueFamilyProperties(device, &count, nil)

	properties := make([]vulkan.QueueFamilyProperties, count)
	vulkan.GetPhysicalDeviceQueueFamilyProperties(device, &count, raw_data(properties))

	for q, i in properties {
		if .GRAPHICS in q.queueFlags {
			return u32(i), true
		}
	}

	return 0, false
}

create_logical_device :: proc(
	physical_device: vulkan.PhysicalDevice,
	queue_idx: u32,
) -> (
	vulkan.Device,
	vulkan.Queue,
) {

	priority: f32 = 1.0

	queue_create_info: vulkan.DeviceQueueCreateInfo = {
		sType            = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = queue_idx,
		queueCount       = 1,
		pQueuePriorities = &priority,
	}

	features: vulkan.PhysicalDeviceFeatures = {}

	device_create_info: vulkan.DeviceCreateInfo = {
		sType                   = .DEVICE_CREATE_INFO,
		pQueueCreateInfos       = &queue_create_info,
		queueCreateInfoCount    = 1,
		pEnabledFeatures        = &features,
		enabledExtensionCount   = len(REQUIRED_EXTENSIONS),
		ppEnabledExtensionNames = raw_data(REQUIRED_EXTENSIONS[:]),
	}

	when ODIN_DEBUG {
		layers := enable_validation_layers()
		device_create_info.enabledLayerCount = u32(len(layers))
		device_create_info.ppEnabledLayerNames = raw_data(layers)
	}

	logical_device: vulkan.Device = {}
	if r := vulkan.CreateDevice(physical_device, &device_create_info, nil, &logical_device);
	   r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to create logical device: %d", r)
		os.exit(1)
	}

	queue: vulkan.Queue = {}
	vulkan.GetDeviceQueue(logical_device, queue_idx, 0, &queue)

	return logical_device, queue
}

has_device_extension_support :: proc(device: vulkan.PhysicalDevice) -> bool {
	count: u32 = 0
	if r := vulkan.EnumerateDeviceExtensionProperties(device, nil, &count, nil); r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to enumerate device extension properties: %d", r)
		os.exit(1)
	}

	properties := make([]vulkan.ExtensionProperties, count)
	defer delete(properties)

	if r := vulkan.EnumerateDeviceExtensionProperties(device, nil, &count, raw_data(properties));
	   r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to enumerate device extension properties: %d", r)
		os.exit(1)
	}

	outer: for r in REQUIRED_EXTENSIONS {
		for p in &properties {
			extensionName := transmute(cstring)&p.extensionName[0]
			if r == extensionName do continue outer
		}
		return false
	}
	return true
}

query_swapchain_support :: proc(
	device: vulkan.PhysicalDevice,
	surface: vulkan.SurfaceKHR,
) -> SwapchainSupportDetails {
	details: SwapchainSupportDetails = {}

	{
		if r := vulkan.GetPhysicalDeviceSurfaceCapabilitiesKHR(
			device,
			surface,
			&details.capabilities,
		); r != .SUCCESS {
			sdl2.LogCritical(ERR, "Failed to create logical device: %d", r)
			os.exit(1)
		}
	}

	{
		format_count: u32 = 0
		if r := vulkan.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, nil);
		   r != .SUCCESS {
			sdl2.LogCritical(ERR, "Failed to get surface formats: %d", r)
			os.exit(1)
		}

		if format_count != 0 {
			details.formats = make([]vulkan.SurfaceFormatKHR, format_count)
			if r := vulkan.GetPhysicalDeviceSurfaceFormatsKHR(
				device,
				surface,
				&format_count,
				raw_data(details.formats),
			); r != .SUCCESS {
				sdl2.LogCritical(ERR, "Failed to get surface formats: %d", r)
				os.exit(1)

			}
		}
	}

	{
		present_mode_count: u32 = 0
		if r := vulkan.GetPhysicalDeviceSurfacePresentModesKHR(
			device,
			surface,
			&present_mode_count,
			nil,
		); r != .SUCCESS {
			sdl2.LogCritical(ERR, "Failed to get surface present modes: %d", r)
			os.exit(1)
		}

		if present_mode_count != 0 {
			details.present_modes = make([]vulkan.PresentModeKHR, present_mode_count)
			if r := vulkan.GetPhysicalDeviceSurfacePresentModesKHR(
				device,
				surface,
				&present_mode_count,
				raw_data(details.present_modes),
			); r != .SUCCESS {
				sdl2.LogCritical(ERR, "Failed to get surface present modes: %d", r)
				os.exit(1)
			}
		}
	}

	return details
}

pick_swapchain_surface_format :: proc(
	formats: []vulkan.SurfaceFormatKHR,
) -> vulkan.SurfaceFormatKHR {
	assert(len(formats) > 0)

	for format in formats {
		if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR do return format
	}

	return formats[0]
}

pick_swapchain_present_mode :: proc(
	present_modes: []vulkan.PresentModeKHR,
) -> vulkan.PresentModeKHR {
	return .FIFO
}

pick_swapchain_extent :: proc(capabilities: vulkan.SurfaceCapabilitiesKHR) -> vulkan.Extent2D {
	if capabilities.currentExtent.width != max(u32) do return capabilities.currentExtent

	mode: sdl2.DisplayMode = {}
	if sdl2.GetCurrentDisplayMode(0, &mode) < 0 {
		sdl2.LogCritical(ERR, "Failed to get current display mode: %s", sdl2.GetError())
		os.exit(1)
	}

	w: u32 = clamp(
		u32(mode.w),
		capabilities.minImageExtent.width,
		capabilities.maxImageExtent.width,
	)
	h: u32 = clamp(
		u32(mode.h),
		capabilities.minImageExtent.height,
		capabilities.maxImageExtent.height,
	)


	return vulkan.Extent2D{width = w, height = h}
}

create_swapchain :: proc(
	details: SwapchainSupportDetails,
	device: vulkan.Device,
	surface: vulkan.SurfaceKHR,
) -> (
	vulkan.SwapchainKHR,
	[]vulkan.Image,
	vulkan.Format,
	vulkan.Extent2D,
) {
	surface_format := pick_swapchain_surface_format(details.formats)
	present_mode := pick_swapchain_present_mode(details.present_modes)
	extent := pick_swapchain_extent(details.capabilities)

	min_image_count := clamp(
		details.capabilities.minImageCount + 1,
		details.capabilities.minImageCount,
		details.capabilities.maxImageCount > 0 \
		? details.capabilities.maxImageCount \
		: details.capabilities.minImageCount,
	)
	assert(min_image_count >= details.capabilities.minImageCount)

	create_info: vulkan.SwapchainCreateInfoKHR = {
		sType = .SWAPCHAIN_CREATE_INFO_KHR,
		surface = surface,
		minImageCount = min_image_count,
		imageFormat = surface_format.format,
		imageColorSpace = surface_format.colorSpace,
		imageExtent = extent,
		imageArrayLayers = 1,
		imageUsage = {.COLOR_ATTACHMENT},
		imageSharingMode = .EXCLUSIVE, // Assume 1 queue family.
		preTransform = details.capabilities.currentTransform,
		compositeAlpha = {.OPAQUE},
		presentMode = present_mode,
		clipped = true,
	}

	swapchain: vulkan.SwapchainKHR = {}
	if r := vulkan.CreateSwapchainKHR(device, &create_info, nil, &swapchain); r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to get create swapchain: %d", r)
		os.exit(1)
	}

	actual_image_count: u32 = 0
	if r := vulkan.GetSwapchainImagesKHR(device, swapchain, &actual_image_count, nil); r != nil {
		sdl2.LogCritical(ERR, "Failed to get swapchain images: %d", r)
		os.exit(1)
	}

	images := make([]vulkan.Image, actual_image_count)
	if r := vulkan.GetSwapchainImagesKHR(device, swapchain, &actual_image_count, raw_data(images));
	   r != nil {
		sdl2.LogCritical(ERR, "Failed to get swapchain images: %d", r)
		os.exit(1)
	}

	return swapchain, images, surface_format.format, extent
}

create_image_views :: proc(
	device: vulkan.Device,
	images: []vulkan.Image,
	swapchain_image_format: vulkan.Format,
) -> []vulkan.ImageView {
	image_views := make([]vulkan.ImageView, len(images))

	for image_view, i in &image_views {
		create_info: vulkan.ImageViewCreateInfo = {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = images[i],
			viewType = .D2,
			format = swapchain_image_format,
			subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
		}

		if r := vulkan.CreateImageView(device, &create_info, nil, &image_view); r != .SUCCESS {
			sdl2.LogCritical(ERR, "Failed to create image view: %d", r)
			os.exit(1)
		}
	}

	return image_views
}

create_graphics_pipeline :: proc(
	device: vulkan.Device,
	swapchain_extent: vulkan.Extent2D,
	render_pass: vulkan.RenderPass,
) -> vulkan.Pipeline {
	vert_bytecode: []byte
	ok: bool
	vert_bytecode, ok = os.read_entire_file_from_filename("vert.spv")
	if !ok {
		sdl2.LogCritical(ERR, "Failed to load vert.spv")
		os.exit(1)
	}
	vert_shader_module := create_shader_module(device, vert_bytecode)
	defer vulkan.DestroyShaderModule(device, vert_shader_module, nil)

	frag_bytecode: []byte
	frag_bytecode, ok = os.read_entire_file_from_filename("frag.spv")
	if !ok {
		sdl2.LogCritical(ERR, "Failed to load frag.spv")
		os.exit(1)
	}

	frag_shader_module := create_shader_module(device, frag_bytecode)
	defer vulkan.DestroyShaderModule(device, frag_shader_module, nil)


	vert_shader_stage_info: vulkan.PipelineShaderStageCreateInfo = {
		sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage = {.VERTEX},
		module = vert_shader_module,
		pName = "main",
	}

	frag_shader_stage_info: vulkan.PipelineShaderStageCreateInfo = {
		sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage = {.FRAGMENT},
		module = frag_shader_module,
		pName = "main",
	}

	shader_stages: [2]vulkan.PipelineShaderStageCreateInfo =  {
		vert_shader_stage_info,
		frag_shader_stage_info,
	}

	dynamic_states: [2]vulkan.DynamicState = {.VIEWPORT, .SCISSOR}

	dynamic_state: vulkan.PipelineDynamicStateCreateInfo = {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = len(dynamic_states),
		pDynamicStates    = raw_data(dynamic_states[:]),
	}

	vertex_input_info: vulkan.PipelineVertexInputStateCreateInfo = {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	}

	input_assembly: vulkan.PipelineInputAssemblyStateCreateInfo = {
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
	}

	viewport: vulkan.Viewport = {
		width    = f32(swapchain_extent.width),
		height   = f32(swapchain_extent.height),
		maxDepth = 1.0,
	}

	scissor: vulkan.Rect2D = {
		extent = swapchain_extent,
	}

	viewport_state: vulkan.PipelineViewportStateCreateInfo = {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	rasterizer: vulkan.PipelineRasterizationStateCreateInfo = {
		sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		lineWidth = 1.0,
		cullMode = {.BACK},
		frontFace = .CLOCKWISE,
	}

	multisampling: vulkan.PipelineMultisampleStateCreateInfo = {
		sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
		minSampleShading = 1.0,
	}

	color_blend_attachment: vulkan.PipelineColorBlendAttachmentState = {
		colorWriteMask = {.R, .G, .B, .A},
		srcColorBlendFactor = .ONE,
		dstColorBlendFactor = .ZERO,
		colorBlendOp = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ZERO,
		alphaBlendOp = .ADD,
	}

	color_blending: vulkan.PipelineColorBlendStateCreateInfo = {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &color_blend_attachment,
	}

	pipeline_layout_create_info: vulkan.PipelineLayoutCreateInfo = {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
	}
	pipeline_layout: vulkan.PipelineLayout = {}

	if r := vulkan.CreatePipelineLayout(
		device,
		&pipeline_layout_create_info,
		nil,
		&pipeline_layout,
	); r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to create pipeline layout: %d", r)
		os.exit(1)
	}

	pipeline_create_info: vulkan.GraphicsPipelineCreateInfo = {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = 2,
		pStages             = raw_data(shader_stages[:]),
		pVertexInputState   = &vertex_input_info,
		pInputAssemblyState = &input_assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &rasterizer,
		pMultisampleState   = &multisampling,
		pColorBlendState    = &color_blending,
		pDynamicState       = &dynamic_state,
		layout              = pipeline_layout,
		renderPass          = render_pass,
		basePipelineIndex   = -1,
	}

	pipeline: vulkan.Pipeline = {}
	if r := vulkan.CreateGraphicsPipelines(device, 0, 1, &pipeline_create_info, nil, &pipeline);
	   r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to create pipeline: %d", r)
		os.exit(1)
	}

	return pipeline
}

create_shader_module :: proc(device: vulkan.Device, bytecode: []byte) -> vulkan.ShaderModule {
	create_info: vulkan.ShaderModuleCreateInfo = {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(bytecode),
		pCode    = transmute(^u32)raw_data(bytecode),
	}

	shader_module: vulkan.ShaderModule = {}

	if r := vulkan.CreateShaderModule(device, &create_info, nil, &shader_module); r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to create shader module: %d", r)
		os.exit(1)
	}

	return shader_module
}

create_render_pass :: proc(
	device: vulkan.Device,
	swapchain_image_format: vulkan.Format,
) -> vulkan.RenderPass {
	color_attachment: vulkan.AttachmentDescription = {
		format = swapchain_image_format,
		samples = {._1},
		loadOp = .CLEAR,
		storeOp = .STORE,
		stencilLoadOp = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout = .UNDEFINED,
		finalLayout = .PRESENT_SRC_KHR,
	}

	color_attachment_ref: vulkan.AttachmentReference = {
		layout = .COLOR_ATTACHMENT_OPTIMAL,
	}

	subpass: vulkan.SubpassDescription = {
		pipelineBindPoint    = .GRAPHICS,
		colorAttachmentCount = 1,
		pColorAttachments    = &color_attachment_ref,
	}

	render_pass: vulkan.RenderPass = {}
	render_pass_create_info: vulkan.RenderPassCreateInfo = {
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &color_attachment,
		subpassCount    = 1,
		pSubpasses      = &subpass,
	}
	if r := vulkan.CreateRenderPass(device, &render_pass_create_info, nil, &render_pass);
	   r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to create render pass: %d", r)
		os.exit(1)
	}

	return render_pass
}

create_framebuffers :: proc(
	device: vulkan.Device,
	image_views: []vulkan.ImageView,
	render_pass: vulkan.RenderPass,
	extent: vulkan.Extent2D,
) -> []vulkan.Framebuffer {
	frame_buffers := make([]vulkan.Framebuffer, len(image_views))

	for view, i in image_views {
		attachments: [1]vulkan.ImageView = {view}

		framebuffer_create_info: vulkan.FramebufferCreateInfo = {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = render_pass,
			attachmentCount = 1,
			pAttachments    = raw_data(attachments[:]),
			width           = extent.width,
			height          = extent.height,
			layers          = 1,
		}

		if r := vulkan.CreateFramebuffer(device, &framebuffer_create_info, nil, &frame_buffers[i]);
		   r != .SUCCESS {
			sdl2.LogCritical(ERR, "Failed to create framebuffer: %d", r)
			os.exit(1)
		}

	}

	return frame_buffers
}

create_command_pool :: proc(device: vulkan.Device) -> vulkan.CommandPool {
	command_pool: vulkan.CommandPool = {}
	command_pool_create_info: vulkan.CommandPoolCreateInfo = {
		sType = .COMMAND_POOL_CREATE_INFO,
		flags = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = 0,
	}

	if r := vulkan.CreateCommandPool(device, &command_pool_create_info, nil, &command_pool);
	   r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to create command pool: %d", r)
		os.exit(1)
	}
	return command_pool
}

create_command_buffer :: proc(
	device: vulkan.Device,
	command_pool: vulkan.CommandPool,
) -> vulkan.CommandBuffer {
	alloc_info: vulkan.CommandBufferAllocateInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = command_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	command_buffer: vulkan.CommandBuffer = {}

	if r := vulkan.AllocateCommandBuffers(device, &alloc_info, &command_buffer); r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to allocate command buffers: %d", r)
		os.exit(1)
	}

	return command_buffer
}

record_command_buffer :: proc(
	command_buffer: vulkan.CommandBuffer,
	image_idx: u32,
	render_pass: vulkan.RenderPass,
	frame_buffers: []vulkan.Framebuffer,
	extent: vulkan.Extent2D,
	pipeline: vulkan.Pipeline,
) {
	begin_info: vulkan.CommandBufferBeginInfo = {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}

	if r := vulkan.BeginCommandBuffer(command_buffer, &begin_info); r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to begin command buffer: %d", r)
		os.exit(1)
	}

	clear_color: vulkan.ClearValue = {
		color = {float32 = {0.0, 0.0, 0.0, 1.0}},
	}

	render_pass_begin_info: vulkan.RenderPassBeginInfo = {
		sType = .RENDER_PASS_BEGIN_INFO,
		renderPass = render_pass,
		framebuffer = frame_buffers[image_idx],
		renderArea = {extent = extent},
		clearValueCount = 1,
		pClearValues = &clear_color,
	}

	vulkan.CmdBeginRenderPass(command_buffer, &render_pass_begin_info, .INLINE)

	vulkan.CmdBindPipeline(command_buffer, .GRAPHICS, pipeline)

	viewport: vulkan.Viewport = {
		width    = f32(extent.width),
		height   = f32(extent.height),
		maxDepth = 1.0,
	}
	vulkan.CmdSetViewport(command_buffer, 0, 1, &viewport)

	scissor: vulkan.Rect2D = {
		extent = extent,
	}
	vulkan.CmdSetScissor(command_buffer, 0, 1, &scissor)

	vulkan.CmdDraw(command_buffer, 3, 1, 0, 0)
	vulkan.CmdEndRenderPass(command_buffer)

	if r := vulkan.EndCommandBuffer(command_buffer); r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to end command buffer: %d", r)
		os.exit(1)
	}
}

create_sync_objects :: proc(
	device: vulkan.Device,
) -> (
	vulkan.Semaphore,
	vulkan.Semaphore,
	vulkan.Fence,
) {
	semaphore_create_info: vulkan.SemaphoreCreateInfo = {
		sType = .SEMAPHORE_CREATE_INFO,
	}

	image_available_semaphore: vulkan.Semaphore = {}
	if r := vulkan.CreateSemaphore(
		device,
		&semaphore_create_info,
		nil,
		&image_available_semaphore,
	); r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to create semaphore: %d", r)
		os.exit(1)
	}

	render_finished_semaphore: vulkan.Semaphore = {}
	if r := vulkan.CreateSemaphore(
		device,
		&semaphore_create_info,
		nil,
		&render_finished_semaphore,
	); r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to create semaphore: %d", r)
		os.exit(1)
	}

	fence_create_info: vulkan.FenceCreateInfo = {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}

	in_flight_fence: vulkan.Fence = {}
	if r := vulkan.CreateFence(device, &fence_create_info, nil, &in_flight_fence); r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to create fence: %d", r)
		os.exit(1)
	}

	return image_available_semaphore, render_finished_semaphore, in_flight_fence
}

draw_frame :: proc(renderer: ^Renderer) {
	if r := vulkan.WaitForFences(
		renderer.logical_device,
		1,
		&renderer.in_flight_fence,
		true,
		max(u64),
	); r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to wait for fences: %d", r)
		os.exit(1)
	}

	image_idx: u32 = 0
	if r := vulkan.AcquireNextImageKHR(
		renderer.logical_device,
		renderer.swapchain,
		max(u64),
		renderer.image_available_semaphore,
		{},
		&image_idx,
	); r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to acquire next image: %d", r)
		os.exit(1)
	}

	if r := vulkan.ResetCommandBuffer(renderer.command_buffer, {.RELEASE_RESOURCES});
	   r != .SUCCESS {
		sdl2.LogCritical(ERR, "Failed to reset command buffer: %d", r)
		os.exit(1)
	}

	record_command_buffer(
		renderer.command_buffer,
		image_idx,
		renderer.render_pass,
		renderer.frame_buffers,
		renderer.extent,
		renderer.pipeline,
	)
}
