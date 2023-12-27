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

setup :: proc(window: ^sdl2.Window) {
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

	swapchain, images := create_swapchain(swapchain_support_details, logical_device, surface)
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
) {
	surface_format := pick_swapchain_surface_format(details.formats)
	present_mode := pick_swapchain_present_mode(details.present_modes)
	extent := pick_swapchain_extent(details.capabilities)

	min_image_count := clamp(
		details.capabilities.minImageCount + 1,
		details.capabilities.minImageCount,
		details.capabilities.maxImageCount,
	)

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

	return swapchain, images
}
