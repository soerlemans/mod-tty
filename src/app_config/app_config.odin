package app_config

import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/posix"

import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

import j "../janet"

// FIXME: Temporary we need more sophisticated configuration.
AppConfig :: struct {
	title:         cstring,
	bg_color:      sdl.FColor,
	fg_color:      sdl.FColor,
	spacer_color:  sdl.FColor,
	accent_color:  sdl.FColor,
	spacer_height: f32,
}

load_app_config :: proc(env: ^j.JanetTable, filename: string) -> AppConfig {
	// 1. Safe default config fallback
	cfg := AppConfig {
		title         = "ModTTY - Default",
		bg_color      = sdl.FColor{18.0 / 255.0, 18.0 / 255.0, 24.0 / 255.0, 1.0},
		fg_color      = sdl.FColor{220.0 / 255.0, 220.0 / 255.0, 204.0 / 255.0, 1.0},
		accent_color  = sdl.FColor{100.0 / 255.0, 200.0 / 255.0, 255.0 / 255.0, 1.0},
		spacer_color  = sdl.FColor{40.0 / 255.0, 40.0 / 255.0, 55.0 / 255.0, 1.0},
		spacer_height = 24.0,
	}

	file_data, err := os.read_entire_file(filename, context.allocator)
	if err != nil {
		fmt.eprintln("%s not found. Using default config.", filename)
		return cfg
	}
	defer delete(file_data)

	c_source := strings.clone_to_cstring(string(file_data), context.temp_allocator)

	eval_result: j.Janet
	// janet_dostring returns 0 on success.
	if j.janet_dostring(env, c_source, "filename", &eval_result) == 0 {
		type_kind := j.janet_type(eval_result)
		if type_kind == j.JanetType.JANET_TABLE {
			config_table := j.janet_unwrap_table(eval_result)
			if config_table != nil {
				spacer_val := j.janet_table_get(config_table, j.janet_cstringv("spacer-height"))
				// Ensure it's a valid number before unwrapping integer
				if spacer_val != 0 {
					cfg.spacer_height = f32(j.janet_unwrap_integer(spacer_val))
					fmt.eprintln("Spacer heigh: ", cfg.spacer_height)
				}
			}
		} else {
			fmt.eprintln("Warning: Unhandled janet type", type_kind)
		}
	} else {
		fmt.eprintln("Error evaluating init.janet script.")
	}

	return cfg
}
