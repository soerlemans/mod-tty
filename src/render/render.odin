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

render_string :: proc(ctx: ^RenderContext, text: string, col, row: f32, color: sdl.Color) {
	x := col * f32(font_w)
	y := row * f32(font_h)

	render_text_string(ctx, text, x, y, color)
}
