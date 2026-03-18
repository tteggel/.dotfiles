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
    // Distance from top-right corner, normalized
    // Cells are ~2x tall as wide, so scale y
    let dx = (w - x) / max(w, 1.0);
    let dy = y * 2.0 / max(h, 1.0);
    let dist = sqrt(dx * dx + dy * dy);

    // Glare: bright in top-right, fading with distance
    let glare = clamp(1.0 - dist / 0.8, 0.0, 1.0);
    let glare = glare * glare;

    let lch = rgb_to_oklch(r, g, b);
    let l = lch[0];
    let c = lch[1];
    let hue = lch[2];

    if is_fg {
        // Desaturate heavily (reduce chroma), preserve lightness
        let nc = c * 0.15;
        // Near glare: push lightness up (washed out by light)
        let nl = mix(l, 1.0, glare * 0.6);
        let rgb = oklch_to_rgb(nl, nc, hue);
        [clamp(rgb[0], 0.0, 255.0), clamp(rgb[1], 0.0, 255.0), clamp(rgb[2], 0.0, 255.0)]
    } else {
        // BG: desaturate partially, glare lifts lightness
        let nc = c * 0.3;
        let nl = mix(l, 0.8, glare * 0.5);
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
