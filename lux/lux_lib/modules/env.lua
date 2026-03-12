env = {}

local file = io.open(".env", "r")
if not file then return end

for line in file:lines() do
    if line ~= "" and not line:match("^%s*#") then
        local key, value = line:match("^([^=]+)=(.+)$")
        if key and value then
            key   = key:match("^%s*(.-)%s*$")
            value = value:match("^%s*(.-)%s*$")
            env[key] = value
        end
    end
end

file:close()
