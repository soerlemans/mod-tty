package vterm

import "core:c"

when ODIN_OS == .Linux || ODIN_OS == .Darwin {
		foreign import libvterm {
				"../../deps/build/libjanet.a"
				"system:vterm"
		}
} else when ODIN_OS == .Windows {
		foreign import libvterm {
				"vterm.lib"
		}
}

VTermOutputCallback :: #type proc "c" (s: [^]u8, len: c.size_t, user: rawptr)

VTERM_MAX_CHARS_PER_CELL :: 6

VTermProp :: enum {
	/* NONE = 0 */
	CURSORVISIBLE = 1, // bool.
	CURSORBLINK, // bool.
	ALTSCREEN, // bool.
	TITLE, // string.
	ICONNAME, // string.
	REVERSE, // bool.
	CURSORSHAPE, // number.
	MOUSE, // number.
	FOCUSREPORT, // bool.
	N_PROPS, // Prop size.
}

VTermValueType :: enum {
	/* NONE = 0 */
	BOOL = 1,
	INT,
	STRING,
	COLOR,
	N_VALUETYPES,
}

VTermModifier :: enum c.int {
	NONE  = 0x00,
	SHIFT = 0x01,
	ALT   = 0x02,
	CTRL  = 0x04,
}

VTermKey :: enum c.int {
	NONE = 0,
	ENTER,
	TAB,
	BACKSPACE,
	ESCAPE,
	UP,
	DOWN,
	LEFT,
	RIGHT,
	INS,
	DEL,
	HOME,
	END,
	PAGEUP,
	PAGEDOWN,
	FUNCTION_0 = 256, // F1 is FUNCTION_0 + 1, F2 is FUNCTION_0 + 2, etc.
}

VTermScreenCellAttrs :: bit_field i32 {
	bold:      i32 | 1,
	underline: i32 | 2,
	italic:    i32 | 1,
	blink:     i32 | 1,
	reverse:   i32 | 1,
	conceal:   i32 | 1,
	strike:    i32 | 1,
	font:      i32 | 4, // 0 to 9.
	dwl:       i32 | 1, // On a DECDWL or DECDHL line.
	dhl:       i32 | 2, // On a DECDHL line (1=top 2=bottom).
	small:     i32 | 1,
	baseline:  i32 | 2,
}


VTermStringFragmentFlags :: bit_field c.size_t {
	len:     c.size_t | 30,
	initial: bool     | 1,
	final:   bool     | 1,
}

VTermStringFragment :: struct {
	str:         cstring,
	using flags: VTermStringFragmentFlags,
}

VTermValue :: struct #raw_union {
	boolean: c.int,
	number:  c.int,
	string:  VTermStringFragment,
	color:   VTermColor,
}

// Opaque C handles
VTerm :: struct {}
VTermScreen :: struct {}
VTermState :: struct {}

VTermPos :: struct {
	row: c.int,
	col: c.int,
}

VTermRect :: struct {
	start_row: c.int,
	end_row:   c.int,
	start_col: c.int,
	end_col:   c.int,
}

VTermColor :: struct #raw_union {
	type:    u8,
	rgb:     struct {
		type:  u8,
		red:   u8,
		green: u8,
		blue:  u8,
	},
	indexed: struct {
		type: u8,
		idx:  u8,
	},
}

VTermScreenCell :: struct {
	chars: [VTERM_MAX_CHARS_PER_CELL]u32,
	width: u8,
	attrs: VTermScreenCellAttrs,
	fg:    VTermColor,
	bg:    VTermColor,
}

// Screen callbacks structure (must match vterm.h layout)
VTermScreenCallbacks :: struct {
	damage:      proc "c" (rect: VTermRect, user: rawptr) -> c.int,
	moverect:    proc "c" (dest: VTermRect, src: VTermRect, user: rawptr) -> c.int,
	movecursor:  proc "c" (pos: VTermPos, oldpos: VTermPos, visible: c.int, user: rawptr) -> c.int,
	settermprop: proc "c" (prop: VTermProp, val: ^VTermValue, user: rawptr) -> c.int,
	bell:        proc "c" (user: rawptr) -> c.int,
	resize:      proc "c" (rows: c.int, cols: c.int, user: rawptr) -> c.int,
	sb_pushline: proc "c" (cols: c.int, cells: [^]VTermScreenCell, user: rawptr) -> c.int,
	sb_popline:  proc "c" (cols: c.int, cells: [^]VTermScreenCell, user: rawptr) -> c.int,
	sb_clear:    proc "c" (user: rawptr) -> c.int,
}

@(default_calling_convention = "c")
foreign libvterm {
	// Lifecycle
	vterm_new :: proc(rows: c.int, cols: c.int) -> ^VTerm ---
	vterm_free :: proc(vt: ^VTerm) ---
	vterm_set_size :: proc(vt: ^VTerm, rows: c.int, cols: c.int) ---
	vterm_set_utf8 :: proc(vt: ^VTerm, is_utf8: c.int) ---

	// Input / Output
	// vterm_input_write :: proc(vt: ^VTerm, bytes: [^]u8, len: c.size_t) -> c.size_t ---
	vterm_input_write :: proc(vt: ^VTerm, bytes: rawptr, len: c.size_t) -> c.size_t ---
	vterm_output_read :: proc(vt: ^VTerm, buffer: [^]u8, len: c.size_t) -> c.size_t ---
	vterm_output_set_callback :: proc(vt: ^VTerm, func: VTermOutputCallback, user: rawptr) ---


	// Screen layer
	vterm_obtain_screen :: proc(vt: ^VTerm) -> ^VTermScreen ---
	vterm_screen_set_callbacks :: proc(screen: ^VTermScreen, callbacks: ^VTermScreenCallbacks, user: rawptr) ---
	vterm_screen_reset :: proc(screen: ^VTermScreen, hard: c.int) ---
	vterm_screen_flush_damage :: proc(screen: ^VTermScreen) ---
	vterm_screen_get_cell :: proc(screen: ^VTermScreen, pos: VTermPos, cell: ^VTermScreenCell) -> c.int ---
	vterm_screen_convert_color_to_rgb :: proc(screen: ^VTermScreen, col: ^VTermColor) ---

	// Keyboard layer
	vterm_keyboard_unichar :: proc(vt: ^VTerm, c: u32, mod: VTermModifier) ---
	vterm_keyboard_key :: proc(vt: ^VTerm, key: VTermKey, mod: VTermModifier) ---
	vterm_keyboard_start_paste :: proc(vt: ^VTerm) ---
	vterm_keyboard_end_paste :: proc(vt: ^VTerm) ---
}
