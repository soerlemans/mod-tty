package main

import "core:fmt"
import "core:os"
import "core:c"

import sdl "vendor:sdl3"
import "janet"

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

FONT_BITMAP := [128][16]u8{
	'A' = {0x00, 0x00, 0x18, 0x3C, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},
	'B' = {0x00, 0x00, 0x7C, 0x66, 0x66, 0x7C, 0x66, 0x66, 0x7C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},
	'C' = {0x00, 0x00, 0x3C, 0x66, 0x60, 0x60, 0x60, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},
	'D' = {0x00, 0x00, 0x78, 0x6C, 0x66, 0x66, 0x66, 0x6C, 0x78, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},
	'>' = {0x00, 0x00, 0x60, 0x30, 0x18, 0x0C, 0x18, 0x30, 0x60, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},
	':' = {0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},
	' ' = {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},
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

		render_string(renderer, "ModTTY Terminal Shell [Janet Module Configured]", 2, 2, config.fg_color)
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

render_string :: proc(renderer: ^sdl.Renderer, text: string, col, row: f32, color: sdl.FColor) {
	sdl.SetRenderDrawColorFloat(renderer, color.r, color.g, color.b, 1.0)
	for i in 0..<len(text) {
		ch := text[i]
		if ch > 127 do continue
		
		start_x := (col + f32(i)) * FONT_W
		start_y := row * FONT_H

		bitmap := FONT_BITMAP[ch]
		for y in 0..<16 {
			row_byte := bitmap[y]
			for x in 0..<8 {
				if (row_byte & (0x80 >> u8(x))) != 0 {
					pixel := sdl.FRect{start_x + f32(x), start_y + f32(y), 1, 1}
					sdl.RenderFillRect(renderer, &pixel)
				}
			}
		}
	}
}