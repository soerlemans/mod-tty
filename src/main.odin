package main

import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/posix"

import j "janet"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

import u "sys_util"
import vterm "sys_vterm"


AppConfig :: struct {
	title:         cstring,
	bg_color:      sdl.FColor,
	fg_color:      sdl.FColor,
	spacer_color:  sdl.FColor,
	accent_color:  sdl.FColor,
	spacer_height: f32,
}

RenderContext :: struct {
	renderer: ^sdl.Renderer,
	font:     ^ttf.Font,
}

load_app_config :: proc(env: ^j.JanetTable, filename: string) -> AppConfig {
	// 1. Safe default config fallback
	cfg := AppConfig {
		title         = "ModTTY - Default",
		bg_color      = sdl.FColor{18.0 / 255.0, 18.0 / 255.0, 24.0 / 255.0, 1.0},
		fg_color      = sdl.FColor{220.0 / 255.0, 220.0 / 255.0, 204.0 / 255.0, 1.0},
		accent_color  = sdl.FColor{100.0 / 255.0, 200.0 / 255.0, 255.0 / 255.0, 1.0},
		spacer_color  = sdl.FColor{40.0 / 255.0, 40.0 / 255.0, 55.0 / 255.0, 1.0},
		spacer_height = 24.0,
	}

	file_data, err := os.read_entire_file(filename, context.allocator)
	if err != nil {
		fmt.eprintln("%s not found. Using default config.", filename)
		return cfg
	}
	defer delete(file_data)

	c_source := strings.clone_to_cstring(string(file_data), context.temp_allocator)

	eval_result: j.Janet
	// janet_dostring returns 0 on success.
	if j.janet_dostring(env, c_source, "filename", &eval_result) == 0 {
		type_kind := j.janet_type(eval_result)
		if type_kind == j.JanetType.JANET_TABLE {
			config_table := j.janet_unwrap_table(eval_result)
			if config_table != nil {
				spacer_val := j.janet_table_get(config_table, j.janet_cstringv("spacer-height"))
				// Ensure it's a valid number before unwrapping integer
				if spacer_val != 0 {
					cfg.spacer_height = f32(j.janet_unwrap_integer(spacer_val))
					fmt.eprintln("Spacer heigh: ", cfg.spacer_height)
				}
			}
		} else {
			fmt.eprintln("Warning: Unhandled janet type", type_kind)
		}
	} else {
		fmt.eprintln("Error evaluating init.janet script.")
	}

	return cfg
}

render_text_string :: proc(
	ctx: ^RenderContext,
	text: string,
	x, y: f32,
	color: sdl.Color,
) {
	c_text := strings.clone_to_cstring(text, context.temp_allocator)

	surface := ttf.RenderText_Blended(ctx.font, (^u8)(c_text), 0, color)
	if surface == nil do return
	defer sdl.DestroySurface(surface)

	texture := sdl.CreateTextureFromSurface(ctx.renderer, surface)
	if texture == nil do return
	defer sdl.DestroyTexture(texture)

	dst_rect := sdl.FRect {
		x = x,
		y = y,
		w = f32(surface.w),
		h = f32(surface.h),
	}

	sdl.RenderTexture(ctx.renderer, texture, nil, &dst_rect)
}

render_string :: proc(
	ctx: ^RenderContext,
	text: string,
	col, row: f32,
	color: sdl.FColor,
) {
	byte_color: sdl.Color
	byte_color.r = u8(color.r * 255)
	byte_color.g = u8(color.g * 255)
	byte_color.b = u8(color.b * 255)
	byte_color.a = u8(color.a * 255)


	x := col * f32(font_w)
	y := row * f32(font_h)

	render_text_string(ctx, text, x, y, byte_color)
}

render_spacer_bar :: proc(
	ctx: ^RenderContext,
	win_h, win_w: f32,
	config: ^AppConfig,
	fps: f32,
) {
	// Diagnostic spacer bar.
	spacer_rect := sdl.FRect {
		0,
		f32(win_h) - config.spacer_height,
		f32(win_w),
		config.spacer_height,
	}
	sdl.SetRenderDrawColorFloat(
		ctx.renderer,
		config.spacer_color.r,
		config.spacer_color.g,
		config.spacer_color.b,
		1.0,
	)
	sdl.RenderFillRect(ctx.renderer, &spacer_rect)

	y := f32(win_h - 18) / f32(font_h)
	diag_text := fmt.tprintf(
		"FPS: %.1f | Spacer: %.0fpix | Status: Active",
		fps,
		config.spacer_height,
	)
		render_string(ctx, diag_text, 1, y, config.accent_color)
}

shell_process :: proc() {
	posix.setenv("TERM", "xterm-256color", true)
	term := libc.getenv("TERM")
	// shell := libc.getenv("SHELL")

	// Easier to debug then ZSH for now.
	posix.setenv("PS1", "~ ", true)
	shell := cstring("/bin/sh")
	if len(shell) == 0 {
		shell = cstring("/bin/sh")
	}

	// TODO: Have this log back to master pid_t somehow.
	fmt.println("TERM=", term)
	fmt.println("SHELL=", shell)

	posix.execlp(shell, shell, nil)
	libc.perror("execlp")
	os.exit(1)
}

pty_init :: proc() -> posix.FD {
	// PTY setup.
	master_fd: posix.FD = 0
	// TODO: Update dynamically.
	ws := u.winsize {
		ws_row    = 24,
		ws_col    = 80,
		ws_xpixel = 0,
		ws_ypixel = 0,
	}
	pid := u.forkpty(&master_fd, nil, nil, &ws)
	if pid < 0 {
		libc.perror("Failed to open PTY")
		os.exit(0)
	}

	// Child process launch shell.
	if pid == 0 {
		shell_process()
	}

	// Set master PTY non-blocking so we can poll it cleanly in the UI loop
	flags := posix.fcntl(master_fd, .GETFL, 0)

	O_NONBLOCK := transmute(c.int)posix.O_Flags{.NONBLOCK}
	posix.fcntl(master_fd, .SETFL, flags | O_NONBLOCK, 0)

	return master_fd
}

main :: proc() {
	// Initialize Janet VM, and load configuration.
	j.janet_init()
	defer j.janet_deinit()

	env := j.janet_core_env(nil)
	config := load_app_config(env, "init.janet")

	// PTY setup.
	master_fd := pty_init()
	defer posix.close(master_fd)

	// SDL3 init.
	if !sdl.Init({.VIDEO}) {
		fmt.println("Failed to initialize SDL3:", sdl.GetError())
		return
	}
	defer sdl.Quit()

	if !ttf.Init() {
		fmt.println("Failed to initialize TTF:", sdl.GetError())
		return
	}
	defer ttf.Quit()

	// Load font.
	font := load_font()
	defer ttf.CloseFont(font)

	cols, rows: i32 = 80, 30
	win_w := i32(cols * font_w)
	win_h := i32(f32(rows * font_h) + config.spacer_height)

	window := sdl.CreateWindow(config.title, win_w, win_h, {.RESIZABLE})
	if window == nil do return
	defer sdl.DestroyWindow(window)

	_ = sdl.StartTextInput(window)
	defer _ = sdl.StopTextInput(window)

	// Create renderer for the window.
	renderer := sdl.CreateRenderer(window, nil)
	if renderer == nil do return
	defer sdl.DestroyRenderer(renderer)

	ctx := RenderContext{renderer, font}

	// Create a text engine tied to your SDL renderer.
	text_engine := ttf.CreateRendererTextEngine(renderer)
	if text_engine == nil {
		fmt.eprintln("Failed to create text engine:", sdl.GetError())
	}
	defer ttf.DestroyRendererTextEngine(text_engine)

	last_tick := sdl.GetTicks()
	frame_count: u32 = 0
	fps: f32 = 60.0

	running := true
	output: string
	input_buffer: [256]u8
	input_len: int = 0
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
					fmt.println("Sending command:", string(input_buffer[:input_len]))
					input_buffer[input_len] = '\r'
					input_len += 1
					posix.write(master_fd, raw_data(input_buffer[:input_len]), uint(input_len))
					input_len = 0
				}
			case .TEXT_INPUT:
				text_bytes := string(event.text.text)
				for i in 0 ..< len(text_bytes) {
					if input_len < len(input_buffer) {
						input_buffer[input_len] = text_bytes[i]
						input_len += 1
					}
				}
			}
		}

		sdl.SetRenderDrawColorFloat(
			renderer,
			config.bg_color.r,
			config.bg_color.g,
			config.bg_color.b,
			1.0,
		)
		sdl.RenderClear(renderer)

		read_buf: [4096]u8
		bytes_read := posix.read(master_fd, raw_data(read_buf[:]), len(read_buf))
		if bytes_read > 0 {
			output = string(read_buf[:bytes_read])
			fmt.printf("output: %s\n", output)
		} else if bytes_read == 0 {
			// EOF: child closed the PTY.
			running = false
		} else {
			// n == -1: check errno.
			err := posix.errno()
			if !(err == .EAGAIN || err == .EWOULDBLOCK) {
				// EIO (child exited on Linux) or another real error
				libc.perror("Error.")
				running = false
			}
		}

		render_string(&ctx, "> ", 2, 4, config.accent_color)
		if input_len > 0 {
			user_str := string(input_buffer[:input_len])
			render_string(&ctx, user_str, 4, 4, config.fg_color)
		}

		// TODO: Internal render is not loading???
		// Its only briefly visible and then gets overwriten again?
		render_string(&ctx, "Out: ", 2, 6, config.fg_color)
		if len(output) > 0 {
				// if idx := strings.index_any(output, "\r\n"); idx != -1 {
				// 		output = output[:idx]
				// }
			render_string(&ctx, output, 4, 6, config.fg_color)
		}

		if (sdl.GetTicks() / 500) % 2 == 0 {
			cursor_x := f32(4 + input_len) * f32(font_w)
			cursor_y := f32(4 * font_h)
			cursor_rect := sdl.FRect{cursor_x, cursor_y, f32(font_w), f32(font_h)}

			sdl.SetRenderDrawColorFloat(
				renderer,
				config.accent_color.r,
				config.accent_color.g,
				config.accent_color.b,
				1.0,
			)
			sdl.RenderFillRect(renderer, &cursor_rect)
		}

		render_spacer_bar(&ctx, f32(win_h), f32(win_w), &config, fps)

		sdl.RenderPresent(renderer)
	}
}
