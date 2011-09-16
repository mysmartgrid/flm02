--[[
LuCI - Lua Configuration Interface

Copyright 2008 Steven Barth <steven@midlink.org>
Copyright 2008 Jo-Philipp Wich <xm@leipzig.freifunk.net>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: network.lua 4171 2009-01-27 20:50:28Z Cyrus $
]]--

f = SimpleForm("tryit", "Test Connection", "Trying to connect to the MySmartgrid server")

uci = luci.model.uci.cursor()

-- Temporary fix for the connection loss on apply
if uci:get("flukso", "events", "apply") == "1" then

	-- Get wireless interface
	wifidevs={}
	uci:foreach("wireless", "wifi-device",
	function(section)
		table.insert(wifidevs, section[".name"])
	end)

	if uci:get("network", "wan", "proto") == "none" then
		uci:set("wireless", wifidevs[1], "disabled", 1) -- Disable wireless interface
	else
		uci:delete("wireless", wifidevs[1], "disabled") -- Activate wireless interface
	end
	uci:save("wireless")
	uci:commit("wireless")
	uci:save("network")
	uci:commit("network")
	uci:apply({"wireless", "network"}) -- Apply changes
	uci:set("flukso", "events", "apply", 0) -- Don't apply next time
	uci:save("flukso")
	uci:commit("flukso")
end


function fsync() --run fsync and parse output
	local p = io.popen("/usr/bin/fsync")
	local result = {}
	for line in p:lines() do
		if line:sub(0,4) == "POST" then
			result["code"] = line:sub(-4):gsub(" ", "")
			message = p:read()
			if message ~= nil then
				result["message"] = message
			end
		end
	end
	p:close()
	return result
end

result = f:field(DummyValue, "", "")
function result.cfgvalue(self, section)
	local fsync = fsync()
	local code = tonumber(fsync["code"])
	if code == 200 then
		return "Verbindung zum Server erfolgreich hergestellt."
	--[[ 
	elseif code > 200 then --check if the problem is the server or the connection
		if fsync["message"] ~= nil then
			return "Fehler (" .. fsync["message"] .. " [" .. fsync["code"] .. "])"
		else
			return "Fehler (" .. fsync["message"] .. ")"
		end]]--
	else
		if fsync["message"] ~= nil then
			return "Es konnte keine Verbindung zum Server hergestellt werden (" .. fsync["message"] .. " [" .. fsync["code"] .. "])"
		else
			return "Es konnte keine Verbindung zum Server hergestellt werden (" .. fsync["code"] .. ")"
		end
	end
end

return f
