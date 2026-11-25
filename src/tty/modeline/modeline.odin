package modeline

import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:log"
import "core:os"
import "core:slice"
import "core:strings"
import "core:sys/posix"

import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

import j "../../ffi/janet"

Modeline :: struct {
	callbacks: [dynamic]^j.JanetFunction,
}

modeline_init :: proc() -> ^Modeline {
	modeline := new(Modeline)
	modeline.callbacks = make([dynamic]^j.JanetFunction, 0, 16)

	return modeline
}

modeline_free :: proc(modeline: ^Modeline) {
	if modeline != nil {
		delete(modeline.callbacks)
	}
}
