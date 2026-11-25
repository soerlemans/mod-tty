package janet

import "core:c"

// FIXME: No Windows compilation at the moment.
when ODIN_OS == .Windows {
		foreign import libjanet {
				"../../../deps/build/janet.lib"
		}
} else when ODIN_OS == .Darwin || ODIN_OS == .Linux {
		foreign import libjanet {
				"../../../deps/build/libjanet.a"
		}
}

// Janet's primary 64-bit tagged value type.
Janet :: u64

JanetCFunction :: #type proc "c" (argc: i32, argv: [^]Janet) -> Janet

// Opaque pointer types for Janet VM constructs.
// TODO: Define fully.
JanetTable :: struct {}
JanetFunction :: struct {}
JanetFiber :: struct {}
JanetEvalFlags :: c.int

/* All possible types */
JanetType :: enum c.int {
	JANET_NUMBER,
	JANET_NIL,
	JANET_BOOLEAN,
	JANET_FIBER,
	JANET_STRING,
	JANET_SYMBOL,
	JANET_KEYWORD,
	JANET_ARRAY,
	JANET_TUPLE,
	JANET_TABLE,
	JANET_STRUCT,
	JANET_BUFFER,
	JANET_FUNCTION,
	JANET_CFUNCTION,
	JANET_ABSTRACT,
	JANET_POINTER,
}

/* Fiber signals */
JanetSignal :: enum c.int {
    JANET_SIGNAL_OK,
    JANET_SIGNAL_ERROR,
    JANET_SIGNAL_DEBUG,
    JANET_SIGNAL_YIELD,
    JANET_SIGNAL_USER0,
    JANET_SIGNAL_USER1,
    JANET_SIGNAL_USER2,
    JANET_SIGNAL_USER3,
    JANET_SIGNAL_USER4,
    JANET_SIGNAL_USER5,
    JANET_SIGNAL_USER6,
    JANET_SIGNAL_USER7,
    JANET_SIGNAL_USER8,
    JANET_SIGNAL_USER9,
    JANET_SIGNAL_INTERRUPT = JANET_SIGNAL_USER8,
    JANET_SIGNAL_EVENT = JANET_SIGNAL_USER9,
}

@(default_calling_convention = "c")
foreign libjanet {
	// Janet VM:
	janet_init :: proc "c" () -> c.int ---
	janet_deinit :: proc "c" () ---
	janet_core_env :: proc "c" (replacements: rawptr) -> ^JanetTable ---

	// Call a function.
	janet_pcall :: proc(fun: ^JanetFunction, argn: i32, argv: ^Janet, out: ^Janet, f: ^^JanetFiber) -> JanetSignal ---
	janet_call :: proc(fun: ^JanetFunction, argn: i32, argv: ^Janet) -> Janet ---
	janet_mcall :: proc(name: cstring, argn: i32, argv: ^Janet) -> Janet ---

		// Typing:
	janet_type :: proc "c" (x: Janet) -> JanetType ---
	janet_checktype :: proc "c" (x: Janet, type: JanetType ) -> c.int ---
	janet_truthy :: proc "c" (x: Janet) -> c.int ---

	// Environment:
	janet_gcroot :: proc "c" (root: Janet) ---
	janet_gcunroot :: proc "c" (root: Janet) -> c.int ---

	janet_table_get :: proc "c" (t: ^JanetTable, key: Janet) -> Janet ---
	janet_table_put :: proc "c" (t: ^JanetTable, key: Janet, val: Janet) ---

	janet_setdyn :: proc "c" (name: cstring, val: Janet) ---
	janet_dyn :: proc "c" (name: cstring) -> Janet ---
	janet_def :: proc "c" (env: ^JanetTable, name: cstring, val: Janet, documentation: cstring) ---

	// Execution:
	janet_dobytes :: proc "c" (env: ^JanetTable, str: ^u8, len: i32, sourcePath: cstring, out: ^Janet) -> c.int ---
	janet_dostring :: proc "c" (env: ^JanetTable, str: cstring, sourcePath: cstring, out: ^Janet) -> c.int ---

	// C types:
	janet_csymbol :: proc "c" (str: cstring) -> rawptr ---
	janet_cstring :: proc "c" (str: cstring) -> ^u8 ---

	// Wrap:
	janet_wrap_nil :: proc "c" () -> Janet ---
	janet_wrap_number :: proc "c" (x: f64) -> Janet ---
	janet_wrap_true :: proc "c" () -> Janet ---
	janet_wrap_false :: proc "c" () -> Janet ---
	janet_wrap_boolean :: proc "c" (val: c.bool) -> Janet ---
	janet_wrap_string :: proc "c" (s: ^u8) -> Janet ---
	janet_wrap_keyword :: proc "c" (sym: rawptr) -> Janet ---
  janet_wrap_function :: proc "c" (fn: ^JanetFunction) -> Janet ---
  janet_wrap_cfunction :: proc "c" (fn: JanetCFunction) -> Janet ---
	janet_wrap_table :: proc "c" (x: ^JanetTable) -> Janet ---
	janet_wrap_pointer :: proc "c" (x: rawptr) -> Janet ---
	janet_wrap_integer :: proc "c" (x: c.int) -> Janet ---

	// Unwrap:
	janet_unwrap_integer :: proc "c" (x: Janet) -> i32 ---
	janet_unwrap_number :: proc "c" (x: Janet) -> f64 ---
	janet_unwrap_table :: proc "c" (x: Janet) -> ^JanetTable ---
	janet_unwrap_function :: proc "c" (x: Janet) -> ^JanetFunction ---
	janet_unwrap_pointer :: proc "c" (x: Janet) -> rawptr ---

	janet_arity :: proc "c" (arity: i32, min: i32, max: i32) ---
	janet_fixarity :: proc "c" (arity: i32, fix: i32) ---

	// Error:
  janet_panic         :: proc "c" (format: cstring) ---
  janet_panicf         :: proc "c" (format: cstring, #c_vararg args: ..any) ---
}

// Re-implement the janet_ckeywordv macro cleanly in Odin:
// In Janet's C API: #define janet_ckeywordv(s) janet_wrap_keyword(janet_csymbol(s)).
janet_ckeywordv :: proc(str: cstring) -> Janet {
	sym := janet_csymbol(str)
	return janet_wrap_keyword(sym)
}

janet_cstringv :: proc(str: cstring) -> Janet {
	return janet_wrap_string(janet_cstring(str))
}

// Absolute setdyn by directly setting the value in env.
janet_absolute_setdyn :: proc(env: ^JanetTable, key: cstring, ptr: rawptr) {
		janet_table_put(env, janet_ckeywordv(key), janet_wrap_pointer(ptr))
}
