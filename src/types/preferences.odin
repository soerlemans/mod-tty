package types

import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import "core:sys/posix"

import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

// TODO: Deduplicate from render package.
FONT_SYSTEM_DEFAULT :: "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
FONT_SIZE :: 18

// Settable from Janet.
Preferences :: struct {
	title:         cstring,
	font_size:     int,
	bg_color:      sdl.FColor,
	fg_color:      sdl.FColor,
	spacer_color:  sdl.FColor,
	accent_color:  sdl.FColor,
	spacer_height: f32,
}

default_preferences :: proc() -> ^Preferences {
		prefs := new(Preferences)

		prefs.title         = "ModTTY - Default"
		prefs.font_size     = 18
    prefs.bg_color      = sdl.FColor{18.0 / 255.0, 18.0 / 255.0, 24.0 / 255.0, 1.0}
    prefs.fg_color      = sdl.FColor{220.0 / 255.0, 220.0 / 255.0, 204.0 / 255.0, 1.0}
    prefs.accent_color  = sdl.FColor{100.0 / 255.0, 200.0 / 255.0, 255.0 / 255.0, 1.0}
    prefs.spacer_color  = sdl.FColor{40.0 / 255.0, 40.0 / 255.0, 55.0 / 255.0, 1.0}
    prefs.spacer_height = 24.0

		return prefs
}
