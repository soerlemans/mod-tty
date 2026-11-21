package janet

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"

import t "../types"

// Janet fibres are a pain.
// So just use a private global for now.
@(private)
g_prefs: ^t.Preferences

// Obtain preferences pointer from dynamic binding.
janet_obtain_preferences :: proc() -> ^t.Preferences {
	val := janet_dyn("preferences")

	if janet_checktype(val, .JANET_POINTER) == 0 {
		typ := janet_type(val)
		fmt.eprintf("Janet value type: %v\n", typ)
		janet_panic("missing :preferences pointer in Janet dynamic bindings!")
	}
	return (^t.Preferences)(janet_unwrap_pointer(val))
}

// Odin function binding (set-font-size <size>).
cfun_set_font_size :: proc "c" (argc: i32, argv: [^]Janet) -> Janet {
	context = g_ctx
	janet_fixarity(argc, 1)

	args := ([^]Janet)(argv)
	size := janet_unwrap_number(argv[0])
	if size < 6 || size > 96 {
		janet_panicf("font size out of range: %g", size)
	}

	// prefs := janet_obtain_preferences()
	prefs:= g_prefs // TODO: Replace with dyn.
	prefs.font_size = int(size)
	log.debug("Config set font_size =", prefs.font_size)

	return janet_wrap_nil()
}

// Register native Janet functions.
register_cfuns :: proc(env: ^JanetTable) {
	fn_val := janet_wrap_cfunction(cfun_set_font_size)
	janet_def(env, "set-font-size", fn_val, "(set-font-size n)\n\nSet terminal font size.")
}
