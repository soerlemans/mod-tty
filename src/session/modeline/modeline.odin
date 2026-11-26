package modeline

import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:log"
import "core:os"
import "core:slice"
import "core:sort"
import "core:strings"
import "core:sys/posix"

import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

import j "../../ffi/janet"
import r "../../render"
import t "../../types"

PROPS_DEFAULT_PRIORITY :: 200
PROPS_PRIORITY :: "priority"
PROPS_VISIBLE :: "visible"
PROPS_INTERVAL_MS :: "visible"

// TODO: Decide if this is needed.
ModelineCellKind :: enum {
	STATUS,
	ANIMATION,
}

ModelineCell :: struct {
	callback:   ^j.JanetFunction, // Callback returning string.
	props:      ^j.JanetTable, // Property table to access and modify from callback.
}

Modeline :: struct {
	callbacks: [dynamic]ModelineCell,
}

cell_props_priority :: proc(cell: ^ModelineCell) -> i32 {
	key := j.janet_keyword(PROPS_PRIORITY)

	val := j.janet_table_get(cell.props, key)
	if !j.janet_istype(val, .JANET_NUMBER) {
			return PROPS_DEFAULT_PRIORITY
	}

	num := i32(j.janet_unwrap_integer(val))
	if num < 0 {
			num = 0
	}
	return num
}

cell_props_visibility :: proc(cell: ^ModelineCell) -> bool {
	key := j.janet_keyword(PROPS_VISIBLE)

	val := j.janet_table_get(cell.props, key)
	if j.janet_istype(val, .JANET_BOOLEAN) {
		return true
	}

	// TODO: Introduce helpers for unwrapping boilerplate.
	return j.janet_unwrap_boolean(val) != 0
}

cell_props_interval_ms :: proc(cell: ^ModelineCell) -> i32 {
	key := j.janet_keyword(PROPS_PRIORITY)

	val := j.janet_table_get(cell.props, key)
		if j.janet_istype(val, .JANET_NUMBER) {
				return PROPS_DEFAULT_PRIORITY
		}

		num := i32(j.janet_unwrap_integer(val))
		if num < 0 {
				num = 0
		}
	return num
}

modeline_init :: proc() -> ^Modeline {
	modeline := new(Modeline)
	modeline.callbacks = make([dynamic]ModelineCell, 0, 16)

	return modeline
}

invoke_modeline_cb :: proc(env: ^j.JanetTable, cell: ModelineCell, last_exit: i32) -> string {
	j_exit := j.janet_wrap_integer(last_exit)
	args := [1]j.Janet{j_exit}

	fiber := j.janet_fiber(cell.callback, 64, 1, &args[0])
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

	if j.janet_istype(result, .JANET_STRING) {
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
		log.errorf("Cant allocate strings builder.")
		return
	}
	defer strings.builder_destroy(&b)

	// Higher priority items should be on the left on the modeline.
	slice.sort_by(modeline.callbacks[:], proc(lhs, rhs: ^ModelineCell) -> bool {
		return cell_props_priority(lhs) > cell_props_priority(rhs)
	})

	sep := string("")
	for cell in modeline.callbacks {
		str := invoke_modeline_cb(env, cell, 0)
		if len(str) == 0 {
			continue
		}

		strings.write_string(&b, sep)
		strings.write_string(&b, str)

		sep = string(" | ")
	}

	ml_text := strings.to_string(b)
	r.render_string(ctx, ml_text, 1, y, prefs.spacer_fg)
}

modeline_free :: proc(modeline: ^Modeline) {
	if modeline != nil {
		delete(modeline.callbacks)
	}
}
