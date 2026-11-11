package sys_util

import "core:c"
import "core:sys/posix"

// forkpty is not in POSIX, so we need to define our own bindings.
when ODIN_OS == .Linux || ODIN_OS == .FreeBSD || ODIN_OS == .OpenBSD || ODIN_OS == .NetBSD {
    foreign import libutil "system:util"
} else when ODIN_OS == .Darwin {
    foreign import libutil "system:c"
}

winsize :: struct {
    ws_row:    c.ushort,
    ws_col:    c.ushort,
    ws_xpixel: c.ushort,
    ws_ypixel: c.ushort,
}

@(default_calling_convention="c")
foreign libutil {
    forkpty :: proc(
        amaster: ^posix.FD,
        name:    cstring,
        termp:   ^posix.termios,
        winp:    ^winsize,
    ) -> posix.pid_t ---
}