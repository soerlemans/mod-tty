package render

import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/posix"

import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

import t "../types"

RenderContext :: struct {
	renderer: ^sdl.Renderer,
	font:     ^ttf.Font,
}

render_text_string :: proc(ctx: ^RenderContext, text: string, x, y: f32, color: sdl.Color) {
	c_text := strings.clone_to_cstring(text, context.temp_allocator)

	surface := ttf.RenderText_Blended(ctx.font, (^u8)(c_text), 0, color)
	if surface == nil do return
	defer sdl.DestroySurface(surface)

	texture := sdl.CreateTextureFromSurface(ctx.renderer, surface)
	if texture == nil do return
	defer sdl.DestroyTexture(texture)

	dst_rect := sdl.FRect {
		x = x,
		y = y,
		w = f32(surface.w),
		h = f32(surface.h),
	}

	sdl.RenderTexture(ctx.renderer, texture, nil, &dst_rect)
}

render_string :: proc(ctx: ^RenderContext, text: string, col, row: f32, color: sdl.FColor) {
	byte_color: sdl.Color
	byte_color.r = u8(color.r * 255)
	byte_color.g = u8(color.g * 255)
	byte_color.b = u8(color.b * 255)
	byte_color.a = u8(color.a * 255)


	x := col * f32(font_w)
	y := row * f32(font_h)

	render_text_string(ctx, text, x, y, byte_color)
}

render_spacer_bar :: proc(ctx: ^RenderContext, win_h, win_w: f32, pref: ^t.Preferences, fps: f32) {
	// Diagnostic spacer bar.
	spacer_rect := sdl.FRect{0, f32(win_h) - pref.spacer_height, f32(win_w), pref.spacer_height}
	sdl.SetRenderDrawColorFloat(
		ctx.renderer,
		pref.spacer_color.r,
		pref.spacer_color.g,
		pref.spacer_color.b,
		1.0,
	)
	sdl.RenderFillRect(ctx.renderer, &spacer_rect)

	y := f32(win_h - 18) / f32(font_h)
	diag_text := fmt.tprintf(
		"FPS: %.1f | Spacer: %.0fpix | Status: Active",
		fps,
		pref.spacer_height,
	)
	render_string(ctx, diag_text, 1, y, pref.accent_color)
}
