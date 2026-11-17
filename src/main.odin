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

import ap "app_config"
import render "render"
import u "sys_util"
import vterm "sys_vterm"
import term "terminal"

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
	cols, rows: i32 = 80, 30

	// Initialize Janet VM, and load configuration.
	j.janet_init()
	defer j.janet_deinit()

	env := j.janet_core_env(nil)
	config := ap.load_app_config(env, "init.janet")

	// TODO: Temporary solution get font dimensions by querying.
	// So they can be updated dynamically.
	font_w := render.font_w
	font_h := render.font_h
	win_w := i32(cols * font_w)
	win_h := i32(f32(rows * font_h) + config.spacer_height)

	// PTY setup.
	master_fd := pty_init()
	defer posix.close(master_fd)

	// Libvterm setup
	terminal, state := term.init(master_fd, rows, cols)
	if state != .OK {
		fmt.println("Failed to init Terminal!")
		return
	}
	defer term.free(terminal)

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
	font := render.load_font()
	defer ttf.CloseFont(font)

	window := sdl.CreateWindow(config.title, win_w, win_h, {.RESIZABLE})
	if window == nil do return
	defer sdl.DestroyWindow(window)

	_ = sdl.StartTextInput(window)
	defer _ = sdl.StopTextInput(window)

	// Create renderer for the window.
	renderer := sdl.CreateRenderer(window, nil)
	if renderer == nil do return
	defer sdl.DestroyRenderer(renderer)

	ctx := render.RenderContext{renderer, font}

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
	output := "Test"
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
					// posix.write(master_fd, raw_data(input_buffer[:input_len]), uint(input_len))
					vterm.vterm_keyboard_key(terminal.vt, .ENTER, .NONE)
					input_len = 0
				}
			case .TEXT_INPUT:
				text_bytes := string(event.text.text)
				for i in 0 ..< len(text_bytes) {
					if input_len < len(input_buffer) {
						input_buffer[input_len] = text_bytes[i]
						input_len += 1

						// FIXME: For now just send byte per byte as its the most simple (but very inefficient).
						vterm.vterm_keyboard_unichar(terminal.vt, u32(text_bytes[i]), .NONE)
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

			ptr: [10]u8 = {'T', 'E', 'S', 'T', '\r', '\n', 0, 0, 0, 0}
			write_len := c.size_t(6)

			// ptr := &read_buf[0]
			// write_len := c.size_t(bytes_read)
			// vterm.vterm_input_write(terminal.vt, ptr, write_len)

			vterm.vterm_input_write(terminal.vt, &ptr[0], write_len)
			// output = strings.clone(string(read_buf[:bytes_read])) // Copy.
			// fmt.printf("output: %s\n", output)
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

		term.render_terminal(terminal, &ctx)

		render.render_string(&ctx, "> ", 2, 4, config.accent_color)
		if input_len > 0 {
			user_str := string(input_buffer[:input_len])
			render.render_string(&ctx, user_str, 4, 4, config.fg_color)
			// vterm.vterm_input_write(terminal.vt, user_, c.size_t(input_len))
		}

		// TODO: Internal render is not loading???
		// Its only briefly visible and then gets overwriten again?
		render.render_string(&ctx, "Out: ", 2, 6, config.fg_color)
		if len(output) > 0 {
			render.render_string(&ctx, output, 6, 6, config.fg_color)
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

		render.render_spacer_bar(&ctx, f32(win_h), f32(win_w), &config, fps)

		sdl.RenderPresent(renderer)
	}
}
