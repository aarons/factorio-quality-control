-- Luacheck configuration for Factorio mod development
-- Based on Nexela's Factorio-luacheckrc configuration

std = "lua53c"

-- Factorio-specific globals that are defined by the game
globals = {
    -- Factorio API globals
    "defines",
    "data",
    "settings",
    "log",
    "localised_print",
    "table_size",
    "serpent",
    "util",
    "mods",

    -- Event system
    "script",
    "remote",
    "commands",

    -- Control stage only
    "global",
    "storage",
    "game",
    "rendering",
    "rcon",
    
    -- Factorio 2.0 prototypes access
    "prototypes",

    -- Data stage only
    "data",
    "settings",

    -- Common Factorio utility functions
    "table",
    "math",
    "string",
}

-- Read-only globals
read_globals = {
    -- Standard Lua libraries that Factorio provides
    "table",
    "math",
    "string",
    "debug",
    "coroutine",
    "utf8",
    "package",
    "io",
    "os",

    -- Factorio specific read-only
    "defines",
    "data",
    "settings",
    "log",
    "localised_print",
    "table_size",
    "serpent",
    "util",
    "mods",
    "script",
    "remote",
    "commands",
    "global",
    "game",
    "rendering",
    "rcon",
    "prototypes",
}

-- Files to ignore
exclude_files = {
    "archive/",
    "*.zip",
}

-- Specific rules
ignore = {
    "211", -- Unused local variable (common in event handlers)
    "213", -- Unused loop variable
    "412", -- Redefining argument (common pattern in Factorio)
    "421", -- Shadowing local variable (common in nested functions)
    "431", -- Shadowing upvalue (acceptable in many cases)
    "432", -- Shadowing upvalue argument
}

-- Max line length
max_line_length = 360

-- Max complexity (increased to accommodate complex game logic)
max_cyclomatic_complexity = 30