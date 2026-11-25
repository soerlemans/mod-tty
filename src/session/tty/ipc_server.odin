package tty

import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:log"
import "core:os"
import "core:slice"
import "core:strings"
import "core:sys/posix"

IpcServer :: struct {
	fd:   posix.FD,
	path: cstring,
}

// Sets up the unix socket for shell integration.
ipc_init :: proc(pid: int) -> ^IpcServer {
	srv := new(IpcServer)

	runtime_dir := libc.getenv("XDG_RUNTIME_DIR")
	if runtime_dir == "" {
		runtime_dir = "/tmp"
	}

	path_str := fmt.aprintf("%s/modtty-%d.sock", runtime_dir, pid)
	srv.path = strings.clone_to_cstring(path_str)

	// Open UNIX socket.
	fd := posix.socket(.UNIX, .STREAM, {})
	if fd == -1 {
		free(srv)
		return nil
	}

	// Set non-blocking & close-on-exec so child shell doesn't inherit it.
	flags := posix.fcntl(fd, .GETFL)
	posix.fcntl(fd, .SETFL, flags | i32(posix.O_NONBLOCK))

	fd_flags := posix.fcntl(fd, .GETFD)
	posix.fcntl(fd, .SETFD, fd_flags | i32(posix.FD_CLOEXEC))

	posix.unlink(srv.path)

	addr: posix.sockaddr_un
	addr.sun_family = .UNIX
	copy(addr.sun_path[:], path_str)

	if posix.bind(fd, cast(^posix.sockaddr)&addr, size_of(addr)) != .OK {
		posix.close(fd)
		free(srv)
		return nil
	}

	if posix.listen(fd, 8) != .OK {
		posix.close(fd)
		free(srv)
		return nil
	}

	srv.fd = fd
	log.debugf("IpcServer init: %v", srv)
	return srv
}

ipc_free :: proc(srv: ^IpcServer) {
	if srv != nil {
		if srv.fd != -1 {
			posix.close(srv.fd)
			srv.fd = -1
		}
		if srv.path != nil {
			posix.unlink(srv.path)
			delete(srv.path)
			srv.path = nil
		}

		free(srv)
	}
}
