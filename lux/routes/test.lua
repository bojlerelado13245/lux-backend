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
