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

pick_physical_device :: proc(instance: vulkan.Instance) -> (vulkan.PhysicalDevice, bool) {
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
		if !is_device_suitable(d) do continue

		return d, true
	}

	return nil, false
}

is_device_suitable :: proc(device: vulkan.PhysicalDevice) -> bool {
	properties: vulkan.PhysicalDeviceProperties = {}
	vulkan.GetPhysicalDeviceProperties(device, &properties)

	features: vulkan.PhysicalDeviceFeatures = {}
	vulkan.GetPhysicalDeviceFeatures(device, &features)

	is_gpu := properties.deviceType == .INTEGRATED_GPU || properties.deviceType == .DISCRETE_GPU
	return is_gpu
}

setup :: proc(window: ^sdl2.Window) {
	instance := create_instance(window)

	surface: vulkan.SurfaceKHR = {}
	if !sdl2.Vulkan_CreateSurface(window, instance, &surface) {
		sdl2.LogCritical(ERR, "Failed to create surface: %s", sdl2.GetError())
		os.exit(1)
	}

	physical_device, found := pick_physical_device(instance)
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
	ensure_device_extension_support(physical_device)

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

ensure_device_extension_support :: proc(device: vulkan.PhysicalDevice) {
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
		sdl2.LogCritical(ERR, "Failed to find required extension: %s", r)
		os.exit(1)
	}
}
