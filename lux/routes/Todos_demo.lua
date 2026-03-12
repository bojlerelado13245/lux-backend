-- ─────────────────────────────────────────────
--  todos.lua — example route file
--  shows how to use lux routes, sqlite, and auth
-- ─────────────────────────────────────────────

-- GET /todos — list all todos
get["/todos"] (function(request)
    local todos = request.db:all("SELECT * FROM todos")
    return reply(200, todos)
end)
get["/todos/test/:id"] (function(request)
    return reply(200, "id is: " .. tostring(request.params.id))
end)
-- GET /todos/protected — requires a valid JWT token
-- header: Authorization: Bearer <token>
get["/todos/protected"] (auth(function(request)
    return reply(200, "Hello " .. request.user.user .. "! This route is protected.")
end))

-- GET /todos/:id — get one todo by id
get["/todos/:id"] (function(request)
    local todo = request.db:one("SELECT * FROM todos WHERE id = ?", tonumber(request.params.id))
    if not todo then
        return reply(404, "Todo not found")
    end
    return reply(200, todo)
end)

-- POST /todos — create a new todo
-- body: { "title": "Buy milk" }
post["/todos"] (function(request)
    local title = request.data.title
    if not title or title == "" then
        return reply(400, "title is required")
    end
    request.db:run("INSERT INTO todos (title, done) VALUES (?, 0)", title)
    local id = request.db:last_id()
    return reply(201, { id = id, title = title, done = false })
end)

-- PUT /todos/:id — mark a todo as done or not done
-- body: { "done": true }
put["/todos/:id"] (function(request)
    local todo = request.db:one("SELECT * FROM todos WHERE id = ?", tonumber(request.params.id))
    if not todo then
        return reply(404, "Todo not found")
    end
    local done = request.data.done and 1 or 0
    request.db:run("UPDATE todos SET done = ? WHERE id = ?", done, request.params.id)
    return reply(200, "updated")
end)

-- DELETE /todos/:id — delete a todo
delete["/todos/:id"] (function(request)
    local todo = request.db:one("SELECT * FROM todos WHERE id = ?", tonumber(request.params.id))
    if not todo then
        return reply(404, "Todo not found")
    end
    request.db:run("DELETE FROM todos WHERE id = ?", request.params.id)
    return reply(200, "deleted")
end)

-- POST /login — get a JWT token
-- body: { "username": "admin", "password": "1234" }
post["/login"] (function(request)
    local username = request.data.username
    local password = request.data.password

    -- in a real app, check the database instead
    if username == "admin" and password == "1234" then
        local token = jwt.sign({
            user = username,
            exp  = os.time() + 3600  -- expires in 1 hour
        })
        return reply(200, { token = token })
    end

    return reply(401, "Invalid credentials")
end)

