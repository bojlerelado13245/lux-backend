-- auth.lua — pure Lua JWT implementation (HS256)
local _, json_lib = pcall(require, "dkjson")

-- ── SHA-256 ────────────────────────────────────────
local function sha256(msg)
    local K = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    }

    local function rrot(x, n) return ((x >> n) | (x << (32 - n))) & 0xffffffff end

    local bytes = {}
    for i = 1, #msg do bytes[i] = msg:byte(i) end

    local len = #bytes
    bytes[len + 1] = 0x80
    while #bytes % 64 ~= 56 do bytes[#bytes + 1] = 0 end

    local bitlen = len * 8
    for i = 7, 0, -1 do
        bytes[#bytes + 1] = (bitlen >> (i * 8)) & 0xff
    end

    local h = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    }

    for i = 1, #bytes, 64 do
        local w = {}
        for j = 0, 15 do
            w[j] = (bytes[i+j*4] << 24) | (bytes[i+j*4+1] << 16) | (bytes[i+j*4+2] << 8) | bytes[i+j*4+3]
        end
        for j = 16, 63 do
            local s0 = rrot(w[j-15],7) ~ rrot(w[j-15],18) ~ (w[j-15] >> 3)
            local s1 = rrot(w[j-2],17) ~ rrot(w[j-2],19)  ~ (w[j-2] >> 10)
            w[j] = (w[j-16] + s0 + w[j-7] + s1) & 0xffffffff
        end

        local a,b,c,d,e,f,g,hh = h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8]

        for j = 0, 63 do
            local S1    = rrot(e,6) ~ rrot(e,11) ~ rrot(e,25)
            local ch    = (e & f) ~ (~e & 0xffffffff & g)
            local temp1 = (hh + S1 + ch + K[j+1] + w[j]) & 0xffffffff
            local S0    = rrot(a,2) ~ rrot(a,13) ~ rrot(a,22)
            local maj   = (a & b) ~ (a & c) ~ (b & c)
            local temp2 = (S0 + maj) & 0xffffffff
            hh=g; g=f; f=e
            e = (d + temp1) & 0xffffffff
            d=c; c=b; b=a
            a = (temp1 + temp2) & 0xffffffff
        end

        h[1]=(h[1]+a)&0xffffffff; h[2]=(h[2]+b)&0xffffffff
        h[3]=(h[3]+c)&0xffffffff; h[4]=(h[4]+d)&0xffffffff
        h[5]=(h[5]+e)&0xffffffff; h[6]=(h[6]+f)&0xffffffff
        h[7]=(h[7]+g)&0xffffffff; h[8]=(h[8]+hh)&0xffffffff
    end

    local result = ""
    for i = 1, 8 do
        result = result .. string.format("%08x", h[i])
    end
    return result
end

-- ── HMAC-SHA256 ────────────────────────────────────
local function hmac256(key, msg)
    local block = 64
    if #key > block then
        local hex = sha256(key)
        local bin = ""
        for i = 1, #hex, 2 do bin = bin .. string.char(tonumber(hex:sub(i,i+1), 16)) end
        key = bin
    end
    while #key < block do key = key .. "\0" end

    local ipad, opad = "", ""
    for i = 1, block do
        local b = key:byte(i)
        ipad = ipad .. string.char(b ~ 0x36)
        opad = opad .. string.char(b ~ 0x5c)
    end

    local inner_hex = sha256(ipad .. msg)
    local inner_bin = ""
    for i = 1, #inner_hex, 2 do
        inner_bin = inner_bin .. string.char(tonumber(inner_hex:sub(i,i+1), 16))
    end

    return sha256(opad .. inner_bin)
end

-- ── Base64url ──────────────────────────────────────
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function b64encode(s)
    local result = ""
    local pad = (3 - #s % 3) % 3
    s = s .. string.rep("\0", pad)
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i+2)
        local n = (a << 16) | (b << 8) | c
        result = result
            .. b64chars:sub((n >> 18) + 1,        (n >> 18) + 1)
            .. b64chars:sub(((n >> 12) & 63) + 1, ((n >> 12) & 63) + 1)
            .. b64chars:sub(((n >> 6)  & 63) + 1, ((n >> 6)  & 63) + 1)
            .. b64chars:sub((n & 63) + 1,          (n & 63) + 1)
    end
    result = result:sub(1, #result - pad)
    return result:gsub("+", "-"):gsub("/", "_"):gsub("=", "")
end

local function b64decode(s)
    s = s:gsub("-", "+"):gsub("_", "/")
    local pad = (4 - #s % 4) % 4
    s = s .. string.rep("=", pad)
    local result = ""
    for i = 1, #s, 4 do
        local a = b64chars:find(s:sub(i,i),   1, true) - 1
        local b = b64chars:find(s:sub(i+1,i+1), 1, true) - 1
        local c = b64chars:find(s:sub(i+2,i+2), 1, true) - 1
        local d = b64chars:find(s:sub(i+3,i+3), 1, true) - 1
        local n = (a << 18) | (b << 12) | (c << 6) | d
        result = result
            .. string.char((n >> 16) & 0xff)
            .. string.char((n >> 8)  & 0xff)
            .. string.char(n & 0xff)
    end
    return result:sub(1, #result - pad)
end

-- ── JWT secret ─────────────────────────────────────
local _secret = (_config and _config.jwt_secret)
             or (env and env.JWT_SECRET)
             or nil

-- ── Sign token ─────────────────────────────────────
local function jwt_encode(payload)
    local header  = b64encode('{"alg":"HS256","typ":"JWT"}')
    local body    = b64encode(json_lib.encode(payload))
    local sig_hex = hmac256(_secret, header .. "." .. body)
    local sig_bin = ""
    for i = 1, #sig_hex, 2 do
        sig_bin = sig_bin .. string.char(tonumber(sig_hex:sub(i,i+1), 16))
    end
    return header .. "." .. body .. "." .. b64encode(sig_bin)
end

-- ── Verify token ───────────────────────────────────
local function jwt_decode(token)
    if not token then return nil, "no token" end
    local header, body, sig = token:match("^([^.]+)%.([^.]+)%.([^.]+)$")
    if not header then return nil, "invalid token format" end

    local sig_hex = hmac256(_secret, header .. "." .. body)
    local sig_bin = ""
    for i = 1, #sig_hex, 2 do
        sig_bin = sig_bin .. string.char(tonumber(sig_hex:sub(i,i+1), 16))
    end
    local expected = b64encode(sig_bin)
    if expected ~= sig then return nil, "invalid signature" end

    local payload = json_lib.decode(b64decode(body))
    if not payload then return nil, "invalid payload" end

    if payload.exp and os.time() > payload.exp then
        return nil, "token expired"
    end

    return payload
end

-- ── Public API ─────────────────────────────────────
jwt = {
    sign   = jwt_encode,
    verify = jwt_decode,
}

-- ── auth() route wrapper ───────────────────────────
auth = function(handler)
    return function(request)
        if not _secret then
            return reply(500, "JWT_SECRET not set in .env or luxconfig.json")
        end
        local token = request.headers["authorization"]
        if token then token = token:match("^Bearer (.+)$") end
        if not token then token = request.query.token end
        if not token then
            return reply(401, "Unauthorized: no token provided")
        end
        local payload, err = jwt_decode(token)
        if not payload then
            return reply(401, "Unauthorized: " .. (err or "invalid token"))
        end
        request.user = payload
        return handler(request)
    end
end
