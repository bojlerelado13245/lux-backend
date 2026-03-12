get["/env-test"] (function(request)
    if not env then
        return reply(500, "env table is nil")
    end
    if not env.APP_NAME then
        return reply(500, "APP_NAME is nil")
    end
    return reply(200, env.APP_NAME)
end)
get["/test"] (function(request)
    return reply(200, "basic test works")
end)
-- login: generates a token
post["/login"] (function(request)
    local username = request.data.username
    local password = request.data.password

    -- normally you'd check the db here
    if username == "admin" and password == "1234" then
        local token = jwt.sign({
            user = username,
            exp  = os.time() + 3600  -- expires in 1 hour
        })
        return reply(200, { token = token })
    end

    return reply(401, "Invalid credentials")
end)

-- protected: only works with a valid token
get["/protected"] (auth(function(request)
    return reply(200, "Hello " .. request.user.user .. ", you are authenticated!")
end))
