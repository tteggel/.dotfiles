# Zellij Pane Shader System

## Architecture

This is a custom Zellij build with pane shader support. A plugin (`dim-unfocused`) applies compiled WASM shaders to unfocused panes.

```
dim-unfocused plugin (WASI)          Zellij server (patched fork)
  │                                    │
  │ set_pane_shader(pane_id, wasm)     │
  │ ──────────────────────────────────>│
  │    (protobuf via plugin API)       │
  │                                    ├─> ShaderInstance::new(wasm_bytes)
  │                                    │     loads WASM via wasmi
  │                                    │
  │                                    ├─> On render: shade_batch(colors)
  │                                    │     writes uniforms + colors to WASM memory
  │                                    │     calls WASM shade_batch(ptr, count)
  │                                    │     reads back transformed colors
  │                                    │
  │                                    ├─> On animation tick: invalidate()
  │                                    │     writes uniforms to WASM memory
  │                                    │     calls WASM invalidate(out_ptr, max)
  │                                    │     marks returned rows dirty
  │                                    │     schedules re-render
```

### Key Files

- `shader/src/lib.rs` — WASM shader (no_std Rust, wasm32-unknown-unknown). Fast to build (~seconds).
- `src/main.rs` — dim-unfocused plugin (wasm32-wasip1). Fast to build (~seconds).
- `flake.nix` — Nix build: shader WASM → plugin WASM → custom Zellij.
- Fork: `github:tteggel/zellij` branch `pane-shaders` — the patched Zellij. **Slow to build (~20 minutes).**

### Fork Integration Points (in Zellij source)

These are the files modified in the fork. When rebasing on upstream, these are the conflict zones:

| File | What | Risk |
|------|------|------|
| `zellij-server/src/output/mod.rs` | ShaderInstance, ShaderUniforms, apply_shader_to_styles, serialize_chunks | **High** — core rendering |
| `zellij-server/src/screen.rs` | ScreenInstruction::SetPaneShader handler, animation tick in RenderToClients | **High** — instruction dispatch |
| `zellij-server/src/panes/grid.rs` | Grid fields (pane_shader, shader_context, prev positions), uniforms construction in render | Medium |
| `zellij-server/src/panes/terminal_pane.rs` | Pane trait impls (set_pane_shader, tick_shader_animation, set_shader_context) | Medium |
| `zellij-server/src/tab/mod.rs` | Pane trait additions, Tab::tick_shader_animations, Tab::set_pane_shader | Medium |
| `zellij-server/src/plugins/zellij_exports.rs` | PluginCommand::SetPaneShader dispatch + set_pane_shader fn | Medium |
| `zellij-tile/src/shim.rs` | set_pane_shader shim function | Low |
| `zellij-utils/src/data.rs` | PluginCommand::SetPaneShader variant | Low |
| `zellij-utils/src/errors.rs` | ScreenContext::SetPaneShader variant | Low |
| `zellij-utils/src/plugin_api/plugin_command.proto` | Protobuf message definitions | Low |
| `zellij-utils/src/plugin_api/plugin_command.rs` | Protobuf conversion impls | Low |
| `zellij-utils/assets/prost/api.plugin_command.rs` | Generated protobuf code | Low |

## WASM Memory Layout

The shader WASM uses linear memory with this layout:

| Offset | Size | Purpose |
|--------|------|---------|
| 0–~1023 | varies | **WASM stack + static data** (DO NOT WRITE HERE from host) |
| 1024–65407 | ~64KB | Color data for shade_batch |
| 65408–65535 | 128 bytes | **Uniforms block** (written by host before each call) |
| 65536+ | varies | Invalidation output buffer (row indices) |

### Critical: Do not write host data at low WASM memory offsets

The WASM toolchain (wasm32-unknown-unknown) places the stack and static variables (e.g., `LAST_BREATH`) at low addresses starting from offset 0. Writing uniforms at offset 0 silently clobbers the module's internal state, causing shade_batch to trap. This failure is **completely silent** — `wasmi::TypedFunc::call()` returns `Err`, `.ok()` converts it to `None`, and the shader just doesn't apply.

### Uniforms Block (128 bytes at offset 65408)

32 x i32, `#[repr(C)]` on host side. Shader reads via `read_i32(UNIFORMS_OFFSET + field_offset)`.

```
+0   pane_width        +64  sel_start_x
+4   pane_height       +68  sel_start_y
+8   cursor_x          +72  sel_end_x
+12  cursor_y          +76  sel_end_y
+16  mouse_x (-1=none) +80  prev_cursor_x
+20  mouse_y           +84  prev_cursor_y
+24  time_ms           +88  prev_mouse_x
+28  pane_id           +92  prev_mouse_y
+32  is_focused        +96  reserved[0..7]
+36  scroll_offset
+40  pane_x
+44  pane_y
+48  screen_width
+52  screen_height
+56  pane_count
+60  has_selection
```

## WASM API Contract

The shader exports two functions:

- `shade_batch(colors_ptr: i32, count: i32)` — **required**. Reads uniforms from offset 65408. Reads/writes color entries at colors_ptr (6 x i32 each = 24 bytes: r, g, b, x, y, is_fg).
- `invalidate(out_ptr: i32, max_rows: i32) -> i32` — **optional**. Enables animation. Returns count of dirty row indices written to out_ptr. Returns 0 = no changes needed.

## Debugging

### Build Times

- **Shader WASM**: seconds. Source: `shader/src/lib.rs`.
- **Plugin WASM**: seconds. Source: `src/main.rs`.
- **Zellij server**: ~20 minutes. Source: the fork.

Only push fork changes when you're confident. Batch all debug logging into a single push. Prefer diagnosing from code reading over speculative log-and-rebuild cycles.

### The shader silently does nothing

Most likely: `shade_batch` is trapping (WASM panic) and returning `None`. Common causes:
- Host writing to WASM memory offsets that overlap with WASM stack/data (see memory layout above)
- Memory not grown large enough before write
- Uniforms offset mismatch between host and shader

### Plugin permissions not granted

The plugin requires `ReadApplicationState` and `ChangeApplicationState`. Permissions are cached in `~/.cache/zellij/permissions.kdl`. If the cache exists with correct entries, `request_permission()` in `zellij_exports.rs` sends `PermissionRequestResult(Granted)` directly to the plugin without UI.

If permissions aren't working:
1. Check if the cache file exists and has the right plugin path
2. Check logs for "permission" messages
3. The plugin path must match exactly (e.g., `~/.config/zellij/plugins/dim-unfocused.wasm`)

### Animation not updating visually

The breathing animation uses `sinf(time * 0.0015)`. The `time_ms` value is epoch milliseconds truncated to i32 (~188 million). At this magnitude, `f32` loses the fractional precision needed for `sinf`. The shader applies `time_ms % 10_000_000` to keep values in a range where f32 sin works correctly. If animation looks frozen, check that this modular reduction is applied consistently in both `shade_batch` and `invalidate`.

### Flake lock management

The fork is a flake input (`zellij-src`) of the sub-flake (`bespoke/zellij/dim-unfocused/flake.nix`). The top-level dotfiles flake imports the sub-flake as a path input. When updating the fork:

```bash
# Update sub-flake lock
cd bespoke/zellij/dim-unfocused && nix flake update zellij-src

# Update top-level lock (must pick up the sub-flake change)
cd ../../.. && nix flake update
```

Both locks must point to the same fork commit or the build uses stale code.

### Rebasing the fork

```bash
cd /path/to/zellij-fork
git remote add upstream https://github.com/zellij-org/zellij.git  # if not done
git fetch upstream main
git rebase upstream/main
# resolve conflicts, especially in screen.rs and output/mod.rs
git push --force-with-lease origin pane-shaders
# then update flake locks as above
```
