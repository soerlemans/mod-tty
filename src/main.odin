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
	shell := libc.getenv("SHELL")

	// Easier to debug then ZSH for now.
	// posix.setenv("PS1", "~ ", true)
	// shell = cstring("/bin/sh")
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

is_modifier_key :: proc(key: sdl.Keycode) -> bool {
	return(
		key == sdl.K_LCTRL ||
		key == sdl.K_RCTRL ||
		key == sdl.K_LSHIFT ||
		key == sdl.K_RSHIFT ||
		key == sdl.K_LALT ||
		key == sdl.K_RALT ||
		key == sdl.K_LGUI ||
		key == sdl.K_RGUI \
	)
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
				// If only a modifier was pressed just ignore.
				if is_modifier_key(event.key.key) do break

				// TODO: Move to function.
				kmod: vterm.VTermModifier = .NONE
				is_ctrl := (event.key.mod & (sdl.KMOD_LCTRL | sdl.KMOD_RCTRL)) != {}
				if is_ctrl {
					kmod |= .CTRL
				}

				is_shift := (event.key.mod & (sdl.KMOD_LSHIFT | sdl.KMOD_RSHIFT)) != {}
				if is_shift {
					kmod |= .SHIFT
				}

				is_alt := (event.key.mod & (sdl.KMOD_LALT | sdl.KMOD_RALT)) != {}
				if is_alt {
					kmod |= .ALT
				}

				switch event.key.key {
				// TODO: Clean up.
				case sdl.K_RETURN:
					vterm.vterm_keyboard_key(terminal.vt, .ENTER, kmod)

				case sdl.K_BACKSPACE:
					vterm.vterm_keyboard_key(terminal.vt, .BACKSPACE, kmod)

				case sdl.K_TAB:
					vterm.vterm_keyboard_key(terminal.vt, .TAB, kmod)

				case sdl.K_ESCAPE:
					vterm.vterm_keyboard_key(terminal.vt, .ESCAPE, kmod)

				case sdl.K_UP:
					vterm.vterm_keyboard_key(terminal.vt, .UP, kmod)

				case sdl.K_DOWN:
					vterm.vterm_keyboard_key(terminal.vt, .DOWN, kmod)

				case sdl.K_LEFT:
					vterm.vterm_keyboard_key(terminal.vt, .LEFT, kmod)

				case sdl.K_RIGHT:
					vterm.vterm_keyboard_key(terminal.vt, .RIGHT, kmod)

				case sdl.K_INSERT:
					vterm.vterm_keyboard_key(terminal.vt, .INS, kmod)

				case sdl.K_DELETE:
					vterm.vterm_keyboard_key(terminal.vt, .DEL, kmod)

				case sdl.K_HOME:
					vterm.vterm_keyboard_key(terminal.vt, .HOME, kmod)

				case sdl.K_END:
					vterm.vterm_keyboard_key(terminal.vt, .END, kmod)

				case sdl.K_PAGEUP:
					vterm.vterm_keyboard_key(terminal.vt, .PAGEUP, kmod)

				case sdl.K_PAGEDOWN:
					vterm.vterm_keyboard_key(terminal.vt, .PAGEDOWN, kmod)

				case:
					// Ignore empty modifiers and if only a shift is present.
					// As we have capitalization be handled by .TEXT_INPUT case.
					if kmod != .NONE && (kmod & (.SHIFT)) == .NONE {
						// SDL Keytypes map to ASCII table.
						vterm.vterm_keyboard_unichar(terminal.vt, u32(event.key.key), kmod)
						terminal.dirty = true
					}
				}

			case .TEXT_INPUT:
				text_ptr := event.text.text
				for r in string(text_ptr) {
					vterm.vterm_keyboard_unichar(terminal.vt, u32(r), .NONE)
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
