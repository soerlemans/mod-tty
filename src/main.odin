package main

import "core:fmt"
import "core:os"
import "core:c"
import "core:strings"

import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"
import janet "janet"

App_Config :: struct {
	title:         cstring,
	bg_color:      sdl.FColor,
	fg_color:      sdl.FColor,
	spacer_color:  sdl.FColor,
	accent_color:  sdl.FColor,
	spacer_height: f32,
}

FONT_W :: 8
FONT_H :: 16

render_text_string :: proc(renderer: ^sdl.Renderer, text: string, x, y: f32, color: sdl.Color) {
    font := get_system_font()
    if font == nil do return

	c_text := strings.clone_to_cstring(text, context.temp_allocator)

	surface := ttf.RenderText_Blended(font, (^u8)(c_text), 0, color)
    if surface == nil do return
    defer sdl.DestroySurface(surface)

    texture := sdl.CreateTextureFromSurface(renderer, surface)
    if texture == nil do return
    defer sdl.DestroyTexture(texture)

    dst_rect := sdl.FRect{
        x = x,
        y = y,
        w = f32(surface.w),
        h = f32(surface.h),
    }

    sdl.RenderTexture(renderer, texture, nil, &dst_rect)
}

render_string :: proc(renderer: ^sdl.Renderer, text: string, col, row: f32, color: sdl.FColor) {
	byte_color: sdl.Color
	byte_color.r = u8(color.r * 255)
	byte_color.g = u8(color.g * 255)
	byte_color.b = u8(color.b * 255)
	byte_color.a = u8(color.a * 255)

	render_text_string(renderer, text, col * FONT_W, row * FONT_H, byte_color)
}


main :: proc() {
	// 1. Initialize Janet VM via our module
	janet.janet_init()
	defer janet.janet_deinit()

	config := load_janet_config("init.janet")
	fmt.println("Loaded config from Janet module successfully!")

	// 2. Initialize SDL3
	if !sdl.Init({.VIDEO}) {
		fmt.println("Failed to initialize SDL3:", sdl.GetError())
		return
	}
	defer sdl.Quit()

	cols, rows := 80, 24
	win_w := i32(cols * FONT_W)
	win_h := i32(f32(rows * FONT_H) + config.spacer_height)

	window := sdl.CreateWindow(config.title, win_w, win_h, {.RESIZABLE})
	if window == nil do return
	defer sdl.DestroyWindow(window)

	_ = sdl.StartTextInput(window)
	defer _ = sdl.StopTextInput(window)

	renderer := sdl.CreateRenderer(window, nil)
	if renderer == nil do return
	defer sdl.DestroyRenderer(renderer)

	input_buffer: [128]u8
	input_len: int = 0

	running := true
	last_tick := sdl.GetTicks()
	frame_count: u32 = 0
	fps: f32 = 60.0

	for running {
		current_tick := sdl.GetTicks()
		frame_count += 1
		if current_tick - last_tick >= 1000 {
			fps = f32(frame_count) * 1000.0 / f32(current_tick - last_tick)
			frame_count = 0
			last_tick = current_tick
		}

		event: sdl.Event
		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				running = false
			case .KEY_DOWN:
				if event.key.key == sdl.K_BACKSPACE && input_len > 0 {
					input_len -= 1
				} else if event.key.key == sdl.K_RETURN {
					input_len = 0
				}
			case .TEXT_INPUT:
				text_bytes := string(event.text.text)
				for i in 0..<len(text_bytes) {
					if input_len < len(input_buffer) {
						input_buffer[input_len] = text_bytes[i]
						input_len += 1
					}
				}
			}
		}

		sdl.SetRenderDrawColorFloat(renderer, config.bg_color.r, config.bg_color.g, config.bg_color.b, 1.0)
		sdl.RenderClear(renderer)

		render_string(renderer, "ModTTY Terminal Shell", 2, 2, config.fg_color)
		render_string(renderer, "> ", 2, 4, config.accent_color)
		if input_len > 0 {
			user_str := string(input_buffer[:input_len])
			render_string(renderer, user_str, 4, 4, config.fg_color)
		}

		if (sdl.GetTicks() / 500) % 2 == 0 {
			cursor_x := f32(4 + input_len) * FONT_W
			cursor_rect := sdl.FRect{cursor_x, 4 * FONT_H, FONT_W, FONT_H}
			sdl.SetRenderDrawColorFloat(renderer, config.accent_color.r, config.accent_color.g, config.accent_color.b, 1.0)
			sdl.RenderFillRect(renderer, &cursor_rect)
		}

		// Diagnostic spacer bar
		spacer_rect := sdl.FRect{
			0,
			f32(win_h) - config.spacer_height,
			f32(win_w),
			config.spacer_height,
		}
		sdl.SetRenderDrawColorFloat(renderer, config.spacer_color.r, config.spacer_color.g, config.spacer_color.b, 1.0)
		sdl.RenderFillRect(renderer, &spacer_rect)

		diag_text := fmt.tprintf("FPS: %.1f | Spacer: %.0fpix | Status: Active", fps, config.spacer_height)
		render_string(renderer, diag_text, 1, f32(win_h - 18) / FONT_H, config.accent_color)

		sdl.RenderPresent(renderer)
	}
}

load_janet_config :: proc(filename: cstring) -> App_Config {
	cfg := App_Config{
		title         = "ModTTY",
		bg_color      = {0.07, 0.07, 0.09, 1.0},
		fg_color      = {0.86, 0.86, 0.80, 1.0},
		spacer_color  = {0.15, 0.15, 0.20, 1.0},
		accent_color  = {0.40, 0.80, 1.00, 1.0},
		spacer_height = 24.0,
	}

	env := janet.janet_core_env(nil)
	data, err := os.read_entire_file_from_path(string(filename), context.allocator)
	if err != nil {
		fmt.println("Could not find init.janet, using default parameters.")
		return cfg
	}
	defer delete(data)

	out: janet.Janet
	ret := janet.janet_dostring(env, cstring(raw_data(data)), filename, &out)
	if ret != 0 {
		fmt.println("Error evaluating init.janet script!")
		return cfg
	}

	config_key := janet.janet_ckeywordv("config")
	config_table_janet := janet.janet_table_get(env, config_key)
	if config_table_janet != 0 {
		config_table := (^janet.JanetTable)(uintptr(config_table_janet))
		
		spacer_val := janet.janet_table_get(config_table, janet.janet_ckeywordv("spacer-height"))
		if spacer_val != 0 {
			cfg.spacer_height = f32(janet.janet_unwrap_integer(spacer_val))
		}
	}

	return cfg
}
