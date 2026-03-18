# Plan: WASM Pane Shaders for Zellij

## Status: Current (rhai) implementation works, WASM migration planned

## What We Have Today

A source patch to Zellij that adds `SetPaneShader(PaneId, Option<String>)` — plugins
send a rhai script string that defines `fn shade(r, g, b, x, y, w, h, is_fg)` returning
`[r, g, b]`. The server compiles the script once and evaluates it per-cell during rendering.

Native Rust helpers registered in the rhai engine: `mix`, `clamp`, `sqrt`, `abs`, `min`,
`max`, `rgb_to_oklch`, `oklch_to_rgb`.

The `dim-unfocused` plugin uses this to desaturate and apply a glare effect to unfocused
panes, working in OKLCH color space for perceptually uniform results.

Live-reload supported: plugin can watch a shader file on disk via `FileSystemUpdate` events.

## Why Move to WASM

- **Fewer new deps**: rhai adds a new dependency; wasmi is already in zellij's tree
- **Upstream-friendly**: WASM is zellij's native plugin format — a WASM shader contract
  is a natural extension, not a bolted-on scripting engine
- **Language-agnostic**: shaders can be written in any language targeting WASM
- **Performance**: OKLCH math compiled to WASM instructions, not interpreted through rhai's
  dynamic dispatch. Batching amortises call overhead.
- **Maintainability**: clean ABI boundary means the patch is smaller and more resilient to
  upstream changes

## Architecture

### Shader WASM Module

Tiny `no_std` Rust crate (`wasm32-unknown-unknown`), no WASI. Exports:

```
// Required: transform colors in batch
// Reads/writes an array of (r, g, b, x, y, is_fg) tuples at colors_ptr
// Each entry: 6 × i32 = 24 bytes. is_fg: 0 or 1.
shade_batch(colors_ptr: i32, count: i32, w: i32, h: i32,
            cursor_x: i32, cursor_y: i32, time_ms: i32)

// Optional: declare which rows need re-rendering this tick
// Writes row indices to out_ptr, returns count written
// Absence means "not animated" — never ticked, zero overhead
invalidate(out_ptr: i32, max_rows: i32, w: i32, h: i32,
           t_ms: i32, cx: i32, cy: i32,
           prev_cx: i32, prev_cy: i32) -> i32
```

All color space conversion (OKLCH etc) lives inside the shader module as compiled Rust.

### Transport

`SetPaneShader(PaneId, Option<Vec<u8>>)` — plugin sends the `.wasm` bytes.
`None` clears the shader.

### Server-Side (zellij patch)

**Grid** stores:
- `Option<ShaderInstance>` where `ShaderInstance` wraps a wasmi `Store<()>` + `Instance`
- Compiled once when `set_pane_shader()` is called with Some(bytes)
- No WASI linkage — pure computation module, lightweight Store

**Rendering** (`output/mod.rs`):
- `CharacterChunk` carries a reference to the shader instance + pane dimensions + cursor + time
- Before the per-character style loop, marshal the chunk's colors into WASM linear memory
- Call `shade_batch()` once per chunk
- Read transformed colors back, apply to styles
- Existing diff-based rendering unchanged — only dirty cells get processed

**Animation tick** (`screen.rs`):
- If any pane's shader exports `invalidate`, screen render loop calls it each tick
- Returned row indices → `output_buffer.update_line(row)` → those rows re-enter the
  normal render pipeline
- Static shaders (no `invalidate` export) → never ticked, zero overhead
- Auto-pause: if `invalidate` returns empty for N consecutive frames, stop ticking
  until next cursor move / focus change

### Plugin (`dim-unfocused`)

- Builds a separate `shader/` crate to `wasm32-unknown-unknown`
- Embeds the `.wasm` bytes (via `include_bytes!`) or loads from filesystem for live-reload
- Sends bytes via `set_pane_shader(pane_id, Some(wasm_bytes.to_vec()))`
- Shader crate contains all the OKLCH math and effect logic

### Nix Build

- Shader crate builds with `cargo build --target wasm32-unknown-unknown --release`
- Plugin crate builds with `cargo build --target wasm32-wasip1 --release`
- Both use the same Rust toolchain (already has both targets)
- Patch no longer adds rhai to zellij-server/Cargo.toml

## Animation Use Cases

With `invalidate` + `time_ms` + cursor position:

- **Focus transitions**: smooth fade over ~200ms instead of instant shader on/off.
  Plugin sends shader on focus loss; shader uses `t` to interpolate from clear to dimmed.
  `invalidate` returns all rows during transition, then empty once settled.
- **Cursor glow**: `invalidate` returns ~8 rows (old + new cursor radius).
  `shade_batch` brightens cells near cursor position.
- **Breathing/pulse**: `invalidate` returns all rows each frame (explicit full-repaint opt-in).
- **Waves/gradients**: `invalidate` returns a sliding band of rows.

## Migration Steps

1. Create `bespoke/zellij/dim-unfocused/shader/` crate with OKLCH + glare effect
2. Update zellij patch: replace rhai with wasmi shader loading in grid.rs
3. Update output/mod.rs: batch marshal/unmarshal instead of per-cell rhai calls
4. Update protobuf: `SetPaneShader` payload from `optional string` to `optional bytes`
5. Update plugin: embed shader .wasm, send bytes instead of script string
6. Add animation: thread cursor + time through to shade_batch, add invalidate tick
7. Update flake.nix: build shader crate, remove rhai from zellij deps
