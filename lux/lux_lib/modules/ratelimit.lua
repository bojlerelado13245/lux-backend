-- ratelimit.lua — rate limiting module
local _limits = {}

ratelimit = function(ip)
    local _max = tonumber(_ratelimit_max) or 100
    local now  = os.time()
    ip = ip or "unknown"


    if not _limits[ip] then
        _limits[ip] = { count = 1, reset_at = now + 60 }
        return true
    end

    local data = _limits[ip]

    if now > data.reset_at then
        data.count    = 1
        data.reset_at = now + 60
        return true
    end

    if data.count >= _max then
        return false
    end

    data.count = data.count + 1
    return true
end
