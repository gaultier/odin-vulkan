package vk

import "core:c"
import "core:fmt"
import "core:os"
import "vendor:sdl2"
import "vendor:vulkan"

ERR : c.int : c.int(sdl2.LogCategory.ERROR)
APP : c.int : c.int(sdl2.LogCategory.APPLICATION)

VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"}

get_instance_extensions :: proc(window: ^sdl2.Window) -> []cstring {
	extension_count: u32 = 0
	if !sdl2.Vulkan_GetInstanceExtensions(window, &extension_count, nil) {
		sdl2.LogCritical(
			ERR,
			"Failed to get extensions count: %s",
			sdl2.GetError(),
		)
		os.exit(1)
	}
	extension_names := make([]cstring, extension_count)
	if !sdl2.Vulkan_GetInstanceExtensions(window, &extension_count, raw_data(extension_names)) {
		sdl2.LogCritical(
			ERR,
			"Failed to get extension names: %s",
			sdl2.GetError(),
		)
		os.exit(1)
	}

	return extension_names
}

enable_validation_layers :: proc(create_info: ^vulkan.InstanceCreateInfo) {
		layer_count: u32 = 0
		if r := vulkan.EnumerateInstanceLayerProperties(&layer_count, nil); r != .SUCCESS {
			sdl2.LogCritical(
				ERR,
				"Failed to get layer count: %d",
				r
			)
			os.exit(1)
		}


	layers := make([]vulkan.LayerProperties, layer_count)
		if r := vulkan.EnumerateInstanceLayerProperties(&layer_count, raw_data(layers)); r != .SUCCESS {
			sdl2.LogCritical(
				ERR,
				"Failed to get layer count: %d",
				r
			)
			os.exit(1)
		}

		outer : for name in VALIDATION_LAYERS {
			for layer in &layers {
if name == cstring(&layer.layerName[0]) do continue outer;
			}
			sdl2.LogCritical(
				ERR,
				"Validation layer not available: %s",
				name)
			os.exit(1)
		}
	
		create_info.ppEnabledLayerNames = &VALIDATION_LAYERS[0]
		create_info.enabledLayerCount = len(VALIDATION_LAYERS)

		sdl2.LogDebug( APP, "Validation layers enabled")
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
			sdl2.LogDebug(
				APP,
				"Extension: %s",
				e
			)
	}

	create_info: vulkan.InstanceCreateInfo = {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = u32(len(extension_names)),
		ppEnabledExtensionNames = raw_data(extension_names),
	}

	when ODIN_DEBUG {
		enable_validation_layers(&create_info)
	}

	instance: vulkan.Instance = {}
	assert(vulkan.CreateInstance !=nil)
	if r := vulkan.CreateInstance(&create_info, nil, &instance); r != .SUCCESS {
			sdl2.LogCritical(
				ERR,
				"Failed to get layer count: %d",
				r
			)
			os.exit(1)
	}

	vulkan.load_proc_addresses_instance(instance)
	return instance
}

pick_physical_device :: proc(instance : vulkan.Instance) -> (vulkan.PhysicalDevice, bool) {
	assert(vulkan.EnumeratePhysicalDevices!=nil)

	device_count : u32 = 0	
	if r := vulkan.EnumeratePhysicalDevices(instance, &device_count, nil); r != .SUCCESS {
			sdl2.LogCritical(
				ERR,
				"Failed to get layer count: %d",
				r
			)
			os.exit(1)
	}
	if device_count == 0 {
			sdl2.LogCritical(
				ERR,
				"No physical devices"
			)
			os.exit(1)
	}

	devices := make([]vulkan.PhysicalDevice, device_count)

	if r := vulkan.EnumeratePhysicalDevices(instance, &device_count, raw_data(devices)); r != .SUCCESS {
			sdl2.LogCritical(
				ERR,
				"Failed to get layer count: %d",
				r
			)
			os.exit(1)
	}

	for d in devices {
		if !is_device_suitable(d) do continue

		return d, true
	}

	return nil, false
}

is_device_suitable :: proc(device: vulkan.PhysicalDevice) -> bool {
	properties : vulkan.PhysicalDeviceProperties = {}
  vulkan.GetPhysicalDeviceProperties(device, &properties)

	features : vulkan.PhysicalDeviceFeatures ={}
	vulkan.GetPhysicalDeviceFeatures(device, &features)

	return properties.deviceType==.INTEGRATED_GPU  || properties.deviceType==.DISCRETE_GPU 
}

setup :: proc(window: ^sdl2.Window) {
	instance := create_instance(window)
	physical_device, found := pick_physical_device(instance)
	if !found {
			sdl2.LogCritical(
				ERR,
				"Failed to find a suitable physical device"
			)
			os.exit(1)
	}
	
	queue_family : u32 = 0
	queue_family, found = pick_queue_family(physical_device)
	if !found {
			sdl2.LogCritical(
				ERR,
				"Failed to find a suitable queue family"
			)
			os.exit(1)
	}

}

pick_queue_family :: proc(device : vulkan.PhysicalDevice) -> (u32, bool) {
	count : u32 = 0
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
