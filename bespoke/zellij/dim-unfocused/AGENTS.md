# Zellij Pane Shader System

## Architecture

This is a custom Zellij build with pane shader support. A plugin (`dim-unfocused`) applies a compiled WASM shader to unfocused panes. The shader runs once per render — there is no animation.

```
dim-unfocused plugin (WASI)          Zellij server (patched fork)
  │                                    │
  │ set_pane_shader(pane_id, wasm)     │
  │ ──────────────────────────────────>│
  │    (protobuf via plugin API)       │
  │                                    ├─> ShaderInstance::new(wasm_bytes)
  │                                    │     loads WASM via wasmi
  │                                    │
  │                                    └─> On render: shade_batch(colors)
  │                                          writes uniforms + colors to WASM memory
  │                                          calls WASM shade_batch(ptr, count)
  │                                          reads back transformed colors
```

### Key Files

- `shader/src/lib.rs` — WASM shader (no_std Rust, wasm32-unknown-unknown). Fast to build (~seconds).
- `src/main.rs` — dim-unfocused plugin (wasm32-wasip1). Fast to build (~seconds).
- `flake.nix` — Nix build: shader WASM → plugin WASM → custom Zellij.
- Fork: `github:tteggel/zellij` branch `pane-shaders-static` — the patched Zellij. **Slow to build (~20 minutes).**

### Fork Integration Points (in Zellij source)

These are the files modified in the fork. When rebasing on upstream, these are the conflict zones:

| File | What | Risk |
|------|------|------|
| `zellij-server/src/output/mod.rs` | `ShaderInstance`, `ShaderUniforms`, `apply_shader_to_styles`, `serialize_chunks` | **High** — core rendering |
| `zellij-server/src/screen.rs` | `ScreenInstruction::SetPaneShader` handler | Medium |
| `zellij-server/src/panes/grid.rs` | `pane_shader` field on `Grid`, uniforms construction in render | Medium |
| `zellij-server/src/panes/terminal_pane.rs` | `Pane::set_pane_shader` impl | Low |
| `zellij-server/src/tab/mod.rs` | `Pane` trait method, `Tab::set_pane_shader` | Low |
| `zellij-server/src/plugins/zellij_exports.rs` | `PluginCommand::SetPaneShader` dispatch + `set_pane_shader` fn | Medium |
| `zellij-tile/src/shim.rs` | `set_pane_shader` shim function | Low |
| `zellij-utils/src/data.rs` | `PluginCommand::SetPaneShader` variant | Low |
| `zellij-utils/src/errors.rs` | `ScreenContext::SetPaneShader` variant | Low |
| `zellij-utils/src/plugin_api/plugin_command.proto` | Protobuf message definitions | Low |
| `zellij-utils/src/plugin_api/plugin_command.rs` | Protobuf conversion impls | Low |
| `zellij-utils/assets/prost/api.plugin_command.rs` | Generated protobuf code | Low |

## WASM Memory Layout

The shader WASM uses linear memory with this layout:

| Offset | Size | Purpose |
|--------|------|---------|
| 0–~1023 | varies | **WASM stack + static data** (DO NOT WRITE HERE from host) |
| 1024–65407 | ~64KB | Color data for `shade_batch` |
| 65408–65535 | 128 bytes | **Uniforms block** (written by host before each call) |

### Critical: Do not write host data at low WASM memory offsets

The WASM toolchain (wasm32-unknown-unknown) places the stack and static variables at low addresses starting from offset 0. Writing uniforms at offset 0 silently clobbers the module's internal state, causing `shade_batch` to trap. This failure is **completely silent** — `wasmi::TypedFunc::call()` returns `Err`, `.ok()` converts it to `None`, and the shader just doesn't apply.

### Uniforms Block (128 bytes at offset 65408)

`#[repr(C)]` on host side. Shader reads via `read_i32(UNIFORMS_OFFSET + field_offset)`.

| Offset | Field |
|--------|-------|
| 0 | `pane_width` |
| 4 | `pane_height` |
| 8–127 | reserved (zeros) |

The block is fixed at 128 bytes so adding fields later doesn't break the contract — they just go into the reserved range.

## WASM API Contract

The shader exports one function:

- `shade_batch(colors_ptr: i32, count: i32)` — **required**. Reads uniforms from offset 65408. Reads/writes color entries at `colors_ptr` (6 × i32 each = 24 bytes: r, g, b, x, y, is_fg).

There is no `invalidate()` / animation tick. The shader runs once per render triggered by terminal output, pane focus changes, or resize.

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

### Flake lock management

The fork is a flake input (`zellij-src`) of the sub-flake (`bespoke/zellij/dim-unfocused/flake.nix`). The top-level dotfiles flake imports the sub-flake as a path input. When updating the fork:

```bash
# Update sub-flake lock
cd bespoke/zellij/dim-unfocused && nix flake update zellij-src

# Update top-level lock (must pick up the sub-flake change)
cd ../../.. && nix flake update
```

Both locks must point to the same fork commit or the build uses stale code.

When the fork's upstream picks up new dependencies (e.g., `dunce`), the plugin's vendored `Cargo.lock` also needs regenerating:

```bash
# Stage plugin sources with a symlink to the fork checkout
mkdir -p $TMPDIR/dim-plugin-lockgen
cp -a bespoke/zellij/dim-unfocused/{src,Cargo.toml,Cargo.lock} $TMPDIR/dim-plugin-lockgen/
ln -s /path/to/zellij-fork-clone $TMPDIR/dim-plugin-lockgen/zellij-src

# Regenerate. The default devShell carries the rust-overlay toolchain; the
# `#zellij` package env no longer puts cargo on PATH, and generate-lockfile
# only resolves deps so it needs no native build inputs.
nix develop ./bespoke/zellij/dim-unfocused \
  --command bash -c "cd $TMPDIR/dim-plugin-lockgen && cargo generate-lockfile"

cp $TMPDIR/dim-plugin-lockgen/Cargo.lock bespoke/zellij/dim-unfocused/Cargo.lock
```

### The zellij derivation overrides `zellij-unwrapped`, not `zellij`

nixpkgs' `zellij` attribute is a `symlinkJoin` wrapper around `zellij-unwrapped`
(the actual `buildRustPackage`). `pkgs.zellij.overrideAttrs` therefore overrides
*the wrapper* — the build succeeds in seconds and silently ships stock upstream
zellij with no pane-shader support. Always override `pkgs.zellij-unwrapped`, and
sanity-check a build with:

```bash
readlink -f result/bin/zellij   # must NOT point at a zellij-unwrapped-X.Y.Z store path
```

nixpkgs' `postInstall` also runs `mandown docs/MANPAGE.md`, which upstream
deleted in zellij-org/zellij#5426, so the flake overrides `postInstall` to
install only the shell completions.

### Rebasing the fork

```bash
git clone https://github.com/tteggel/zellij /tmp/zellij-fork
cd /tmp/zellij-fork
git remote add upstream https://github.com/zellij-org/zellij.git
git fetch upstream main
git checkout -b pane-shaders-static-next upstream/main
git cherry-pick pane-shaders-static
# resolve conflicts, especially in output/mod.rs and grid.rs
git push origin pane-shaders-static-next
# update flake locks as above
# once happy: rename pane-shaders-static-next → pane-shaders-static via gh
```

Push uses SSH (`git@github.com:tteggel/zellij.git`) because rebasing usually pulls in upstream `.github/workflows/*.yml` changes that the OAuth token can't authorize.

Verify before pushing by building straight from the local checkout — no push, no
lock churn:

```bash
nix build ./bespoke/zellij/dim-unfocused#zellij \
  --override-input zellij-src "git+file:///path/to/zellij-fork?ref=pane-shaders-static-next"
```

**Proto tag numbers are the recurring conflict.** The patch claims one
`CommandName` and one `PluginCommand.payload` tag, and upstream keeps taking the
next free values. On each rebase, renumber ours above whatever upstream now
occupies, in both `plugin_command.proto` and the generated
`assets/prost/api.plugin_command.rs` (enum value, `as_str_name`, `from_str_name`,
and the `tags="…"` list on `PluginCommand::payload`). History so far:
215→227→229 for `CommandName`, 164→172 for the payload oneof.

Upstream also raises its MSRV regularly (0.45 needs rustc 1.95), so a rebase
usually means bumping the sub-flake's `nixpkgs` and `rust-overlay` too.
