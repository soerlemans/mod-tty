package scripting

import "base:runtime"
import "core:log"
import "core:os"
import "core:strings"

import j "../ffi/janet"

import s "../session"
import ml "../session/modeline"
import t "../types"

@(private)
g_ctx: runtime.Context

capture_rt_context :: proc() {
	g_ctx = context
}


eval_file :: proc(env: ^j.JanetTable, path: string, allocator := context.allocator) -> bool {
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

	out: j.Janet
	status := j.janet_dobytes(env, raw_data(data), i32(len(data)), c_path, &out)
	if j.JanetSignal(status) != .JANET_SIGNAL_OK {
		log.errorf("Error running Janet file %q (signal %v)", path, status)
		return false
	}

	return true
}

// TODO: Also inject terminal into the environment and manipulate it.
// If any of these fail just kill the program.
// Initialize Janet VM, and load configuration.
init_scripting :: proc(sesh: ^s.Session) -> ^j.JanetTable {
	// Propagate context to C exposed functions.
	capture_rt_context()

	res := j.janet_init()
	if res != 0 {
		log.errorf("Failed to initialize Janet VM (error: %d)", res)
		os.exit(1)
	}

	env := j.janet_core_env(nil)
	if env == nil {
		log.errorf("Failed to create Janet core environment")
		j.janet_deinit()
		os.exit(1)
	}

	// Pin env to root so its never relocated.
	j.janet_gcroot(j.janet_wrap_table(env))

	// Register globals in environment.
	j.janet_absolute_setdyn(env, "preferences", rawptr(sesh.prefs))
	j.janet_absolute_setdyn(env, "modeline-callbacks", rawptr(&sesh.modeline.callbacks))

	register_cfuns(env)

	// TODO: Add reading from XDG_CONFIG_HOME.
	// And on Debug just read local init.janet.
	if eval_file(env, "init.janet") == false {
		log.errorf("Failed to read init.janet config.")
		os.exit(1)
	}

	return env
}


deinit_scripting :: proc() {
	j.janet_deinit()
}
