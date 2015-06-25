#!/usr/bin/env lua

local uci        = require 'luci.model.uci'.cursor()

local function ntpd()
	local ntpserver = uci:get('system.ntp.server')

	if ntpserver ~= nil then
		server = "-p "
		server = server .. table.concat(ntpserver, " -p ")

		local output = io.popen('ntpd -n -q -d ' .. server)
		return(output)
	end
end
