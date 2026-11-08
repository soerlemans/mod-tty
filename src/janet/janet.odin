package janet

import "core:c"

// FIXME: No Windows compilation at the moment.
when ODIN_OS == .Windows {
    foreign import lib "../../out/janet.lib"
} else {
    foreign import lib "../../out/libjanet.a"
}

// Janet's primary 64-bit tagged value type.
Janet :: u64 

// Opaque pointer types for Janet VM constructs.
JanetTable :: struct {}
JanetFiber :: struct {}
JanetEvalFlags :: c.int

@(default_calling_convention = "c")
foreign lib {
	janet_init :: proc() ---
	janet_deinit :: proc() ---
	janet_core_env :: proc(replacements: rawptr) -> ^JanetTable ---
	janet_dostring :: proc(env: ^JanetTable, str: cstring, sourcePath: cstring, out: ^Janet) -> c.int ---
	janet_table_get :: proc(t: ^JanetTable, key: Janet) -> Janet ---
	janet_ckeywordv :: proc(str: cstring) -> Janet ---
	janet_unwrap_integer :: proc(x: Janet) -> i32 ---
}