package main

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "vendor:sdl2"
import "vendor:vulkan"

import "vk"

frame_duration_ms: u32 = 1 / 60

main :: proc() {
	if sdl2.Init(sdl2.INIT_VIDEO | sdl2.INIT_EVENTS) < 0 {
		os.exit(1)
	}
	sdl2.LogSetAllPriority(.VERBOSE)

	if sdl2.Vulkan_LoadLibrary(nil) < 0 {
		sdl2.LogCritical(
			c.int(sdl2.LogCategory.ERROR),
			"Failed to load vulkan library: %s",
			sdl2.GetError(),
		)
		os.exit(1)
	}

	window := sdl2.CreateWindow("Hello", 0, 0, 800, 600, {sdl2.WindowFlags.VULKAN})
	if window == nil {
		sdl2.LogCritical(
			c.int(sdl2.LogCategory.ERROR),
			"Failed to create window: %s",
			sdl2.GetError(),
		)
		os.exit(1)
	}

	renderer := vk.setup(window)

	for {
		begin_frame_ms := sdl2.GetTicks()

		e: sdl2.Event = {}
		for sdl2.PollEvent(&e) {
			#partial switch e.type {
			case .QUIT:
				os.exit(0)
			case .KEYDOWN:
				#partial switch e.key.keysym.sym {
				case .ESCAPE:
					os.exit(0)
				}
			}
		}

		vk.draw_frame(&renderer)


		vulkan.DeviceWaitIdle(renderer.logical_device)
	}
}
