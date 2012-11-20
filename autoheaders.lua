local ReadableStream = require('continuable').ReadableStream
local stringFormat = require('string').format
local osDate = require('os').date

return function (app)
  return function (req, res)
    if req.headers.expect == "100-continue" then
      req.socket:write("HTTP/1.1 100 Continue\r\n\r\n")()
    end
    app(req, function (code, headers, body)
      local hasDate = false
      local hasServer = false
      local hasContentLength = false
      local hasTransferEncoding = false
      for name in pairs(headers) do
        name = name:lower()
        if name == "date" then hasDate = true end
        if name == "server" then hasServer = true end
        if name == "content-length" then hasContentLength = true end
        if name == "transfer-encoding" then hasTransferEncoding = true end
      end
      if not hasDate then
        headers['Date'] = osDate("!%a, %d %b %Y %H:%M:%S GMT")
      end
      if not hasServer then
        headers['Server'] = "MoonSlice " .. _VERSION
      end
      if body and (not hasContentLength) and (not hasTransferEncoding) then
        if type(body) == "string" then
          headers["Content-Length"] = #body
          hasContentLength = true
        elseif type(body) == "table" then
          if type(body.read) ~= "function" then
            local length = 0
            for i, v in ipairs(body) do
              length = length + #v
            end
            headers["Content-Length"] = length
            hasContentLength = true
          else
            headers["Transfer-Encoding"] = "chunked"
            hasTransferEncoding = true
            local originalStream = body
            body = { done = false }
            function body:read() return function (callback)
              if self.done then
                return callback()
              end
              originalStream:read()(function (err, chunk)
                if err then return callback(err) end
                if chunk then
                  local length
                  if type(chunk) == "table" then
                    length = 0
                    for i, v in ipairs(body) do
                      length = length + #v
                    end
                  else
                    length = #chunk
                  end
                  return callback(nil, stringFormat("%X\r\n%s\r\n", length, chunk))
                end
                self.done = true
                callback(nil, "0\r\n\r\n\r\n")
              end)
            end end
          end
        end
      end
      if req.should_keep_alive and (hasContentLength or hasTransferEncoding or code == 304) then
        headers["Connection"] = "keep-alive"
      else
        headers["Connection"] = "close"
        req.should_keep_alive = false
      end
      res(code, headers, body)
    end)
  end
end
