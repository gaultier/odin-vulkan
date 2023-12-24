
package main

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "vendor:sdl2"

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

	instance := vk.create_instance(window)

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


		end_frame_ms := sdl2.GetTicks()
		assert(begin_frame_ms <= end_frame_ms)
		elapsed_ms := end_frame_ms - begin_frame_ms
		if (elapsed_ms < frame_duration_ms) {
			sdl2.LogWarn(
				c.int(sdl2.LogCategory.APPLICATION),
				"%d %d",
				elapsed_ms,
				frame_duration_ms,
			)
			sdl2.Delay(frame_duration_ms - elapsed_ms)
		}
		free_all(context.temp_allocator)
	}
}
