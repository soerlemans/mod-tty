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
import plibc "posix_libc"
import render "render"
import u "sys_util"
import vterm "sys_vterm"
import term "terminal"

FpsContext :: struct {
	fps:         f32,
	frame_count: u32,
	last_tick:   u64,
}

update_fps :: proc(ctx: ^FpsContext) {
	current_tick := sdl.GetTicks()
	ctx.frame_count += 1
	if current_tick - ctx.last_tick >= 1000 {
		ctx.fps = f32(ctx.frame_count) * 1000.0 / f32(current_tick - ctx.last_tick)
		ctx.frame_count = 0
		ctx.last_tick = current_tick
	}
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

resize_terminal :: proc(
	master_fd: posix.FD,
	terminal: ^term.Terminal,
	win_w, win_h, font_w, font_h: f32,
	config: ^ap.AppConfig,
) {
	available_h := win_h - config.spacer_height
	cols := int(win_w / font_w)
	rows := int(available_h / font_h)

	if cols < 10 {cols = 10}
	if rows < 5 {rows = 5}

	// Update libvterm grid size.
	vterm.vterm_set_size(terminal.vt, c.int(rows), c.int(cols))

	// Notify the kernel PTY of the new dimensions.
	ws := plibc.winsize {
		ws_row    = u16(rows),
		ws_col    = u16(cols),
		ws_xpixel = u16(win_w),
		ws_ypixel = u16(win_h),
	}
	plibc.ioctl(i32(master_fd), plibc.TIOCSWINSZ, &ws)
}

main :: proc() {
	cols, rows: i32 = 80, 30

	// Initialize Janet VM, and load configuration.
	j.janet_init()
	defer j.janet_deinit()

	env := j.janet_core_env(nil)
	config := ap.load_app_config(env, "init.janet")

	// For now we pick 800x600 as default size.
	win_w := i32(800)
	win_h := i32(600)
	fmt.printf("WinDim: %dx%d\n", win_w, win_h)

	// PTY setup.
	master_fd := pty_init()
	defer posix.close(master_fd)

	// Libvterm setup
	terminal, state := term.terminal_init(master_fd, rows, cols)
	if state != .OK {
		fmt.println("Failed to init Terminal!")
		return
	}
	defer term.terminal_free(terminal)

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

	// Event loop.
	fps_ctx := FpsContext{60.0, 0, sdl.GetTicks()}

	fds := [1]posix.pollfd{{fd = master_fd, events = {.IN}}}
	running := true
	input_buffer: [4096]u8
	input_len: int = 0
	for running {
		update_fps(&fps_ctx)

		read_buf: [4096]u8
		ret := posix.poll(&fds[0], 1, 16)
		if ret > 0 && .IN in fds[0].revents {
			bytes_read := posix.read(master_fd, raw_data(read_buf[:]), len(read_buf))
			if bytes_read > 0 {
				ptr := &read_buf[0]
				write_len := c.size_t(bytes_read)
				vterm.vterm_input_write(terminal.vt, ptr, write_len)
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
		} else if ret < 0 {
			err := posix.errno()
			if !(err == .EAGAIN || err == .EWOULDBLOCK) {
				libc.perror("Poll error")
				running = false
			}
		}

		event: sdl.Event
		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				running = false

			case .KEY_DOWN:
				if event.key.key == sdl.K_BACKSPACE && input_len > 0 {
					vterm.vterm_keyboard_key(terminal.vt, .ENTER, .NONE)
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

			case .WINDOW_RESIZED:
				win_w = event.window.data1
				win_h = event.window.data2

				// TODO: Update PTY and LIBVTERM.
				resize_terminal(
					master_fd,
					terminal,
					f32(win_w),
					f32(win_h),
					f32(render.font_w),
					f32(render.font_h),
					&config,
				)
				terminal.dirty = true
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

		term.render_terminal(terminal, &ctx)
		render.render_spacer_bar(&ctx, f32(win_h), f32(win_w), &config, fps_ctx.fps)

		sdl.RenderPresent(renderer)
	}
}
