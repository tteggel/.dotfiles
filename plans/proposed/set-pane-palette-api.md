# Zellij Plugin API: SetPanePalette

## Problem

The `set_pane_color` plugin API only overrides default fg/bg — cells with
explicit ANSI colors (syntax highlighting, colored `ls` output, prompts, etc.)
are unaffected. This makes focus-based dimming inconsistent: plain text dims
but colored output stays vivid.

## Existing infrastructure

Zellij already supports per-pane palette overrides via OSC 4 escape sequences.
In `grid.rs`, each pane has:

```rust
changed_colors: Option<[Option<AnsiCode>; 256]>
```

When a program inside a pane writes `\e]4;INDEX;COLOR\a`, the grid stores the
override and uses it at render time. This means the full 256-color palette can
already be remapped per-pane — but only from terminal output, not from plugins.

## Proposed API

Add a `PluginCommand::SetPanePalette` that sets `changed_colors` on a pane's
grid from the plugin side:

```rust
// In zellij-tile shim:
pub fn set_pane_palette(pane_id: PaneId, overrides: Vec<(u8, Option<String>)>) {
    // overrides: vec of (color_index, hex_color_or_none_to_reset)
    // e.g. [(1, Some("#994444")), (2, Some("#449944")), ...]
}
```

This mirrors what OSC 4 already does but exposed to the plugin system. The
implementation would route through the same `changed_colors` storage.

## Use case: dim-unfocused plugin

With `SetPanePalette`, the dim-unfocused plugin could:

1. On focus change, compute dimmed versions of all 16 standard ANSI colors
   (blend each toward the background by a configurable factor)
2. Call `set_pane_palette` on unfocused panes with the dimmed palette
3. Call `set_pane_palette` on the focused pane with `None` values to reset

This would dim **all** colored content uniformly — syntax highlighting, colored
ls, git diff, prompts — not just unstyled text.

## Implementation scope (estimated small)

- Add `SetPanePalette(PaneId, Vec<(u8, Option<(u8,u8,u8)>)>)` to `PluginCommand`
- Add protobuf message for the command
- Route it through `screen.rs` to set `changed_colors` on the target pane's grid
- Add `set_pane_palette` to `zellij-tile` shim
- Permission: `ChangeApplicationState` (same as `set_pane_color`)

The heavy lifting (palette storage, render-time application) already exists.

## References

- OSC 4 handling: `zellij-server/src/panes/grid.rs` line ~3224
- `changed_colors` storage: `Grid` struct
- Per-pane color PR: https://github.com/zellij-org/zellij/pull/4737
- Dynamic colors issue: https://github.com/zellij-org/zellij/issues/2105
