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

-- Keybindings for pane splitting and navigation
local act = wezterm.action
config.keys = {
  -- Pane splitting (Ctrl+Shift+| and Ctrl+Shift+_)
  { key = '|', mods = 'CTRL|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = '_', mods = 'CTRL|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },

  -- Pane navigation (Ctrl+Shift+arrow)
  { key = 'LeftArrow',  mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Left' },
  { key = 'RightArrow', mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Right' },
  { key = 'UpArrow',    mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Up' },
  { key = 'DownArrow',  mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Down' },

  -- Pane resize (Ctrl+Shift+Alt+arrow)
  { key = 'LeftArrow',  mods = 'CTRL|SHIFT|ALT', action = act.AdjustPaneSize { 'Left', 5 } },
  { key = 'RightArrow', mods = 'CTRL|SHIFT|ALT', action = act.AdjustPaneSize { 'Right', 5 } },
  { key = 'UpArrow',    mods = 'CTRL|SHIFT|ALT', action = act.AdjustPaneSize { 'Up', 5 } },
  { key = 'DownArrow',  mods = 'CTRL|SHIFT|ALT', action = act.AdjustPaneSize { 'Down', 5 } },

  -- Close pane (Ctrl+Shift+W)
  { key = 'w', mods = 'CTRL|SHIFT', action = act.CloseCurrentPane { confirm = false } },
}

return config
