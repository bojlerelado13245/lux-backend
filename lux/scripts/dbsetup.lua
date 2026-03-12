-- setup.lua — runs once on boot, creates tables
db:run([[
    CREATE TABLE IF NOT EXISTS todos (
        id    INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        done  INTEGER DEFAULT 0
    )
]])
print("[setup] todos table ready")
