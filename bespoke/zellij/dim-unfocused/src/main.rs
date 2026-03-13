use std::collections::BTreeMap;
use zellij_tile::prelude::*;

#[derive(Default)]
struct DimUnfocused {
    dim_bg: String,
    dim_fg: String,
    dimmed_panes: std::collections::HashSet<(u32, bool)>,
}

const DEFAULT_DIM_BG: &str = "#1a1a1a";
const DEFAULT_DIM_FG: &str = "#808080";

register_plugin!(DimUnfocused);

impl ZellijPlugin for DimUnfocused {
    fn load(&mut self, configuration: BTreeMap<String, String>) {
        self.dim_bg = configuration
            .get("dim_bg")
            .cloned()
            .unwrap_or_else(|| DEFAULT_DIM_BG.to_string());
        self.dim_fg = configuration
            .get("dim_fg")
            .cloned()
            .unwrap_or_else(|| DEFAULT_DIM_FG.to_string());

        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
        ]);
        subscribe(&[
            EventType::PaneUpdate,
            EventType::PermissionRequestResult,
        ]);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::PermissionRequestResult(PermissionStatus::Granted) => {
                // Permissions granted — no action needed, PaneUpdate will fire
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
                                set_pane_color(pane_id, None, None);
                            }
                        } else {
                            self.dimmed_panes.insert(pane_key);
                            set_pane_color(
                                pane_id,
                                Some(self.dim_fg.clone()),
                                Some(self.dim_bg.clone()),
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
