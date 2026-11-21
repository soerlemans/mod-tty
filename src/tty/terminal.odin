package tty

import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:log"
import "core:os"
import "core:slice"
import "core:sys/posix"

import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

import j "../janet"
import plibc "../posix_libc"
import render "../render"
import u "../sys_util"
import vterm "../sys_vterm"
import t "../types"

READ_BUF_SIZE :: 4096

TerminalStatus :: enum {
	OK,
	FAIL,
}


PollStatus :: enum {
	OK,
	PTY_EOF,
	PTY_ERROR,
}

// Scrollback line stored in your own ring buffer
ScrollbackLine :: struct {
	cells: []vterm.VTermScreenCell,
}

Terminal :: struct {
	vt:             ^vterm.VTerm,
	vt_state:       ^vterm.VTermState,
	vt_screen:      ^vterm.VTermScreen,
	pty_fd:         posix.FD,
	read_buf:       [READ_BUF_SIZE]u8,
	poll_fds:       [1]posix.pollfd,
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

	term := cast(^Terminal)user
	if len > 0 {
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
on_movecursor :: proc "c" (
	pos: vterm.VTermPos,
	oldpos: vterm.VTermPos,
	visible: c.int,
	user: rawptr,
) -> c.int {
	term := cast(^Terminal)user
	term.cursor_pos = pos
	term.cursor_visible = (visible != 0)
	term.dirty = true
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
	for i in copy_count ..< int(cols) {
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
VTERM_CALLBACKS := vterm.VTermScreenCallbacks {
	damage      = on_damage,
	moverect    = on_moverect,
	movecursor  = on_movecursor,
	settermprop = on_settermprop,
	bell        = on_bell,
	resize      = on_resize,
	sb_pushline = on_sb_pushline,
	sb_popline  = on_sb_popline,
	sb_clear    = on_sb_clear,
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
	log.infof("TERM=%s", term)
	log.infof("SHELL=%s", shell)
	fmt.println("Welcome to Hyper term.")

	res := posix.execlp(shell, shell, nil)
	if res == -1 {
		libc.perror("execlp")
		os.exit(int(res))
	}
	os.exit(0)
}

pty_init :: proc(rows, cols: i32) -> posix.FD {
	// PTY setup.
	pty_fd: posix.FD = -1
	ws := u.winsize {
		ws_row    = u16(rows),
		ws_col    = u16(cols),
		ws_xpixel = 0,
		ws_ypixel = 0,
	}
	pid := u.forkpty(&pty_fd, nil, nil, &ws)
	if pid < 0 {
		libc.perror("Failed to open PTY")
		os.exit(0)
	}

	// Child process flow launches shell.
	if pid == 0 {
		shell_process()
	}

	// Set master PTY non-blocking so we can poll it cleanly in the UI loop
	flags := posix.fcntl(pty_fd, .GETFL, 0)

	O_NONBLOCK := transmute(c.int)posix.O_Flags{.NONBLOCK}
	posix.fcntl(pty_fd, .SETFL, flags | O_NONBLOCK, 0)

	return pty_fd
}

terminal_init :: proc(rows, cols: i32) -> (^Terminal, TerminalStatus) {
	term := new(Terminal)

	pfd := pty_init(rows, cols)
	if pfd < 0 {
		free(term)
		log.errorf("Failed to init PTY: %d", pfd)
		os.exit(1)
	}
	// Init members.
	term.pty_fd = pfd
	term.poll_fds = [1]posix.pollfd{{fd = pfd, events = {.IN}}}
	term.rows = rows
	term.cols = cols
	term.max_scrollback = 10000


	term.vt = vterm.vterm_new(rows, cols)
	if term.vt == nil do return nil, .FAIL

	vterm.vterm_set_utf8(term.vt, 1)

	// Make callbacks reregister due to UTF-8 encoding change.
	term.vt_state = vterm.vterm_obtain_state(term.vt)
	vterm.vterm_state_reset(term.vt_state, 1)

	term.vt_screen = vterm.vterm_obtain_screen(term.vt)
	vterm.vterm_screen_reset(term.vt_screen, 1)

	// Set callbacks.
	vterm.vterm_output_set_callback(term.vt, on_vterm_output, term)
	vterm.vterm_screen_set_callbacks(term.vt_screen, &VTERM_CALLBACKS, term)

	return term, .OK
}

resize_terminal :: proc(term: ^Terminal, win_w, win_h, font_w, font_h: f32, pref: ^t.Preferences) {
	available_h := win_h - pref.spacer_height
	cols := int(win_w / font_w)
	rows := int(available_h / font_h)

	if cols < 10 {cols = 10}
	if rows < 5 {rows = 5}

	// Update libvterm grid size.
	vterm.vterm_set_size(term.vt, c.int(rows), c.int(cols))

	// Notify the kernel PTY of the new dimensions.
	ws := plibc.winsize {
		ws_row    = u16(rows),
		ws_col    = u16(cols),
		ws_xpixel = u16(win_w),
		ws_ypixel = u16(win_h),
	}
	plibc.ioctl(i32(term.pty_fd), plibc.TIOCSWINSZ, &ws)
}


draw_rect :: proc(renderer: ^sdl.Renderer, x, y, w, h: f32, color: vterm.VTermColor) {
	sdl.SetRenderDrawColor(renderer, color.rgb.red, color.rgb.green, color.rgb.blue, 255)
	rect := sdl.FRect {
		x = x,
		y = y,
		w = w,
		h = h,
	}
	sdl.RenderFillRect(renderer, &rect)
}

draw_glyph :: proc(
	render_ctx: ^render.RenderContext,
	r: rune,
	px_x, px_y: f32,
	fg: vterm.VTermColor,
	cell_w, cell_h: f32,
) {
	// Skip drawing if it's an empty space or null character
	if r == 0 || r == ' ' do return

	sdl_color := sdl.Color{fg.rgb.red, fg.rgb.green, fg.rgb.blue, 255}

	// Rasterize the single rune into an SDL surface using SDL_ttf
	font := render_ctx.font
	renderer := render_ctx.renderer
	surface := ttf.RenderGlyph_Blended(font, u32(r), sdl_color)
	if surface == nil do return
	defer sdl.DestroySurface(surface)

	// Convert the surface to an SDL texture for rendering
	texture := sdl.CreateTextureFromSurface(renderer, surface)
	if texture == nil do return
	defer sdl.DestroyTexture(texture)

	dst_rect := sdl.FRect {
		x = px_x,
		y = px_y,
		w = cell_w,
		h = cell_h,
	}

	sdl.RenderTexture(renderer, texture, nil, &dst_rect)
}

draw_cursor :: proc(renderer: ^sdl.Renderer, x, y, w, h: f32) {
	// Draw a semi-transparent or solid white cursor box.
	sdl.SetRenderDrawColor(renderer, 200, 200, 200, 200)
	rect := sdl.FRect {
		x = x,
		y = y,
		w = w,
		h = h,
	}
	sdl.RenderFillRect(renderer, &rect)
}

poll_terminal :: proc(term: ^Terminal) -> PollStatus {
	WAIT_MS :: 20

	fds_ptr := &term.poll_fds[0]
	ret := posix.poll(fds_ptr, 1, WAIT_MS) // Wait for a maximum of 20ms.

	if ret > 0 && .IN in term.poll_fds[0].revents {
		raw_ptr := raw_data(term.read_buf[:])

		bytes_read := posix.read(term.pty_fd, raw_ptr, READ_BUF_SIZE)
		if bytes_read > 0 {
			write_len := c.size_t(bytes_read)
			vterm.vterm_input_write(term.vt, raw_ptr, write_len)
		} else if bytes_read == 0 {
			// EOF: child closed the PTY.
			return .PTY_EOF
		} else {
			// n == -1: check errno.
			err := posix.errno()
			if !(err == .EAGAIN || err == .EWOULDBLOCK) {
				libc.perror("Error in poll_terminal.")
				return .PTY_ERROR
			}
		}
	}

	return .OK
}

// Indexed colors are changeable by
override_indexed_color :: proc(vc: ^vterm.VTermColor, prefs: ^t.Preferences) {
	// Default background color is completely black RGB(0, 0, 0).
	// So if that is the case we override it with our preferences set background color.
	tag_idx := (vc.type & u8(vterm.VTermColorType.VTERM_COLOR_TYPE_MASK))
	if tag_idx == u8(vterm.VTermColorType.VTERM_COLOR_INDEXED) {
		if vc.indexed.idx < len(t.AnsiColors) {
			ansi_idx := t.AnsiColors(vc.indexed.idx)
			color := &prefs.ansi_colors[ansi_idx]

			// Change union from indexed color to RGB color.
			vc.rgb.type =
				(vc.type & ~u8(vterm.VTermColorType.VTERM_COLOR_TYPE_MASK)) |
				u8(vterm.VTermColorType.VTERM_COLOR_RGB)
			vc.rgb.red = color.r
			vc.rgb.green = color.g
			vc.rgb.blue = color.b
		}
	}
}

override_bg_color :: proc(vc_bg: ^vterm.VTermColor, prefs: ^t.Preferences) {
	// Default background color is completely black RGB(0, 0, 0).
	// So if that is the case we override it with our preferences set background color.
	tag_idx := (vc_bg.type & u8(vterm.VTermColorType.VTERM_COLOR_TYPE_MASK))
	if tag_idx == u8(vterm.VTermColorType.VTERM_COLOR_RGB) {
		if vc_bg.rgb.red == 0 && vc_bg.rgb.green == 0 && vc_bg.rgb.blue == 0 {
			vc_bg.rgb.red = prefs.bg_color.r
			vc_bg.rgb.green = prefs.bg_color.g
			vc_bg.rgb.blue = prefs.bg_color.b
		}
	} else {
		override_indexed_color(vc_bg, prefs)
	}
}

render_terminal :: proc(
	term: ^Terminal,
	render_ctx: ^render.RenderContext,
	prefs: ^t.Preferences,
) {
	// Only redraw if there is new data.
	// if term.dirty == false do return
	term.dirty = false

	renderer := render_ctx.renderer
	CELL_W := f32(render.font_w)
	CELL_H := f32(render.font_h)

	// 1. Draw the solid background rectangle for every cell first
	//    (so wide glyphs or antialiasing don't bleed across cell borders)
	for row in 0 ..< term.rows {
		col: i32 = 0
		for col < term.cols {
			cell: vterm.VTermScreenCell
			cell_pos := vterm.VTermPos {
				row = row,
				col = col,
			}
			vterm.vterm_screen_get_cell(term.vt_screen, cell_pos, &cell)

			// Enforce our set background color
			override_indexed_color(&cell.fg, prefs)
			override_bg_color(&cell.bg, prefs)

			// Convert indexed/default colors into concrete RGB
			vterm.vterm_screen_convert_color_to_rgb(term.vt_screen, &cell.fg)
			vterm.vterm_screen_convert_color_to_rgb(term.vt_screen, &cell.bg)

			// Handle reverse video attribute (used by selections, cursors, status bars).
			fg, bg := cell.fg, cell.bg
			if cell.attrs.reverse != 0 {
				fg, bg = bg, fg
			}

			width := i32(max(cell.width, 1))
			px_x := f32(col) * CELL_W
			px_y := f32(row) * CELL_H

			draw_rect(renderer, px_x, px_y, f32(width) * CELL_W, CELL_H, bg)

			// 2. Draw the glyph if the cell is not empty (`chars[0] == 0` means space/blank)
			if cell.chars[0] != 0 {
				draw_glyph(render_ctx, rune(cell.chars[0]), px_x, px_y, fg, CELL_W, CELL_H)
			}

			col += width
		}
	}

	if term.cursor_visible {
		cx := f32(term.cursor_pos.col) * CELL_W
		cy := f32(term.cursor_pos.row) * CELL_H
		draw_cursor(renderer, cx, cy, CELL_W, CELL_H)
	}
}

terminal_free :: proc(term: ^Terminal) {
	if term == nil do return

	if term.vt != nil {
		vterm.vterm_free(term.vt)

		term.vt = nil
		term.vt_state = nil
		term.vt_screen = nil
	}

	if term.pty_fd > -1 {
		posix.close(term.pty_fd)
	}

	free(term)
}
