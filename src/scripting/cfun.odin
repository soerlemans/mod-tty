package scripting

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"

import j "../ffi/janet"

import t "../types"

@(private)
g_modeline_cbs: ^[dynamic]^j.JanetFunction

// Obtain preferences pointer from dynamic binding.
jenv_obtain_preferences :: proc() -> ^t.Preferences {
	val := j.janet_dyn("preferences")

	if j.janet_checktype(val, .JANET_POINTER) == 0 {
		typ := j.janet_type(val)
		fmt.eprintf("Janet value type: %v\n", typ)
		j.janet_panic("missing :preferences pointer in Janet dynamic bindings!")
	}
	return (^t.Preferences)(j.janet_unwrap_pointer(val))
}


jenv_insert_modeline_callback :: proc() -> ^t.Preferences {
	val := j.janet_dyn("preferences")

	if j.janet_checktype(val, .JANET_POINTER) == 0 {
		typ := j.janet_type(val)
		fmt.eprintf("Janet value type: %v\n", typ)
		j.janet_panic("missing :preferences pointer in Janet dynamic bindings!")
	}
	return (^t.Preferences)(j.janet_unwrap_pointer(val))
}

// Odin function binding (set-font-size <size>).
cfun_set_font_size :: proc "c" (argc: i32, argv: [^]j.Janet) -> j.Janet {
	context = g_ctx
	j.janet_fixarity(argc, 1)

	size := j.janet_unwrap_number(argv[0])
	if size < 3.0 || size > 96.0 {
		j.janet_panicf("Font size out of range: %g", size)
	}

	prefs := jenv_obtain_preferences()
	prefs.font_size = f32(size)
	log.debug("Config set font_size =", prefs.font_size)

	return j.janet_wrap_nil()
}


// Odin function binding (register-modeline-cb <priority> <func>).
// Register a modeline callback.
cfun_register_modeline_cb :: proc "c" (argc: i32, argv: [^]j.Janet) -> j.Janet {
	context = g_ctx
	j.janet_fixarity(argc, 1)

	func := j.janet_unwrap_function(argv[0])

	return j.janet_wrap_nil()
}

// Odin function binding (set-modeline-height <size>).
// TODO: modeline should have a minimum heigh larger then the font load size.
// TODO: Rename to modeline.
cfun_set_modeline_height :: proc "c" (argc: i32, argv: [^]j.Janet) -> j.Janet {
	context = g_ctx
	j.janet_fixarity(argc, 1)

	size := j.janet_unwrap_integer(argv[0])

	prefs := jenv_obtain_preferences()
	prefs.spacer_height = f32(size) // TODO: Rename spacer to hyper_buffer_height.
	log.debug("Config set font_size =", prefs.font_size)

	return j.janet_wrap_nil()
}

// Register native j.Janet functions.
register_cfuns :: proc(env: ^j.JanetTable) {
	fn_val := j.janet_wrap_cfunction(cfun_set_font_size)
	j.janet_def(env, "set-font-size", fn_val, "(set-font-size n)\n\nSet terminal font size.")

	fn_val = j.janet_wrap_cfunction(cfun_set_modeline_height)
	j.janet_def(
		env,
		"set-modeline-height",
		fn_val,
		"(set-modeline-height n)\n\nSet height of the hyper buffer.",
	)

	fn_val = j.janet_wrap_cfunction(cfun_register_modeline_cb)
	j.janet_def(
		env,
		"set-modeline-cb",
		fn_val,
		"(set-modeline-cb n)\n\nRegister a modeline callback.",
	)
}
