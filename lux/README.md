# lux

A stupidly simple Lua backend framework. Readable, fast, and easy to deploy.

```lua
get["/hello/:name"] (function(request)
    return reply(200, "Hello " .. request.params.name)
end)
```

---

## Why lux?

- Routes that read like English
- No boilerplate — just drop `.lua` files in `routes/`
- SQLite built in
- JWT auth in one line
- Auto-generated Swagger docs
- 21kb total — smaller than most images on a webpage

---

## Requirements

- Lua 5.4
- LuaRocks

---

## Installation

```bash
# 1. clone the repo
git clone https://github.com/yourusername/lux
cd lux

# 2. install dependencies
lua lux_lib/install.lua

# 3. set up your environment
cp .env.example .env
# edit .env and set JWT_SECRET to a random string

# 4. run
lua lux_lib/lux.lua
```

---

## Project structure

```
myproject/
├── lux_lib/
│   ├── lux.lua          ← framework core
│   ├── install.lua      ← dependency installer
│   └── modules/
│       ├── auth.lua     ← JWT auth
│       ├── env.lua      ← .env loader
│       ├── logger.lua   ← request logger
│       ├── ratelimit.lua ← rate limiting
│       └── sanitize.lua ← input sanitization
├── routes/
│   └── todos.lua        ← your routes go here
├── scripts/
│   └── setup.lua        ← runs on boot (db setup)
├── data/                ← sqlite database (auto created)
├── .env                 ← secrets (never commit this)
├── .env.example         ← template for .env
└── luxconfig.json       ← configuration
```

---

## Routes

Create any `.lua` file in `routes/` — it loads automatically.

```lua
get["/users"] (function(request)
    return reply(200, "list of users")
end)

post["/users"] (function(request)
    local name = request.data.name
    return reply(201, { name = name })
end)

get["/users/:id"] (function(request)
    local id = request.params.id
    return reply(200, "user " .. id)
end)

delete["/users/:id"] (function(request)
    return reply(200, "deleted")
end)
```

---

## Request object

```lua
request.params.id          -- URL param      /users/:id
request.query.search       -- query string   ?search=hello
request.data.name          -- JSON body      { "name": "john" }
request.body               -- raw body string
request.headers["x-token"] -- request header
request.db                 -- sqlite connection
request.user               -- JWT payload (only in auth() routes)
```

---

## Reply

```lua
reply(200, "plain text")
reply(200, { name = "john" })   -- auto JSON
reply(201, "created")
reply(400, "bad input")
reply(401, "not allowed")
reply(404, "not found")
reply(500, "server error")
```

---

## Database

```lua
-- run a query (insert, update, delete)
request.db:run("INSERT INTO users (name) VALUES (?)", name)

-- get all rows
local users = request.db:all("SELECT * FROM users")

-- get one row
local user = request.db:one("SELECT * FROM users WHERE id = ?", id)

-- get last inserted id
local id = request.db:last_id()
```

Create tables in `scripts/setup.lua` — runs once on boot:

```lua
db:run([[
    CREATE TABLE IF NOT EXISTS users (
        id   INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
    )
]])
```

---

## Auth

Add `JWT_SECRET` to your `.env`:

```
JWT_SECRET=your_random_secret_here
```

Login route — generate a token:

```lua
post["/login"] (function(request)
    if request.data.username == "admin" and request.data.password == "1234" then
        local token = jwt.sign({
            user = request.data.username,
            exp  = os.time() + 3600  -- 1 hour
        })
        return reply(200, { token = token })
    end
    return reply(401, "Invalid credentials")
end)
```

Protected route — requires a valid token:

```lua
get["/secret"] (auth(function(request)
    return reply(200, "Hello " .. request.user.user)
end))
```

Send token in the `Authorization` header:

```
Authorization: Bearer <token>
```

---

## Environment variables

Create a `.env` file in your project root:

```
JWT_SECRET=your_random_secret_here
APP_NAME=My App
```

Access anywhere in your routes:

```lua
local name = env.APP_NAME
```

---

## Configuration

`luxconfig.json` controls everything:

```json
{
    "port": 3000,
    "cors": true,
    "db": "data/app.sqlite",
    "swagger": true,
    "verbose": false,
    "rate_limit": 100,
    "log": "logs/app.log",
    "scripts": ["scripts/setup.lua"],
    "dependencies": ["http", "dkjson", "luaposix", "lsqlite3"]
}
```

| Key | Type | Description |
|---|---|---|
| `port` | number | Port to listen on |
| `cors` | bool | Enable CORS headers |
| `db` | string | Path to SQLite database |
| `swagger` | bool | Enable Swagger UI at `/docs` |
| `verbose` | bool | Show detailed boot logs |
| `rate_limit` | number | Max requests per minute per IP |
| `log` | string or true | Log to file or console only |
| `scripts` | array | Lua files to run on boot |
| `dependencies` | array | Packages to install |

---

## Swagger docs

Swagger UI is available at `http://localhost:3000/docs` when `swagger` is enabled. Opens automatically in your browser on startup.

---

## Production deployment

lux handles HTTP. For HTTPS in production, put Caddy in front:

```
# Caddyfile
myapp.com {
    reverse_proxy localhost:3000
}
```

Caddy handles SSL certificates automatically for free.

---

## License

MIT
