package janet

import "core:log"
import "core:os"
import "base:runtime"
import "core:strings"

import t "../types"

@(private)
g_ctx: runtime.Context

capture_scripting_context :: proc() {
	g_ctx = context
}


eval_file :: proc(env: ^JanetTable, path: string, allocator := context.allocator) -> bool {
	data, err := os.read_entire_file(path, allocator)
	if err != nil {
		log.warnf("Could not read Janet file: %q", path)
		return false
	}
	defer delete(data, allocator)

	if len(data) == 0 {
		return true
	}

	// `sourcePath` in Janet must be a null-terminated C string for error messages/stacktraces.
	c_path := strings.clone_to_cstring(path, context.temp_allocator)

	out: Janet
	status := janet_dobytes(env, raw_data(data), i32(len(data)), c_path, &out)
	if JanetSignal(status) != .JANET_SIGNAL_OK {
		log.errorf("Error running Janet file %q (signal %v)", path, status)
		return false
	}

	return true
}

// TODO: Also inject terminal into the environment and manipulate it.
// If any of these fail just kill the program.
// Initialize Janet VM, and load configuration.
init_scripting :: proc(prefs: ^t.Preferences) {
	// Propagate context to C exposed functions.
	capture_scripting_context()

	res := janet_init()
	if res != 0 {
		log.errorf("Failed to initialize Janet VM (error: %d)", res)
		os.exit(1)
	}

	env := janet_core_env(nil)
	if env == nil {
   log.errorf("Failed to create Janet core environment")
   janet_deinit()
   os.exit(1)
	}

	// Pin env so that its always referable.
	janet_gcroot(janet_wrap_table(env))

	// Register Odin interop.
	// janet_setdyn("preferences", janet_wrap_pointer(prefs))
	g_prefs = prefs
	register_cfuns(env)

	// Load config file.
	if eval_file(env, "init.janet") == false {
		log.errorf("Failed to read init.janet config.")
		os.exit(1)
	}
}
