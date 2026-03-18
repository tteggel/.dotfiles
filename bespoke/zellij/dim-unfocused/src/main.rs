use std::collections::BTreeMap;
use std::path::PathBuf;
use zellij_tile::prelude::*;

struct DimUnfocused {
    shader_script: String,
    shader_file: Option<PathBuf>,
    dimmed_panes: std::collections::HashSet<(u32, bool)>,
}

impl Default for DimUnfocused {
    fn default() -> Self {
        Self {
            shader_script: String::new(),
            shader_file: None,
            dimmed_panes: std::collections::HashSet::new(),
        }
    }
}

register_plugin!(DimUnfocused);

fn default_shader() -> String {
    r#"fn shade(r, g, b, x, y, w, h, is_fg) {
    let lch = rgb_to_oklch(r, g, b);
    let l = lch[0];
    let c = lch[1];
    let hue = lch[2];

    // Pane-local coordinates (x,y are screen-global)
    let lx = x % max(w, 1.0);
    let ly = y % max(h, 1.0);

    // --- Vignette: edge darkening ---
    let nx = lx / max(w, 1.0);
    let ny = ly / max(h, 1.0);
    let vx = (nx - 0.5) * 2.0;
    let vy = (ny - 0.5) * 2.0;
    let vdist = sqrt(vx * vx + vy * vy);
    let vignette = clamp(1.2 - vdist * 0.4, 0.55, 1.0);

    // --- Glare: elliptical highlight near top-right, warm tint ---
    let gx = (w * 0.8 - lx) / max(w, 1.0);
    let gy = (ly - h * 0.15) * 2.5 / max(h, 1.0);
    let gdist = sqrt(gx * gx * 0.6 + gy * gy);
    let glare = clamp(1.0 - gdist / 0.8, 0.0, 1.0);
    let glare = glare * glare * glare * 0.55;
    // Warm shift: push hue toward amber (70°) in glare zone
    let hue = mix(hue, 70.0, glare * 0.5);

    // --- Scanlines: faint darkening on alternating rows ---
    let scanline = if y % 2.0 < 1.0 { 0.97 } else { 1.0 };

    // --- Noise: pseudo-random per-cell grain ---
    let n = abs(((x * 12.9898 + y * 78.233) * 43758.5453) % 1.0);
    let noise = (n - 0.5) * 0.035;

    // --- Combine ---
    let nl = l * vignette * scanline + noise;

    if is_fg {
        let nc = c * 0.18;
        // Glare washes out toward white
        let nl = clamp(mix(nl, 1.0, glare), 0.0, 1.0);
        let nc = nc * (1.0 - glare);
        let rgb = oklch_to_rgb(nl, nc, hue);
        [clamp(rgb[0], 0.0, 255.0), clamp(rgb[1], 0.0, 255.0), clamp(rgb[2], 0.0, 255.0)]
    } else {
        let nc = c * 0.25;
        let nl = clamp(mix(nl, 0.85, glare), 0.0, 1.0);
        let nc = nc * (1.0 - glare * 0.8);
        let rgb = oklch_to_rgb(nl, nc, hue);
        [clamp(rgb[0], 0.0, 255.0), clamp(rgb[1], 0.0, 255.0), clamp(rgb[2], 0.0, 255.0)]
    }
}"#.to_string()
}

impl DimUnfocused {
    fn reload_shader(&mut self) {
        if let Some(ref path) = self.shader_file {
            let host_path = PathBuf::from("/host").join(path);
            if let Ok(contents) = std::fs::read_to_string(&host_path) {
                self.shader_script = contents;
                // Re-send to all currently dimmed panes
                for &(id, is_plugin) in &self.dimmed_panes {
                    let pane_id = if is_plugin {
                        PaneId::Plugin(id)
                    } else {
                        PaneId::Terminal(id)
                    };
                    set_pane_shader(pane_id, Some(self.shader_script.clone()));
                }
            }
        }
    }
}

impl ZellijPlugin for DimUnfocused {
    fn load(&mut self, configuration: BTreeMap<String, String>) {
        // If shader_file is set, load from file (with live-reload).
        // Otherwise use the built-in default shader.
        if let Some(path) = configuration.get("shader_file") {
            self.shader_file = Some(PathBuf::from(path));
        }

        self.shader_script = default_shader();

        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
        ]);
        subscribe(&[
            EventType::PaneUpdate,
            EventType::PermissionRequestResult,
            EventType::FileSystemUpdate,
            EventType::FileSystemCreate,
        ]);

        // Try loading from file (overrides default if present)
        self.reload_shader();

        if self.shader_file.is_some() {
            watch_filesystem();
        }
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::PermissionRequestResult(PermissionStatus::Granted) => {},
            Event::FileSystemUpdate(paths) | Event::FileSystemCreate(paths) => {
                if let Some(ref shader_path) = self.shader_file {
                    let host_path = PathBuf::from("/host").join(shader_path);
                    if paths.iter().any(|(p, _)| p == &host_path) {
                        self.reload_shader();
                    }
                }
            },
            Event::PaneUpdate(pane_manifest) => {
                let mut currently_visible: std::collections::HashSet<(u32, bool)> =
                    std::collections::HashSet::new();

                for (_tab_id, panes) in &pane_manifest.panes {
                    for pane in panes {
                        if pane.is_plugin || pane.is_suppressed {
                            continue;
                        }

                        let pane_key = (pane.id, pane.is_plugin);
                        currently_visible.insert(pane_key);
                        let pane_id = if pane.is_plugin {
                            PaneId::Plugin(pane.id)
                        } else {
                            PaneId::Terminal(pane.id)
                        };

                        if pane.is_focused {
                            if self.dimmed_panes.remove(&pane_key) {
                                set_pane_shader(pane_id, None);
                            }
                        } else if self.dimmed_panes.insert(pane_key) {
                            set_pane_shader(
                                pane_id,
                                Some(self.shader_script.clone()),
                            );
                        }
                    }
                }

                self.dimmed_panes.retain(|k| currently_visible.contains(k));
            },
            _ => {},
        }
        false
    }

    fn render(&mut self, _rows: usize, _cols: usize) {}
}
