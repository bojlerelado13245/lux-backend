-- install.lua — lux dependency installer

-- ── detect OS ──────────────────────────────────────
local function get_os()
    local sep = package.config:sub(1,1)
    if sep == "\\" then return "windows" end
    local f = io.popen("uname -s 2>/dev/null")
    if not f then return "windows" end
    local result = f:read("*l")
    f:close()
    if result == "Darwin" then return "mac" end
    return "linux"
end

local OS = get_os()
print("[lux] detected OS: " .. OS)

-- ── read luxconfig.json ────────────────────────────
local file = io.open("luxconfig.json", "r")
if not file then
    print("[lux] error: luxconfig.json not found")
    print("[lux] make sure you run this from your project root")
    os.exit(1)
end

local content = file:read("*a")
file:close()

-- ── parse dependencies ─────────────────────────────
local deps = {}
local deps_str = content:match('"dependencies"%s*:%s*%[(.-)%]')
if deps_str then
    for dep in deps_str:gmatch('"([^"]+)"') do
        deps[#deps + 1] = dep
    end
end

if #deps == 0 then
    print("[lux] no dependencies found in luxconfig.json")
    os.exit(0)
end

print("[lux] installing " .. #deps .. " dependencies...\n")

-- ── skip on windows (luaposix is unix only) ────────
local skip_on_windows = {
    ["luaposix"] = true,
}

-- ── install each dep ───────────────────────────────
local failed  = {}
local skipped = {}

for _, dep in ipairs(deps) do
    if OS == "windows" and skip_on_windows[dep] then
        print("[lux] skipping " .. dep .. " (unix only)")
        skipped[#skipped + 1] = dep
    else
        io.write("[lux] installing " .. dep .. "... ")
        io.flush()

        local cmd    = "luarocks install " .. dep .. " 2>&1"
        local handle = io.popen(cmd)
        local output = handle:read("*a")
        handle:close()

        if output:find("already installed") then
            print("already installed")
        elseif output:find("Error") or output:find("error") then
            print("failed")
            print("       " .. output:match("[^\n]+"))
            failed[#failed + 1] = dep
        else
            print("done")
        end
    end
end

-- ── sqlite special case on mac ─────────────────────
if OS == "mac" then
    local handle = io.popen("lua -e \"require('lsqlite3')\" 2>&1")
    local result = handle:read("*a")
    handle:close()
    if result:find("symbol not found") or result:find("error") then
        print("\n[lux] fixing lsqlite3 for macOS...")
        local sqlite_dir = io.popen("brew --prefix sqlite 2>/dev/null"):read("*l")
        if sqlite_dir then
            os.execute("luarocks install lsqlite3 SQLITE_DIR=" .. sqlite_dir .. " --force 2>&1")
            print("[lux] lsqlite3 fixed")
        else
            print("[lux] install sqlite via homebrew first: brew install sqlite")
        end
    end
end

-- ── summary ────────────────────────────────────────
print("")
if #failed == 0 and #skipped == 0 then
    print("[lux] all dependencies installed successfully")
    print("[lux] you can now run: lua lux_lib/lux.lua")
elseif #failed == 0 then
    print("[lux] all dependencies installed (" .. #skipped .. " skipped for your OS)")
    print("[lux] you can now run: lua lux_lib/lux.lua")
else
    print("[lux] " .. #failed .. " dependencies failed to install:")
    for _, dep in ipairs(failed) do
        print("       luarocks install " .. dep)
    end
    print("[lux] install them manually and try again")
end
