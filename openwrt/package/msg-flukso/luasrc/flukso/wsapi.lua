local nixio      = require 'nixio'
nixio.fs         = require 'nixio.fs'
local json       = require 'luci.json'

local setmetatable = setmetatable
local coroutine = coroutine
local unpack = unpack
local string = string
local table = table
local print = print
local os = os

module("wsapi")

local POLLIN            = nixio.poll_flags('in')

local function start_ws_proxy(config)
	local cmdline = "lua-ws-wrapper "
		.. "--host " .. config.url .. " "
		.. "--port " .. config.port .. " "
		.. "--user " .. config.user .. " "
		.. "--device " .. config.device .. " "
		.. "--key 0x" .. config.key .. " "
		.. "--fork "
		.. "--capath " .. config.cacert .. " "
		.. config.in_fifo .. " " .. config.out_fifo
	return os.execute(cmdline) == 0
end

local function ws_client_handler(config, sock)
	while true do
		sock.valid = false
		while not start_ws_proxy(config) do
			coroutine.yield(nil, "servfail")
		end
		sock.valid = true

		local fd_in = nixio.open(config.in_fifo, nixio.open_flags('wronly'))
		local fd_out = nixio.open(config.out_fifo, nixio.open_flags('rdonly', 'nonblock'))

		nixio.poll(nil, 1500)

		local fd_out_lines = fd_out:linesource()

		config.fds = {
			["in"]  = fd_in,
			["out"] = fd_out,
		}

		local arg, wait_for_eol = nil, nil

		arg, wait_for_eol = coroutine.yield()

		while true do
			if arg == nil then
				local line, err = fd_out_lines()
				if not line and not err then
					yield(nil, nil)
					break
				end
				local servfail = false
				while not servfail and not line and (err == nixio.const.EAGAIN or err == nixio.const.EINTR) and wait_for_eol do
					local pollfd = { { fd = fd_out, events = POLLIN, revents = 0 } }
					local res, err = nixio.poll(pollfd, 10000)
					if res == 0 then
						servfail = true
					elseif res == 1 then
						line, err = fd_out_lines()
					end
				end
				if not servfail then
					arg, wait_for_eol = coroutine.yield(line, err)
				else
					break
				end
			else
				local written, err = fd_in:writeall(arg .. "\n")
				if err then
					written = nil
					break
				end
				arg, wait_for_eol = coroutine.yield(written, err)
			end
		end

		fd_in:close()
		fd_out:close()
	end
end

local ws_client_ops = {}

function ws_client_ops.read(self, wait_for_eol)
	return self[".handler"](nil, wait_for_eol)
end

function ws_client_ops.write(self, line)
	return self[".handler"](line)
end

function ws_client_ops.process_command(self, command)
end

function ws_client_ops.wait_for_response(self)
	while true do
		local line, err = self:read(true)
		if line == nil then
			return line, err
		end
		line = json.decode(line)
		if line.cmd then
			self:process_command(line)
		elseif line.error then
			return nil, line.error
		else
			return line, err
		end
	end
end

function ws_client_ops.send_command(self, command, args)
	local data = {
		cmd = command,
		args = args,
	}
	local written, err = self:write(json.encode(data))
	if not written then
		return nil, err
	end
	return self:wait_for_response()
end

function ws_client_ops.new_update_value_command(self, sensor_id)
	local buffer = {
		head = string.format('{"cmd":"update","args":{"values":{%s:[', json.encode(sensor_id)),
		tail = ']}}}',
		values = {},
		ws = self,
	}
	buffer.size = #buffer.head + #buffer.tail

	return setmetatable(buffer, {
		__index = {
			append = function(self, timestamp, value)
				if not timestamp or not value then
					return true
				end

				local jvalue = json.encode({timestamp * 1000, value})
				if self.size + #jvalue + 1 >= 4096 then
					return false
				end
				self.values[#self.values + 1] = jvalue
				self.size = self.size + #jvalue + 1
				return true
			end,
			combine = function(self)
				return self.head .. table.concat(self.values, ",") .. self.tail
			end,
			run = function(self)
				local written, err = self.ws:write(self:combine())
				if not written then
					return nil, err
				end
				return self.ws:wait_for_response()
			end
		}
	})
end

function new_device_client(url, port, user, device, key, cacert, in_fifo, out_fifo)
	nixio.fs.mkfifo(in_fifo, '644')
	nixio.fs.mkfifo(out_fifo, '644')

	local config = {
		url      = url,
		port     = port,
		user     = user,
		device   = device,
		key      = key,
		cacert   = cacert,
		in_fifo  = in_fifo,
		out_fifo = out_fifo,
		fds      = {},
	}

	local sock = {
		input_fd = function(self)
			return config.fds.out
		end,
		[".handler"] = coroutine.wrap(ws_client_handler),
	}

	sock[".handler"](config, sock)

	return setmetatable(sock, {
		__index = ws_client_ops,
	})
end

return {
	new_device_client = new_device_client,
}
