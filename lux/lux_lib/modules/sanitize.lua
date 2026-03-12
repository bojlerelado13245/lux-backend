-- sanitize.lua — input sanitization
local function sanitize(val)
    if type(val) == "string" then
        val = val:gsub("%z", "")
        val = val:gsub("&", "&amp;")
        val = val:gsub("<", "&lt;")
        val = val:gsub(">", "&gt;")
        val = val:gsub('"', "&quot;")
        val = val:gsub("'", "&#39;")
        return val
    end
    if type(val) == "table" then
        local clean = {}
        for k, v in pairs(val) do
            clean[k] = sanitize(v)
        end
        return clean
    end
    return val
end

sanitize_input = sanitize
