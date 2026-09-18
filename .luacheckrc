std = "lua51"
codes = true

-- WoW addons intentionally read and define globals supplied by the game client,
-- Ace libraries, and other addons. Keep Luacheck focused on first-party Lua
-- correctness rather than requiring a large, fragile copy of the WoW API here.
ignore = {
    "111", -- setting a non-standard global variable
    "112", -- mutating a non-standard global variable
    "113", -- accessing an undefined variable
}

exclude_files = {
    "Libs/**",
}
