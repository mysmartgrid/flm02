--[[
LuCI - Lua Configuration Interface

Copyright 2008 Steven Barth <steven@midlink.org>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: system.lua 5472 2009-11-01 01:37:03Z jow $
]]--

require("luci.sys")
require("luci.sys.zoneinfo")
require("luci.tools.webadmin")


m = Map("system", translate("System"), translate("Here you can configure the basic aspects of your device like its hostname or the timezone."))

s = m:section(TypedSection, "system", "")
s.anonymous = true
s.addremove = false


local system, model, memtotal, memcached, membuffers, memfree = luci.sys.sysinfo()
local uptime = luci.sys.uptime()
local uci = luci.model.uci.cursor()

s:option(DummyValue, "_system", translate("System")).value = system
s:option(DummyValue, "_cpu", translate("Processor")).value = model

local load1, load5, load15 = luci.sys.loadavg()
s:option(DummyValue, "_la", translate("Load")).value =
 string.format("%.2f, %.2f, %.2f", load1, load5, load15)

s:option(DummyValue, "_memtotal", translate("Memory")).value =
 string.format("%.2f MB (%.0f%% %s, %.0f%% %s, %.0f%% %s)",
  tonumber(memtotal) / 1024,
  100 * memcached / memtotal,
  tostring(translate("cached")),
  100 * membuffers / memtotal,
  tostring(translate("buffered")),
  100 * memfree / memtotal,
  tostring(translate("free"))
)
 
s:option(DummyValue, "_systime", translate("m_i_systemtime")).value =
 os.date("%c")
 
s:option(DummyValue, "_uptime", translate("m_i_uptime")).value = 
 luci.tools.webadmin.date_format(tonumber(uptime))

s:option(DummyValue, "_hostname", translate("hostname")).value =                   
 luci.sys.hostname(value)                                                          

s:option(DummyValue, "_release", "Release").value =                   
   uci:get("firmware", "system", "version")
s:option(DummyValue, "_release", "Firmware-tag").value =                   
   uci:get("firmware", "system", "tag")
s:option(DummyValue, "_release", "Firmware-date").value =                   
   uci:get("firmware", "system", "releasetime")
s:option(DummyValue, "_release", "Firmware-release").value =
   uci:get("firmware", "system", "build")


-- Wifi Data init -- 
if not uci:get("network", "wan") then
	uci:section("network", "interface", "wan", {proto="none", ifname=" "})
	uci:save("network")
	uci:commit("network")
end

local wlcursor = luci.model.uci.cursor_state()
local wireless = wlcursor:get_all("wireless")
local wifidata = luci.sys.wifi.getiwconfig()
local wifidevs = {}
local ifaces = {}

for k, v in pairs(wireless) do
	if v[".type"] == "wifi-iface" then
		table.insert(ifaces, v)
	end
end

wlcursor:foreach("wireless", "wifi-device",
	function(section)
		table.insert(wifidevs, section[".name"])
	end)


-- Wifi Status Table --
s = m:section(Table, ifaces, translate("wifi"))

link = s:option(DummyValue, "_link", translate("link"))
function link.cfgvalue(self, section)
	local ifname = self.map:get(section, "ifname")
	return wifidata[ifname] and wifidata[ifname]["Link Quality"] or "-"
end

essid = s:option(DummyValue, "ssid", "ESSID")

bssid = s:option(DummyValue, "_bsiid", "BSSID")
function bssid.cfgvalue(self, section)
	local ifname = self.map:get(section, "ifname")
	return (wifidata[ifname] and (wifidata[ifname].Cell 
	 or wifidata[ifname]["Access Point"])) or "-"
end

protocol = s:option(DummyValue, "_mode", translate("protocol"))
function protocol.cfgvalue(self, section)
	local mode = wireless[self.map:get(section, "device")].mode
	return mode and "802." .. mode
end

mode = s:option(DummyValue, "mode", translate("mode"))
encryption = s:option(DummyValue, "encryption", translate("iwscan_encr"))

power = s:option(DummyValue, "_power", translate("power"))
function power.cfgvalue(self, section)
	local ifname = self.map:get(section, "ifname")
	return wifidata[ifname] and wifidata[ifname]["Tx-Power"] or "-"
end

scan = s:option(Button, "_scan", translate("scan"))
scan.inputstyle = "find"

function scan.cfgvalue(self, section)
	return self.map:get(section, "ifname") or false
end

s:option(DummyValue, "_systime", translate("Local Time")).value =
 os.date("%c")

s:option(DummyValue, "_uptime", translate("Uptime")).value =
 luci.tools.webadmin.date_format(tonumber(uptime))

hn = s:option(Value, "hostname", translate("Hostname"))

function hn.write(self, section, value)
	Value.write(self, section, value)
	luci.sys.hostname(value)
end


tz = s:option(ListValue, "zonename", translate("Timezone"))
tz:value("UTC")

for i, zone in ipairs(luci.sys.zoneinfo.TZ) do
        tz:value(zone[1])
end

function tz.write(self, section, value)
        local function lookup_zone(title)
                for _, zone in ipairs(luci.sys.zoneinfo.TZ) do
                        if zone[1] == title then return zone[2] end
                end
        end

        AbstractValue.write(self, section, value)
        self.map.uci:set("system", section, "timezone", lookup_zone(value) or "GMT0")
end

return m
