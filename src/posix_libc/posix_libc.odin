package posix_libc

import "core:c"
import "core:sys/posix"

// Very much a hack.
when ODIN_OS == .Linux {
    TIOCSWINSZ :: 0x5414
} else when ODIN_OS == .Darwin {
    // macOS (BSD-derived ioctl value)
    TIOCSWINSZ :: 0x80087468
} else {
    #panic("Unsupported platform for PTY window resizing")
}

foreign import plibc "system:c"

winsize :: struct {
	ws_row:    c.ushort,
	ws_col:    c.ushort,
	ws_xpixel: c.ushort,
	ws_ypixel: c.ushort,
}

@(default_calling_convention = "c")
foreign plibc {
    ioctl :: proc(fd: i32, request: u32, ws: ^winsize) -> i32 ---
}
