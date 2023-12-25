package vk

import "core:c"
import "core:fmt"
import "core:os"
import "vendor:sdl2"
import "vendor:vulkan"

VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"}

get_extension_names :: proc(window: ^sdl2.Window) -> []cstring {
	extension_count: u32 = 0
	if !sdl2.Vulkan_GetInstanceExtensions(window, &extension_count, nil) {
		sdl2.LogCritical(
			c.int(sdl2.LogCategory.ERROR),
			"Failed to get extensions count: %s",
			sdl2.GetError(),
		)
		os.exit(1)
	}
	extension_names := make([]cstring, extension_count)
	if !sdl2.Vulkan_GetInstanceExtensions(window, &extension_count, raw_data(extension_names)) {
		sdl2.LogCritical(
			c.int(sdl2.LogCategory.ERROR),
			"Failed to get extension names: %s",
			sdl2.GetError(),
		)
		os.exit(1)
	}

	return extension_names
}

create_instance :: proc(window: ^sdl2.Window) -> vulkan.Instance {
	app_info: vulkan.ApplicationInfo = {
		sType              = .APPLICATION_INFO,
		pApplicationName   = "Hello",
		pEngineName        = "No Engine",
		applicationVersion = vulkan.MAKE_VERSION(0, 0, 1),
		engineVersion      = vulkan.MAKE_VERSION(0, 0, 1),
		apiVersion         = vulkan.MAKE_VERSION(0, 0, 1),
	}

	extension_names := get_extension_names(window)
	for e in extension_names {
		fmt.println(e)
	}

	create_info: vulkan.InstanceCreateInfo = {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = u32(len(extension_names)),
		ppEnabledExtensionNames = raw_data(extension_names),
	}

	//	when ODIN_DEBUG {
	//		layer_count: u32 = 0
	//		if r := vulkan.EnumerateInstanceLayerProperties(&layer_count, nil); r != .SUCCESS {
	//			sdl2.LogCritical(
	//				c.int(sdl2.LogCategory.ERROR),
	//				"Failed to get layer count: %d",
	//				r
	//			)
	//			os.exit(1)
	//		}


	//	layers := make([]vulkan.LayerProperties, layer_count)
	//		if r := vulkan.EnumerateInstanceLayerProperties(&layer_count, raw_data(layers)); r != .SUCCESS {
	//			sdl2.LogCritical(
	//				c.int(sdl2.LogCategory.ERROR),
	//				"Failed to get layer count: %d",
	//				r
	//			)
	//			os.exit(1)
	//		}

	//		outer : for name in VALIDATION_LAYERS {
	//			for layer in &layers {
	//if name == cstring(&layer.layerName[0]) do continue outer;
	//			}
	//			sdl2.LogCritical(
	//				c.int(sdl2.LogCategory.ERROR),
	//				"Validation layer not available: %s",
	//				name)
	//			os.exit(1)
	//		}
	//	
	//		create_info.ppEnabledLayerNames = &VALIDATION_LAYERS[0]
	//		create_info.enabledLayerCount = len(VALIDATION_LAYERS)
	//
	//			sdl2.LogDebug(
	//				c.int(sdl2.LogCategory.APPLICATION),
	//				"Validation layers enabled"
	//				)
	//}

	instance: vulkan.Instance = {}
	if r := vulkan.CreateInstance(&create_info, nil, &instance); r != .SUCCESS {
		fmt.eprintf("Failed to CreateInstance: %d\n", r)
	}

	return instance
}
