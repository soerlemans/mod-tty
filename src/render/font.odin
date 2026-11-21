package render

import "core:fmt"
import "core:log"
import "core:math"
import "core:os"

import rl "vendor:raylib"
import sdl3 "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

import t "../types"

// Debian system default
FONT_W :: 8
FONT_H :: 16

font_w: i32 = -1
font_h: i32 = -1

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
load_font :: proc(prefs: ^t.Preferences) -> ^ttf.Font {
	font := ttf.OpenFont(prefs.font_path, f32(prefs.font_size))
	if font == nil {
		log.error("Could not load font: %s (%s)", prefs.font_path, sdl3.GetError())
		os.exit(1)
	}

	glyph_w, glyph_h := get_mono_cell_size(font)
	font_w = i32(math.ceil_f32(glyph_w))
	font_h = i32(math.ceil_f32(glyph_h))

	log.infof("Font \"%v\" loaded with size %d.", prefs.font_path, prefs.font_size)
	log.infof("Cell dimensions %dx%d", font_w, font_h)

	return font
}
