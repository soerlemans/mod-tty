package tty

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

import j "../janet"
import plibc "../posix_libc"
import render "../render"
import u "../sys_util"
import vterm "../sys_vterm"
import t "../types"

Modeline :: struct {
	callbacks: [dynamic]^j.JanetFunction
}

modeline_free :: proc(modeline: ^Modeline) {
		if modeline != nil {
				delete(modeline.callbacks)
		}
}
