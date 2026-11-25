package session

import j "../ffi/janet"

import t "../types"
import ml "modeline"
import tty "tty"

Session :: struct {
	env:      ^j.JanetTable,
	prefs:    ^t.Preferences,
	term:     ^tty.Terminal,
	modeline: ^ml.Modeline,
}
