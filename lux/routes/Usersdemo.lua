-- GET all users
get["/users"] (function(request)
    local users = request.db:all("SELECT * FROM users")
    return reply(200, users)
end)

-- GET one user
get["/users/:id"] (function(request)
    local user = request.db:one("SELECT * FROM users WHERE id = ?", request.params.id)
    if not user then
        return reply(404, "User not found")
    end
    return reply(200, user)
end)

-- CREATE user
post["/users"] (function(request)
    local name  = request.data.name
    local email = request.data.email

    if not name then
        return reply(400, "name is required")
    end

    request.db:run("INSERT INTO users (name, email) VALUES (?, ?)", name, email or "")
    local id   = request.db:last_id()
    local user = request.db:one("SELECT * FROM users WHERE id = ?", id)

    return reply(201, user)
end)

-- UPDATE user
put["/users/:id"] (function(request)
    local user = request.db:one("SELECT * FROM users WHERE id = ?", request.params.id)
    if not user then
        return reply(404, "User not found")
    end

    local name  = request.data.name  or user.name
    local email = request.data.email or user.email

    request.db:run(
        "UPDATE users SET name = ?, email = ? WHERE id = ?",
        name, email, request.params.id
    )

    local updated = request.db:one("SELECT * FROM users WHERE id = ?", request.params.id)
    return reply(200, updated)
end)

-- DELETE user
delete["/users/:id"] (function(request)
    local user = request.db:one("SELECT * FROM users WHERE id = ?", request.params.id)
    if not user then
        return reply(404, "User not found")
    end

    request.db:run("DELETE FROM users WHERE id = ?", request.params.id)
    return reply(200, "User deleted")
end)
