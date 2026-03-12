local wezterm = require 'wezterm'

local config = {}
if wezterm.config_builder then
  config = wezterm.config_builder()
end

config.wsl_domains = {
  {
    name = 'WSL:NixOS',
    distribution = 'NixOS',
  },
}
config.default_domain = 'WSL:NixOS'

config.font = wezterm.font 'ZedMono NF'
config.font_size = 11.0
config.color_scheme = 'OneDark (base16)'

-- Clean look: no title bar, just the tab bar
config.window_decorations = 'RESIZE'
config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = false

-- Padding
config.window_padding = {
  left = 4,
  right = 4,
  top = 4,
  bottom = 4,
}

-- Scrollback
config.scrollback_lines = 10000

-- No close confirmation
config.window_close_confirmation = 'NeverPrompt'

-- Start maximized
wezterm.on('gui-startup', function(cmd)
  local _, _, window = wezterm.mux.spawn_window(cmd or {})
  window:gui_window():maximize()
end)

-- Pane management is handled by Zellij — keep WezTerm keys minimal
config.keys = {}

return config
