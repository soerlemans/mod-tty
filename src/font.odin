package main

import "core:os"

import rl "vendor:raylib"
import sdl3 "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

// Debian system default
FONT_SYSTEM_DEFAULT :: "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
FONT_SIZE :: 18

load_sys_font :: proc() -> ^ttf.Font {
		font := ttf.OpenFont(FONT_SYSTEM_DEFAULT, FONT_SIZE);
		if font == nil {
				sdl3.Log("Kon font niet laden: %s", sdl3.GetError());
				os.exit(1)
		}

		return font
}
