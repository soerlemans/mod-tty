package terminal

import "base:runtime"
import "core:c"
import "core:slice"
import "core:sys/posix"
import "core:fmt"

import vterm "../sys_vterm"

TerminalStatus :: enum {
		OK,
		FAIL
}

// Scrollback line stored in your own ring buffer
ScrollbackLine :: struct {
	cells: []vterm.VTermScreenCell,
}

Terminal :: struct {
	vt:             ^vterm.VTerm,
	vt_screen:      ^vterm.VTermScreen,
	pty_fd:         posix.FD,
	rows:           c.int,
	cols:           c.int,

	// Rendering & UI state updated by callbacks
	dirty:          bool,
	cursor_pos:     vterm.VTermPos,
	cursor_visible: bool,
	title:          string,
	bell_rung:      bool,

	// Bounded scrollback history (e.g., ring buffer of up to 10,000 lines)
	scrollback:     [dynamic]ScrollbackLine,
	max_scrollback: int,
}

// vterm.VTerm -> PTY (Required): Sends keystrokes and terminal query responses back to shell.
on_vterm_output :: proc "c" (s: [^]u8, len: c.size_t, user: rawptr) {
	context = runtime.default_context()

	fmt.println("on_vterm_output: ", s[:len]);
	term := cast(^Terminal)user
	if len > 0 {
			fmt.println("on_vterm_output: ", s[:len]);
			posix.write(posix.FD(term.pty_fd), s, uint(len))
	}
}

// Damage (Required): Tells you which rectangle of cells changed and needs redrawing.
on_damage :: proc "c" (rect: vterm.VTermRect, user: rawptr) -> c.int {
	term := cast(^Terminal)user
	// Simple approach: mark whole vt_screen dirty.
	// Advanced approach: union `rect` into a dirty bounding box.
	term.dirty = true
	return 1
}

// MoveRect (Optional): Optimization hint when a region scrolls (e.g. lines shift up).
on_moverect :: proc "c" (dest: vterm.VTermRect, src: vterm.VTermRect, user: rawptr) -> c.int {
	term := cast(^Terminal)user
	// Most GPU terminals just mark dirty and redraw the grid from vterm.VTermScreen,
	// because redrawing 80x24 instanced quads is faster than copying VRAM rects.
	term.dirty = true
	return 1
}

// MoveCursor (Required for rendering cursor): Tracks cursor coordinates & visibility.
on_movecursor :: proc "c" (pos: vterm.VTermPos, oldpos: vterm.VTermPos, visible: c.int, user: rawptr) -> c.int {
	term := cast(^Terminal)user
	term.cursor_pos     = pos
	term.cursor_visible = (visible != 0)
	term.dirty          = true
	return 1
}

// SetTermProp (Recommended): Handles window title (OSC 0/2), cursor shape, altscreen, etc.
on_settermprop :: proc "c" (prop: vterm.VTermProp, val: ^vterm.VTermValue, user: rawptr) -> c.int {
	term := cast(^Terminal)user
	#partial switch prop {
	case .TITLE:
		// val.str is a VTermStringFragment { str: [^]u8, len: size_t, initial: bool, final: bool }
		// Copy fragments into term.title to update your OS window title bar
	case .CURSORSHAPE:
		// val.number: 1 = Block, 2 = Underline, 3 = Bar
	case .CURSORBLINK:
		// val.boolean: toggle cursor blink timer
	case .ALTSCREEN:
		// val.boolean: true when entering vim/htop, false when exiting
	case .MOUSE:
		// val.number: mouse reporting mode requested by TUI app
	}
	return 1
}

// Bell (Optional): Triggered on '\a' (ASCII 0x07).
on_bell :: proc "c" (user: rawptr) -> c.int {
	term := cast(^Terminal)user
	term.bell_rung = true // Trigger visual flash or audio chime
	return 1
}

// Resize (Optional): Notifies you if an escape sequence (CSI 8 ; rows ; cols t) resized vterm.VTerm.
on_resize :: proc "c" (rows: c.int, cols: c.int, user: rawptr) -> c.int {
	term := cast(^Terminal)user
	term.rows = rows
	term.cols = cols
	term.dirty = true
	return 1
}

// Scrollback Push (Required for scrollback): Saves a line that scrolled off the top.
on_sb_pushline :: proc "c" (cols: c.int, cells: [^]vterm.VTermScreenCell, user: rawptr) -> c.int {
	term := cast(^Terminal)user

	// IMPORTANT: `cells` is only valid during this callback! You MUST copy it.
	// Also note: "c" calling convention has no Odin context, so establish default_context().
	context = runtime.default_context()

	line_copy := slice.clone(cells[:cols])
	if len(term.scrollback) >= term.max_scrollback {
		delete(term.scrollback[0].cells)
		ordered_remove(&term.scrollback, 0) // In production, use a ring buffer instead of shifting
	}
	append(&term.scrollback, ScrollbackLine{cells = line_copy})
	return 1
}

// Scrollback Pop (Required for scrollback): Restores a line when the window grows taller
on_sb_popline :: proc "c" (cols: c.int, cells: [^]vterm.VTermScreenCell, user: rawptr) -> c.int {
	term := cast(^Terminal)user
	if len(term.scrollback) == 0 {
		return 0 // Tell libvterm there is no history left to pop
	}

	context = runtime.default_context()
	last := pop(&term.scrollback)
	defer delete(last.cells)

	// Copy saved cells back into libvterm's buffer, padding or truncating to `cols`
	copy_count := min(int(cols), len(last.cells))
	copy(cells[:copy_count], last.cells[:copy_count])
	for i in copy_count..<int(cols) {
		cells[i] = {} // Blank-fill remaining columns if terminal got wider
	}
	return 1 // Tell libvterm a line was restored
}

// Scrollback Clear (Optional): Triggered by `clear` / `CSI 3 J`.
on_sb_clear :: proc "c" (user: rawptr) -> c.int {
	term := cast(^Terminal)user
	context = runtime.default_context()
	for line in term.scrollback {
		delete(line.cells)
	}
	clear(&term.scrollback)
	return 1
}

// We never change the callbacks during runtime so its effectively a constant.
VTERM_CALLBACKS := vterm.VTermScreenCallbacks{
		damage = on_damage,
		moverect = on_moverect,
		movecursor = on_movecursor,
		settermprop = on_settermprop,
		bell = on_bell,
		resize = on_resize,
		sb_pushline = on_sb_pushline,
		sb_popline = on_sb_popline,
		sb_clear = on_sb_clear
}

init :: proc(pty_fd: posix.FD, rows, cols: i32) -> (^Terminal, TerminalStatus) {
		term := new(Terminal)

		// Init members.
		term.pty_fd = pty_fd
		term.rows = rows
		term.cols = cols

		term.vt = vterm.vterm_new(rows, cols)
		if term.vt == nil do return nil, .FAIL

		vterm.vterm_set_utf8(term.vt, 1)
		term.vt_screen = vterm.vterm_obtain_screen(term.vt)

		vterm.vterm_output_set_callback(term.vt, on_vterm_output, term)
		vterm.vterm_screen_set_callbacks(term.vt_screen, &VTERM_CALLBACKS, term)

		return term, .OK
}

free::proc(term: ^Terminal) {
		vterm.vterm_free(term.vt)

		free(term)
}
