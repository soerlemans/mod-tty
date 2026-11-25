package main

import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import "core:sys/posix"

import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

import j "ffi/janet"
import u "ffi/sys_util"
import vterm "ffi/vterm"
import scr "scripting"

import render "render"
import tty "tty"
import ml "tty/modeline"
import t "types"

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
	log_level: log.Level = .Debug when ODIN_DEBUG else .Info
	context.logger = log.create_console_logger(log_level)
	defer log.destroy_console_logger(context.logger)

	log.debug("DEBUG logging enabled!")

	// Set preferences to defaults.
	prefs := t.default_preferences()
	defer free(prefs)

	// Initialize modeline.
	modeline := ml.modeline_init()
	defer ml.modeline_free(modeline)

	// Initialize scripting backend.
	scr.init_scripting(prefs, modeline)
	defer scr.deinit_scripting()

	// For now we pick 800x600 as default size.
	win_w := i32(800)
	win_h := i32(600)
	log.debugf("WinDim: %dx%d", win_w, win_h)

	// Libvterm setup
	cols, rows: i32 = 80, 24 // Defaults.
	terminal, state := tty.terminal_init(rows, cols)
	if state != .OK {
		fmt.println("Failed to init Terminal!")
		return
	}
	defer tty.terminal_free(terminal)

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
	font := render.load_font(prefs)
	defer ttf.CloseFont(font)

	window := sdl.CreateWindow(prefs.title, win_w, win_h, {.RESIZABLE})
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
	for running := true; running; {
		update_fps(&fps_ctx)

		// Poll if there is new input from PTY.
		if tty.poll_terminal(terminal) != .OK {
			fmt.println("Polling error")
			break
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
				tty.resize_terminal(
					terminal,
					f32(win_w),
					f32(win_h),
					f32(render.font_w),
					f32(render.font_h),
					prefs,
				)
				terminal.dirty = true
			}
		}

		sdl.SetRenderDrawColor(
			renderer,
			prefs.bg_color.r,
			prefs.bg_color.g,
			prefs.bg_color.b,
			prefs.bg_color.a,
		)
		sdl.RenderClear(renderer)

		tty.render_terminal(terminal, &ctx, prefs)
		render.render_spacer_bar(&ctx, f32(win_h), f32(win_w), prefs, fps_ctx.fps)

		sdl.RenderPresent(renderer)
	}
}
