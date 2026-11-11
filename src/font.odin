package main

import "core:os"
import "core:math"
import "core:fmt"

import rl "vendor:raylib"
import sdl3 "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

// Debian system default
FONT_W :: 8
FONT_H :: 16

font_w: i32 = -1
font_h: i32 = -1

FONT_SYSTEM_DEFAULT :: "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
FONT_SIZE :: 18

get_mono_cell_size :: proc(font: ^ttf.Font) -> (cell_w: f32, cell_h: f32) {
    advance: i32
    // Query the advance width of 'M' (codepoint 77).
    if ttf.GetGlyphMetrics(font, u32('M'), nil, nil, nil, nil, &advance) {
        cell_w = f32(advance)
    }

    // Get the recommended vertical line spacing for rows.
    cell_h = f32(ttf.GetFontLineSkip(font))
    return cell_w, cell_h
}

// TODO: For now always assume system font.
load_font :: proc() -> ^ttf.Font {
		font := ttf.OpenFont(FONT_SYSTEM_DEFAULT, FONT_SIZE);
		if font == nil {
				sdl3.Log("Could not load font: %s (%s)", FONT_SYSTEM_DEFAULT, sdl3.GetError());
				os.exit(1)
		}

		glyph_w, glyph_h := get_mono_cell_size(font)
		font_w = i32(math.ceil_f32(glyph_w))
		font_h = i32(math.ceil_f32(glyph_h))

		fmt.printf("Cell dimensions %dx%d\n", font_w, font_h);

		return font
}

