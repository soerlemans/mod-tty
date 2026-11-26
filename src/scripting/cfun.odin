package scripting

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"

import j "../ffi/janet"

import ml "../session/modeline"
import t "../types"

// Obtain preferences pointer from dynamic binding.
obtain_preferences :: proc() -> ^t.Preferences {
	val := j.janet_dyn("preferences")

	if j.janet_checktype(val, .JANET_POINTER) == 0 {
		typ := j.janet_type(val)
		fmt.eprintf("Janet value type: %v\n", typ)
		j.janet_panic("missing :preferences pointer in Janet dynamic bindings!")
	}
	return (^t.Preferences)(j.janet_unwrap_pointer(val))
}

obtain_modeline :: proc() -> ^ml.Modeline {
	val := j.janet_dyn("modeline-callbacks")

	if j.janet_checktype(val, .JANET_POINTER) == 0 {
		typ := j.janet_type(val)
		fmt.eprintf("Janet value type: %v\n", typ)
		j.janet_panic("missing :modeline-callbacks pointer in Janet dynamic bindings!")
	}
	return (^ml.Modeline)(j.janet_unwrap_pointer(val))
}

// Odin function binding (set-font-size <size>).
cfun_set_font_size :: proc "c" (argc: i32, argv: [^]j.Janet) -> j.Janet {
	context = g_ctx
	j.janet_fixarity(argc, 1)

	size := j.janet_unwrap_number(argv[0])
	if size < 3.0 || size > 96.0 {
		j.janet_panicf("Font size out of range: %g", size)
	}

	prefs := obtain_preferences()
	prefs.font_size = f32(size)
	log.debug("Config set font_size =", prefs.font_size)

	return j.janet_wrap_nil()
}


// Odin function binding (register-modeline-cb <func> <optional>).
// Register a modeline callback.
// TODO: Actually do something with priority.
cfun_register_modeline_cb :: proc "c" (argc: i32, argv: [^]j.Janet) -> j.Janet {
	context = g_ctx
	j.janet_arity(argc, 1, 2)

	if j.janet_checktype(argv[0], .JANET_FUNCTION) != 0 {
		j.janet_panic("First argument to register-modeline-cb must be a function.")
	}

	// Optional argument checking.
	if (argc == 2) {
		if j.janet_checktype(argv[1], .JANET_TABLE) != 0 {
			j.janet_panic(
				"Second optional argument to register-modeline-cb must be a janet table.",
			)
		}
	}

	func := j.janet_unwrap_function(argv[0])
	initial_props := j.janet_unwrap_table(argv[1])

	// Pin so the objects wont be moved around.
	j.janet_gcroot(j.janet_wrap_function(func))
	j.janet_gcroot(j.janet_wrap_table(initial_props))

	modeline := obtain_modeline()

	cell := ml.ModelineCell{func, initial_props}

	append(&modeline.callbacks, cell)

	return j.janet_wrap_nil()
}

// Register native j.Janet functions.
register_cfuns :: proc(env: ^j.JanetTable) {
	fn_val := j.janet_wrap_cfunction(cfun_set_font_size)
	j.janet_def(env, "set-font-size", fn_val, "(set-font-size n)\n\nSet terminal font size.")

	fn_val = j.janet_wrap_cfunction(cfun_register_modeline_cb)
	j.janet_def(
		env,
		"register-modeline-cb",
		fn_val,
		"(register-modeline-cb priority lambda)\n\nRegister a modeline callback.",
	)
}
