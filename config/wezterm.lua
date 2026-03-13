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
config.colors = {
  selection_fg = '#282c34',
  selection_bg = '#61afef',
}

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

-- Hold Shift to bypass Zellij mouse capture for native WezTerm selection
config.bypass_mouse_reporting_modifiers = 'SHIFT'

-- No close confirmation
config.window_close_confirmation = 'NeverPrompt'

-- Disable win32 input mode (Windows default) so kitty keyboard protocol works
-- through the WSL domain — Zellij uses kitty protocol to distinguish Ctrl+Shift
config.allow_win32_input_mode = false
config.enable_kitty_keyboard = true

-- Start maximized
wezterm.on('gui-startup', function(cmd)
  local _, _, window = wezterm.mux.spawn_window(cmd or {})
  window:gui_window():maximize()
end)

-- Disable WezTerm's own Ctrl+Shift bindings so they pass through to Zellij
local act = wezterm.action
local passthrough = act.DisableDefaultAssignment
config.keys = {
  { key = 'h', mods = 'CTRL|SHIFT', action = passthrough },
  { key = 'j', mods = 'CTRL|SHIFT', action = passthrough },
  { key = 'k', mods = 'CTRL|SHIFT', action = passthrough },
  { key = 'l', mods = 'CTRL|SHIFT', action = passthrough },
  { key = 'n', mods = 'CTRL|SHIFT', action = passthrough },
  { key = 'w', mods = 'CTRL|SHIFT', action = passthrough },
  { key = 't', mods = 'CTRL|SHIFT', action = passthrough },
  { key = 'p', mods = 'CTRL|SHIFT', action = passthrough },
  { key = 's', mods = 'CTRL|SHIFT', action = passthrough },
  { key = 'g', mods = 'CTRL|SHIFT', action = passthrough },
  { key = 'q', mods = 'CTRL|SHIFT', action = passthrough },
  { key = 'z', mods = 'CTRL|SHIFT', action = passthrough },
  { key = '=', mods = 'CTRL|SHIFT', action = passthrough },
  { key = '-', mods = 'CTRL|SHIFT', action = passthrough },
  { key = '[', mods = 'CTRL|SHIFT', action = passthrough },
  { key = ']', mods = 'CTRL|SHIFT', action = passthrough },
  { key = '1', mods = 'CTRL|SHIFT', action = passthrough },
  { key = '2', mods = 'CTRL|SHIFT', action = passthrough },
  { key = '3', mods = 'CTRL|SHIFT', action = passthrough },
  { key = '4', mods = 'CTRL|SHIFT', action = passthrough },
  { key = '5', mods = 'CTRL|SHIFT', action = passthrough },
  { key = 'Space', mods = 'CTRL|SHIFT', action = passthrough },
}

return config
