package janet

import "core:c"

// FIXME: No Windows compilation at the moment.
when ODIN_OS == .Windows {
    foreign import libjanet "../../out/janet.lib"
} else when ODIN_OS == .Darwin || ODIN_OS == .Linux {
    foreign import libjanet "../../out/janet.a"
}

// Janet's primary 64-bit tagged value type.
Janet :: u64 

// Opaque pointer types for Janet VM constructs.
JanetTable :: struct {}
JanetFiber :: struct {}
JanetEvalFlags :: c.int

@(default_calling_convention = "c")
foreign libjanet {
	janet_init :: proc() ---
	janet_deinit :: proc() ---
	janet_core_env :: proc(replacements: rawptr) -> ^JanetTable ---
	janet_dostring :: proc(env: ^JanetTable, str: cstring, sourcePath: cstring, out: ^Janet) -> c.int ---
	janet_table_get :: proc(t: ^JanetTable, key: Janet) -> Janet ---
	janet_unwrap_integer :: proc(x: Janet) -> i32 ---
	janet_csymbol :: proc(str: cstring) -> rawptr ---
	janet_wrap_keyword :: proc(sym: rawptr) -> Janet ---
}

// Re-implement the janet_ckeywordv macro cleanly in Odin:
// In Janet's C API: #define janet_ckeywordv(s) janet_wrap_keyword(janet_csymbol(s)).
janet_ckeywordv :: proc "c" (str: cstring) -> Janet {
	sym := janet_csymbol(str)
	return janet_wrap_keyword(sym)
}