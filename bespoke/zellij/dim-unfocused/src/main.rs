use std::collections::BTreeMap;
use zellij_tile::prelude::*;

#[derive(Default)]
struct DimUnfocused {
    dim_bg: String,
    dim_fg: String,
    dimmed_panes: std::collections::HashSet<(u32, bool)>,
}

register_plugin!(DimUnfocused);

fn parse_hex(s: &str) -> Option<(u8, u8, u8)> {
    let s = s.strip_prefix('#')?;
    if s.len() != 6 {
        return None;
    }
    let r = u8::from_str_radix(&s[0..2], 16).ok()?;
    let g = u8::from_str_radix(&s[2..4], 16).ok()?;
    let b = u8::from_str_radix(&s[4..6], 16).ok()?;
    Some((r, g, b))
}

fn to_hex(r: u8, g: u8, b: u8) -> String {
    format!("#{:02x}{:02x}{:02x}", r, g, b)
}

/// Blend color toward target by factor (0.0 = original, 1.0 = target)
fn blend(color: (u8, u8, u8), target: (u8, u8, u8), factor: f32) -> (u8, u8, u8) {
    let lerp = |a: u8, b: u8| -> u8 {
        (a as f32 + (b as f32 - a as f32) * factor).round() as u8
    };
    (lerp(color.0, target.0), lerp(color.1, target.1), lerp(color.2, target.2))
}

impl ZellijPlugin for DimUnfocused {
    fn load(&mut self, configuration: BTreeMap<String, String>) {
        let fg = configuration.get("fg").map(|s| s.as_str()).unwrap_or("#dcdfe4");
        let bg = configuration.get("bg").map(|s| s.as_str()).unwrap_or("#282c34");
        let dim: f32 = configuration.get("dim")
            .and_then(|s| s.parse().ok())
            .unwrap_or(0.4);

        let fg_rgb = parse_hex(fg).unwrap_or((220, 223, 228));
        let bg_rgb = parse_hex(bg).unwrap_or((40, 44, 52));

        // Dim fg: blend toward bg (wash out text)
        let dimmed_fg = blend(fg_rgb, bg_rgb, dim);
        // Dim bg: darken by blending toward black
        let dimmed_bg = blend(bg_rgb, (0, 0, 0), dim * 0.5);

        self.dim_fg = to_hex(dimmed_fg.0, dimmed_fg.1, dimmed_fg.2);
        self.dim_bg = to_hex(dimmed_bg.0, dimmed_bg.1, dimmed_bg.2);

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
            Event::PermissionRequestResult(PermissionStatus::Granted) => {},
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
