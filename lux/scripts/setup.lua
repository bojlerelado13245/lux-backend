-- scripts/setup.lua — runs once on server start
db:run([[
    CREATE TABLE IF NOT EXISTS users (
        id    INTEGER PRIMARY KEY AUTOINCREMENT,
        name  TEXT NOT NULL,
        email TEXT
    )
]])

print("[setup] users table ready")
