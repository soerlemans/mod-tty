package modeline

import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:log"
import "core:os"
import "core:slice"
import "core:strings"
import "core:sys/posix"

import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

import j "../../ffi/janet"
import r "../../render"
import t "../../types"

Modeline :: struct {
	callbacks: [dynamic]^j.JanetFunction,
}

modeline_init :: proc() -> ^Modeline {
	modeline := new(Modeline)
	modeline.callbacks = make([dynamic]^j.JanetFunction, 0, 16)

	return modeline
}

invoke_modeline_cb :: proc(fn: ^j.JanetFunction, env: ^j.JanetTable, last_exit: i32) -> string {
	j_exit := j.janet_wrap_integer(last_exit)
	args := [1]j.Janet{j_exit}

	fiber := j.janet_fiber(fn, 64, 1, &args[0])
	if fiber == nil {
		log.errorf("Failed to allocate Janet fiber for modeline callback!")
		return ""
	}
	fiber.env = env

	result: j.Janet
	sig := j.janet_continue(fiber, j.janet_wrap_nil(), &result)
	if sig != .JANET_SIGNAL_OK {
		log.errorf("Modeline callback signaled error (%v): %v!", sig, result)
		return ""
	}

	if j.janet_checktype(result, .JANET_STRING) != 0 {
		raw_str := string(j.janet_unwrap_string(result))
		return strings.clone(raw_str, context.temp_allocator)
	} else {
		log.errorf("Unsupported return type for modeline callback: %v!", result)
	}

	return ""
}

render_modeline :: proc(
	ctx: ^r.RenderContext,
		win_h, win_w: f32,
		env: ^j.JanetTable,
	modeline: ^Modeline,
	prefs: ^t.Preferences,
) {
	// Diagnostic spacer bar.
	spacer_rect := sdl.FRect{0, f32(win_h) - prefs.spacer_height, f32(win_w), prefs.spacer_height}
	sdl.SetRenderDrawColor(
		ctx.renderer,
		prefs.spacer_bg.r,
		prefs.spacer_bg.g,
		prefs.spacer_bg.b,
		prefs.spacer_bg.a,
	)
	sdl.RenderFillRect(ctx.renderer, &spacer_rect)

	y := f32(win_h - 18) / f32(r.font_h)

	b, err := strings.builder_make()
	if err != nil {
		// TODO:.....
	}
	defer strings.builder_destroy(&b)

	sep := string("")
	for cb in modeline.callbacks {
		str := invoke_modeline_cb(cb, env, 0)

		strings.write_string(&b, sep)
		strings.write_string(&b, str)

		sep = string(" |")
	}


	ml_text := strings.to_string(b)
	r.render_string(ctx, ml_text, 1, y, prefs.spacer_fg)
}

modeline_free :: proc(modeline: ^Modeline) {
	if modeline != nil {
		delete(modeline.callbacks)
	}
}
