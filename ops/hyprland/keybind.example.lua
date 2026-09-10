-- Omarchy Quake Panel — sample Hyprland keybind for the kiosk/second-screen toggle.
-- Calls the same IPC target ops/omarchy-menu.example.jsonc's menu entry and
-- ops/bin/omarchy-quake-panel-toggle use — see shell/Service.qml's IpcHandler.
--
-- Merge this bind into your own ~/.config/hypr/bindings.lua (or wherever your other
-- `hl.bind` calls live) with whatever modifier/key combination you actually want; SUPER+F9
-- is just an example, not a reserved Omarchy shortcut.

hl.bind({
  mods = "SUPER",
  key = "F9",
  action = "exec, omarchy-shell -q quake-panel toggleMode",
  description = "Toggle Quake Panel between kiosk and second-screen mode",
})
