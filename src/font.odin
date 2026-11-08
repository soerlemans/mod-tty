package main

import "core:fmt"
import "core:os"
import "core:c"
import "core:strings"

import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"
import janet "janet"

// Global or state-managed cached font pointer
@(private)
cached_font: ^ttf.Font = nil

get_system_font :: proc() -> ^ttf.Font {
    // Return immediately if already loaded
    if cached_font != nil {
        return cached_font
    }

    // Ensure SDL_ttf is initialized
    if ttf.WasInit() == 0 {
        if !ttf.Init() {
            return nil
        }
    }

    // Common system monospaced font paths on macOS
    system_paths := []string{
        "/System/Library/Fonts/SFMono-Regular.otf",
        "/System/Library/Fonts/Supplemental/Courier New.ttf",
        "/Library/Fonts/Menlo.ttc",
    }

    for path in system_paths {
        if os.exists(path) {
            c_path := strings.clone_to_cstring(path, context.temp_allocator)
            // Load at a crisp terminal size (e.g., 14.0 or 16.0 point font)
            cached_font = ttf.OpenFont(c_path, 15.0)
            if cached_font != nil {
                ttf.SetFontHinting(cached_font, .LIGHT)
                break
            }
        }
    }

    return cached_font
}