use std::collections::BTreeMap;
use std::path::PathBuf;
use zellij_tile::prelude::*;

const SHADER_WASM: &[u8] = include_bytes!(env!("SHADER_WASM_PATH"));

struct DimUnfocused {
    shader_wasm: Vec<u8>,
    shader_file: Option<PathBuf>,
    dimmed_panes: std::collections::HashSet<(u32, bool)>,
}

impl Default for DimUnfocused {
    fn default() -> Self {
        Self {
            shader_wasm: Vec::new(),
            shader_file: None,
            dimmed_panes: std::collections::HashSet::new(),
        }
    }
}

register_plugin!(DimUnfocused);

impl DimUnfocused {
    fn reload_shader(&mut self) {
        if let Some(ref path) = self.shader_file {
            let host_path = PathBuf::from("/host").join(path);
            if let Ok(contents) = std::fs::read(&host_path) {
                self.shader_wasm = contents;
                // Re-send to all currently dimmed panes
                for &(id, is_plugin) in &self.dimmed_panes {
                    let pane_id = if is_plugin {
                        PaneId::Plugin(id)
                    } else {
                        PaneId::Terminal(id)
                    };
                    set_pane_shader(pane_id, Some(self.shader_wasm.clone()));
                }
            }
        }
    }
}

impl ZellijPlugin for DimUnfocused {
    fn load(&mut self, configuration: BTreeMap<String, String>) {
        // If shader_file is set, load from file (with live-reload).
        // Otherwise use the built-in compiled shader.
        if let Some(path) = configuration.get("shader_file") {
            self.shader_file = Some(PathBuf::from(path));
        }

        self.shader_wasm = SHADER_WASM.to_vec();

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
                // Every real (non-plugin) pane still present, INCLUDING collapsed
                // stack members. Since zellij 0.44's stack-list UI, collapsing a
                // stacked pane moves it into the server's suppressed_panes and it
                // reports is_suppressed=true while keeping whatever shader we last
                // set on it. If we dropped such a pane from `dimmed_panes` while it
                // was suppressed, then on re-expand-with-focus the remove() below
                // would return false, we'd skip the un-dim, and the now-active pane
                // would stay dark. So keep suppressed panes tracked and only prune a
                // key once its pane is actually gone (closed => absent from manifest).
                let mut present: std::collections::HashSet<(u32, bool)> =
                    std::collections::HashSet::new();

                for (_tab_id, panes) in &pane_manifest.panes {
                    for pane in panes {
                        if pane.is_plugin {
                            continue;
                        }

                        let pane_key = (pane.id, pane.is_plugin);
                        present.insert(pane_key);

                        // Collapsed stack members aren't rendered; leave their
                        // shader as-is (still tracked above) until they reappear.
                        if pane.is_suppressed {
                            continue;
                        }

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
                                Some(self.shader_wasm.clone()),
                            );
                        }
                    }
                }

                self.dimmed_panes.retain(|k| present.contains(k));
            },
            _ => {},
        }
        false
    }

    fn render(&mut self, _rows: usize, _cols: usize) {}
}
