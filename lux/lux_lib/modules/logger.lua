-- logger.lua — request logger
local _log_file = nil

if _log_target and type(_log_target) == "string" then
    local folder = _log_target:match("^(.+)/[^/]+$")
    if folder then os.execute("mkdir -p " .. folder) end
    _log_file = io.open(_log_target, "a")
end

logger = function(method, path, status, ms)
    local time = os.date("%Y-%m-%d %H:%M:%S")
    local line = "[" .. time .. "] " .. method .. " " .. path .. " " .. tostring(status) .. " " .. ms .. "ms"
    print(line)
    if _log_file then
        _log_file:write(line .. "\n")
        _log_file:flush()
    end
end
