-- lux.lua — core framework (lua-http engine)
local server  = require("http.server")
local headers = require("http.headers")
local json    = require("dkjson")

-- graceful shutdown (unix only, skipped on windows)
local ok_signal, signal = pcall(require, "posix.signal")
if ok_signal then
    signal.signal(signal.SIGINT, function()
        print("\n\27[90m  goodbye\27[0m\n")
        os.exit(0)
    end)
end

-- ── Private state ──────────────────────────────────
local _routes = {}
local _config = {}
local _db     = nil

-- ── Colors ─────────────────────────────────────────
local c = {
    reset   = "\27[0m",
    bold    = "\27[1m",
    green   = "\27[32m",
    cyan    = "\27[36m",
    yellow  = "\27[33m",
    red     = "\27[31m",
    white   = "\27[97m",
    gray    = "\27[90m",
}

-- ── Logger ─────────────────────────────────────────
local function log(msg)
    if _config.verbose then
        print(c.gray .. "  › " .. c.reset .. msg)
    end
end

local function warn(msg)
    print(c.yellow .. "  ⚠ " .. c.reset .. msg)
end

local function err(msg)
    print(c.red .. "  ✗ " .. c.reset .. msg)
end

-- ── Banner ─────────────────────────────────────────
local function print_banner(port)
    print("")
    print(c.cyan .. c.bold ..
    "  ██╗     ██╗   ██╗██╗  ██╗\n" ..
    "  ██║     ██║   ██║╚██╗██╔╝\n" ..
    "  ██║     ██║   ██║ ╚███╔╝ \n" ..
    "  ██║     ██║   ██║ ██╔██╗ \n" ..
    "  ███████╗╚██████╔╝██╔╝ ██╗\n" ..
    "  ╚══════╝ ╚═════╝ ╚═╝  ╚═╝"
    .. c.reset)
    print("")
    print(c.white .. c.bold .. "  ready  " .. c.reset .. c.gray .. "→  " .. c.reset .. c.green .. "http://localhost:" .. port .. c.reset)
    if _config.swagger then
        print(c.white .. c.bold .. "  docs   " .. c.reset .. c.gray .. "→  " .. c.reset .. c.green .. "http://localhost:" .. port .. "/docs" .. c.reset)
    end
    if _db then
        print(c.white .. c.bold .. "  db     " .. c.reset .. c.gray .. "→  " .. c.reset .. c.green .. _config.db .. c.reset)
    end
    if _config.rate_limit then
        print(c.white .. c.bold .. "  limit  " .. c.reset .. c.gray .. "→  " .. c.reset .. c.white .. _config.rate_limit .. " req/min" .. c.reset)
    end
    if _config.log then
        local log_target = type(_config.log) == "string" and _config.log or "console"
        print(c.white .. c.bold .. "  log    " .. c.reset .. c.gray .. "→  " .. c.reset .. c.white .. log_target .. c.reset)
    end
    print(c.white .. c.bold .. "  routes " .. c.reset .. c.gray .. "→  " .. c.reset .. c.white .. #_routes .. " loaded" .. c.reset)
    if _config.cors then
        print(c.white .. c.bold .. "  cors   " .. c.reset .. c.gray .. "→  " .. c.reset .. c.white .. "enabled" .. c.reset)
    end
    print("")
end

-- ── JSON config reader ─────────────────────────────
local function read_config()
    local file = io.open("luxconfig.json", "r")
    if not file then
        warn("no luxconfig.json found, using defaults")
        return { port = 3000, cors = false, swagger = true, verbose = false }
    end
    local content = file:read("*a")
    file:close()
    local config      = {}
    config.port       = tonumber(content:match('"port"%s*:%s*(%d+)'))
    config.cors       = content:match('"cors"%s*:%s*true') ~= nil
    config.db         = content:match('"db"%s*:%s*"([^"]+)"')
    config.swagger    = content:match('"swagger"%s*:%s*false') == nil
    config.verbose    = content:match('"verbose"%s*:%s*true') ~= nil
    config.rate_limit = tonumber(content:match('"rate_limit"%s*:%s*(%d+)'))
    local log_path    = content:match('"log"%s*:%s*"([^"]+)"')
    local log_bool    = content:match('"log"%s*:%s*true')
    config.log        = log_path or (log_bool and true) or false
    config.scripts    = {}
    for script in content:gmatch('"(scripts/[^"]+%.lua)"') do
        config.scripts[#config.scripts + 1] = script
    end
    if config.db == "" then config.db = nil end
    return config
end

-- ── SQLite setup ───────────────────────────────────
local function setup_db(path)
    local ok, sqlite = pcall(require, "lsqlite3")
    if not ok then
        err("lsqlite3 not installed — run: luarocks install lsqlite3")
        return nil
    end
    local folder = path:match("^(.+)/[^/]+$")
    if folder then os.execute("mkdir -p " .. folder) end
    local dbconn = sqlite.open(path)
    log("db connected: " .. path)
    return {
        run = function(_, query, ...)
            local stmt = dbconn:prepare(query)
            if not stmt then return nil, dbconn:errmsg() end
            local args = { ... }
            if #args > 0 then stmt:bind_values(table.unpack(args)) end
            stmt:step()
            stmt:finalize()
            return true
        end,
        all = function(_, query, ...)
            local stmt = dbconn:prepare(query)
            if not stmt then return nil, dbconn:errmsg() end
            local args = { ... }
            if #args > 0 then stmt:bind_values(table.unpack(args)) end
            local rows = {}
            for row in stmt:nrows() do rows[#rows + 1] = row end
            stmt:finalize()
            return rows
        end,
        one = function(_, query, ...)
            local stmt = dbconn:prepare(query)
            if not stmt then return nil, dbconn:errmsg() end
            local args = { ... }
            if #args > 0 then stmt:bind_values(table.unpack(args)) end
            local row = stmt:nrows()(stmt)
            stmt:finalize()
            return row
        end,
        last_id = function(_)
            return dbconn:last_insert_rowid()
        end,
    }
end

-- ── Route verbs ────────────────────────────────────
local function make_verb(method)
    return setmetatable({}, {
        __index = function(_, path)
            return function(handler)
                table.insert(_routes, {
                    method  = method,
                    path    = path,
                    handler = handler
                })
            end
        end
    })
end

get    = make_verb("GET")
post   = make_verb("POST")
put    = make_verb("PUT")
delete = make_verb("DELETE")
patch  = make_verb("PATCH")

-- ── Reply ──────────────────────────────────────────
reply = function(status, body)
    if type(body) == "table" then
        return { status = status, body = json.encode(body), content_type = "application/json" }
    end
    return { status = status, body = tostring(body or ""), content_type = "text/plain" }
end

-- ── Path matcher ───────────────────────────────────
local function escape_pattern(s)
    return s:gsub("([%-%.%+%[%]%(%)%$%^%%%?%*])", "%%%1")
end

local function match_route(pattern, actual)
    local keys = {}
    local escaped = escape_pattern(pattern)
    local regex = escaped:gsub("%%:(%w+)", function(key)
        keys[#keys + 1] = key
        return "([^/]+)"
    end)
    local values = { actual:match("^" .. regex .. "$") }
    if #values == 0 then return nil end
    local params = {}
    for i, key in ipairs(keys) do params[key] = values[i] end
    return params
end

-- ── Query string parser ────────────────────────────
local function parse_query(path)
    local clean, qs = path:match("^([^?]*)%??(.*)")
    local query = {}
    if qs then
        for k, v in qs:gmatch("([^&=]+)=([^&=]+)") do
            query[k] = v
        end
    end
    return clean, query
end

-- ── Swagger spec builder ───────────────────────────
local function build_swagger(port)
    local paths = {}
    for _, route in ipairs(_routes) do
        local path = route.path:gsub(":(%w+)", "{%1}")
        if not paths[path] then paths[path] = {} end
        local method = route.method:lower()
        local params = {}
        for param in route.path:gmatch(":(%w+)") do
            params[#params + 1] = {
                name     = param,
                ["in"]   = "path",
                required = true,
                schema   = { type = "string" }
            }
        end
        paths[path][method] = {
            summary    = method:upper() .. " " .. path,
            parameters = params,
            responses  = {
                ["200"] = { description = "OK" },
                ["400"] = { description = "Bad Request" },
                ["404"] = { description = "Not Found" },
                ["500"] = { description = "Server Error" },
            }
        }
        if method == "post" or method == "put" or method == "patch" then
            paths[path][method].requestBody = {
                content = { ["application/json"] = { schema = { type = "object" } } }
            }
        end
    end
    return json.encode({
        openapi = "3.0.0",
        info    = { title = "lux API", version = "1.0.0" },
        servers = { { url = "http://localhost:" .. port } },
        paths   = paths,
    })
end

-- ── Swagger UI ─────────────────────────────────────
local function swagger_html(port)
    return [[<!DOCTYPE html>
<html>
<head>
    <title>lux — API Docs</title>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist/swagger-ui.css">
    <style>body { margin: 0; }</style>
</head>
<body>
<div id="swagger-ui"></div>
<script src="https://unpkg.com/swagger-ui-dist/swagger-ui-bundle.js"></script>
<script>
    SwaggerUIBundle({
        url: "/docs/spec",
        dom_id: "#swagger-ui",
        presets: [SwaggerUIBundle.presets.apis, SwaggerUIBundle.SwaggerUIStandalonePreset],
        layout: "BaseLayout",
        deepLinking: true,
    })
</script>
</body>
</html>]]
end

-- ── Route scanner ──────────────────────────────────
local function load_routes()
    local handle = io.popen("ls routes/*.lua 2>/dev/null")
    if not handle then return end
    for file in handle:lines() do
        local name = file:match("([^/]+)%.lua$")
        log("loading route: " .. name)
        dofile(file)
    end
    handle:close()
end

-- ── Open browser ───────────────────────────────────
local function open_browser(url)
    local os_name = io.popen("uname -s 2>/dev/null"):read("*l")
    if os_name == "Darwin" then
        os.execute("open " .. url)
    elseif os_name == "Linux" then
        os.execute("xdg-open " .. url .. " 2>/dev/null")
    else
        os.execute("start " .. url)
    end
end

-- ── Boot ───────────────────────────────────────────
_config = read_config()

-- env module
local env_file = io.open(".env", "r")
if env_file then
    env_file:close()
    dofile("lux_lib/modules/env.lua")
    log("env loaded")
end

-- rate limit module
if _config.rate_limit then
    _ratelimit_max = _config.rate_limit
    dofile("lux_lib/modules/ratelimit.lua")
    log("rate limit: " .. _config.rate_limit .. " req/min")
end

-- logger module
if _config.log then
    _log_target = _config.log
    dofile("lux_lib/modules/logger.lua")
    log("logging enabled")
end

-- sanitize module (always loaded)
dofile("lux_lib/modules/sanitize.lua")

-- database
if _config.db and _config.db ~= "" then
    _db = setup_db(_config.db)
end

-- startup scripts
if _config.scripts and #_config.scripts > 0 then
    if not _db then
        log("skipping scripts: no database configured")
    else
        for _, script in ipairs(_config.scripts) do
            local file = io.open(script, "r")
            if file then
                file:close()
                log("running script: " .. script)
                local fn, errmsg = loadfile(script)
                if fn then
                    db = _db
                    fn()
                else
                    err("script error in " .. script .. ": " .. tostring(errmsg))
                end
            else
                warn("script not found: " .. script)
            end
        end
    end
end

-- routes
load_routes()

local port = _config.port or 3000

local srv = server.listen {
    host = "localhost",
    port = port,

    onstream = function(_, stream)
        local start_time  = os.clock()
        local req_headers = stream:get_headers()
        local method      = req_headers:get(":method")
        local full_path   = req_headers:get(":path") or "/"
        local path, query = parse_query(full_path)

        local hdrs = {}
        for name, value in req_headers:each() do
            if name:sub(1,1) ~= ":" then hdrs[name:lower()] = value end
        end

        local body = stream:get_body_as_string() or ""

        local data = {}
        if hdrs["content-type"] and hdrs["content-type"]:find("application/json") then
            local decoded = json.decode(body)
            if decoded then data = decoded end
        end

        -- sanitize all input
        data   = sanitize_input(data)
        query  = sanitize_input(query)

        local request = {
            method  = method,
            path    = path,
            query   = query,
            headers = hdrs,
            body    = body,
            data    = data,
            params  = {},
            db      = _db,
        }

        local function send(res)
            local res_headers = headers.new()
            res_headers:append(":status",      tostring(res.status or 200))
            res_headers:append("content-type", res.content_type or "text/plain")
            if _config.cors then
                res_headers:append("access-control-allow-origin",  "*")
                res_headers:append("access-control-allow-methods", "GET, POST, PUT, DELETE, PATCH, OPTIONS")
                res_headers:append("access-control-allow-headers", "Content-Type, Authorization, X-Token")
            end
            stream:write_headers(res_headers, false)
            stream:write_chunk(res.body or "", true)
            if logger then
                local ms = math.floor((os.clock() - start_time) * 1000)
                logger(method, path, res.status, ms)
            end
        end

        -- cors preflight
        if method == "OPTIONS" and _config.cors then
            send(reply(204, ""))
            return
        end

        -- rate limiting
        if ratelimit then
            local ip = req_headers:get("x-forwarded-for")
                    or req_headers:get("x-real-ip")
                    or "unknown"
            local ok_peer, peer = pcall(function()
                return select(2, stream.connection:peername())
            end)
            if ok_peer and peer then ip = peer end
            if not ratelimit(ip) then
                send(reply(429, "Too many requests, slow down"))
                return
            end
        end

        -- swagger
        if _config.swagger then
            if method == "GET" and path == "/docs" then
                send({ status = 200, body = swagger_html(port), content_type = "text/html" })
                return
            end
            if method == "GET" and path == "/docs/spec" then
                send({ status = 200, body = build_swagger(port), content_type = "application/json" })
                return
            end
        end

        -- match routes
        local handled = false
        for _, route in ipairs(_routes) do
            if route.method == method then
                local params = match_route(route.path, path)
                if params then
                    request.params = sanitize_input(params)
                    local ok, res = pcall(route.handler, request)
                    if ok then
                        send(res)
                    else
                        send(reply(500, "Error: " .. tostring(res)))
                    end
                    handled = true
                    break
                end
            end
        end

        if not handled then
            send(reply(404, "Not found"))
        end
    end
}

print_banner(port)
srv:listen()

if _config.swagger then
    open_browser("http://localhost:" .. port .. "/docs")
end

srv:loop()
