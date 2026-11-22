package types

import "core:c"
import "core:c/libc"
import "core:encoding/hex"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import "core:sys/posix"

import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

// TODO: Deduplicate from render package.
FONT_SYSTEM_DEFAULT :: "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
FONT_SIZE :: 15.0
SPACER_HEIGHT :: 24.0

AnsiColors :: enum u8 {
	BLACK   = 0,
	RED     = 1,
	GREEN   = 2,
	YELLOW  = 3,
	BLUE    = 4,
	MAGENTA = 5,
	CYAN    = 6,
	WHITE   = 7,
}

// Settable from Janet.
Preferences :: struct {
	title:         cstring,
	font_size:     f32,
	font_path:     cstring,
	fg_color:      sdl.Color,
	bg_color:      sdl.Color,
	spacer_fg:     sdl.Color,
	spacer_bg:     sdl.Color,
	accent_color:  sdl.Color,
	ansi_colors:   [AnsiColors]sdl.Color,
	spacer_height: f32,
}

// Parser a color code like #2E3440 into a fcolor.
ccode_to_fcolor :: proc(ccode: string) -> sdl.FColor {
	assert(len(ccode) == 7, "Color code must be 7 long (#RRGGBB hexstring)!")
	assert(ccode[0] == '#', "Color code must start with #!")

	bytes, ok := hex.decode(transmute([]u8)ccode[1:])
	if !ok {
		fmt.eprintf("Invalid hex string \"%s\"\n", ccode)
		os.exit(1)
	}

	fcolor := sdl.FColor {
		(f32(bytes[0]) / 255.0),
		(f32(bytes[1]) / 255.0),
		(f32(bytes[2]) / 255.0),
		1.0,
	}

	return fcolor
}

ccode_to_color :: proc(ccode: string) -> sdl.Color {
	assert(len(ccode) == 7, "Color code must be 7 long (#RRGGBB hexstring)!")
	assert(ccode[0] == '#', "Color code must start with #!")

	bytes, ok := hex.decode(transmute([]u8)ccode[1:])
	if !ok {
		fmt.eprintf("Invalid hex string \"%s\"\n", ccode)
		os.exit(1)
	}
	defer delete(bytes)

	color := sdl.Color{bytes[0], bytes[1], bytes[2], 255}

	return color
}

default_preferences :: proc() -> ^Preferences {
	prefs := new(Preferences)

	prefs.title = "ModTTY - Default"
	prefs.font_size = FONT_SIZE
	prefs.font_path = FONT_SYSTEM_DEFAULT

	prefs.fg_color = ccode_to_color("#EBDBB2")
	prefs.bg_color = ccode_to_color("#32302F")

	prefs.spacer_fg = ccode_to_color("#A89984")
	prefs.spacer_bg = ccode_to_color("#3C3836")

	prefs.accent_color = ccode_to_color("#83A598")

	prefs.ansi_colors[.BLACK] = ccode_to_color("#282828")
	prefs.ansi_colors[.RED] = ccode_to_color("#CC241D")
	prefs.ansi_colors[.GREEN] = ccode_to_color("#98971A")
	prefs.ansi_colors[.YELLOW] = ccode_to_color("#D79921")
	prefs.ansi_colors[.BLUE] = ccode_to_color("#458588")
	prefs.ansi_colors[.MAGENTA] = ccode_to_color("#B16286")
	prefs.ansi_colors[.CYAN] = ccode_to_color("#689D6A")
	prefs.ansi_colors[.WHITE] = ccode_to_color("#A89984")

	prefs.spacer_height = SPACER_HEIGHT

	return prefs
}
