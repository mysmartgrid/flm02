#!/usr/bin/env lua

--[[
    
    heartbeat.lua - send a heartbeat to the flukso server

    Copyright (C) 2008-2009 jokamajo.org
                  2011 Bart Van Der Meerssche <bart.vandermeerssche@flukso.net>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

]]--

if not arg[1] then
	print ('Please pass the reset argument as a boolean to the script.')
	os.exit(1)
end

local dbg        = require 'dbg'
local nixio      = require 'nixio'
nixio.fs         = require 'nixio.fs'
local uci        = require 'luci.model.uci'.cursor()
local luci       = {}
luci.sys         = require 'luci.sys'
luci.json        = require 'luci.json'
luci.util        = require 'luci.util'
local httpclient = require 'luci.httpclient'
local api        = require 'flukso.api'

-- character table string
local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

-- encoding
function enc(data)
	return ((data:gsub('.', function(x)
		local r,b='',x:byte()
		for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
		return r;
		end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
		if (#x < 6) then return '' end
		local c=0
		for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
		return b:sub(c+1,c+1)
		end)..({ '', '==', '=' })[#data%3+1])
end

-- decoding
function dec(data)
	data = string.gsub(data, '[^'..b..'=]', '')
	return (data:gsub('.', function(x)
		if (x == '=') then return '' end
		local r,f='',(b:find(x)-1)
		for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
		return r;
		end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
		if (#x ~= 8) then return '' end
		local c=0
		for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
		return string.char(c)
		end))
end

-- parse and load /etc/config/flukso
local FLUKSO		= uci:get_all('flukso')

-- WAN settings
local WAN_ENABLED	= (FLUKSO.daemon.enable_wan_branch == '1')
local UPGRADE_ENABLED = (FLUKSO.daemon.enable_remote_upgrade == '1')

local UPGRADE_URL	= FLUKSO.daemon.upgrade_url
local DOWNLOAD_URL      = FLUKSO.daemon.wan_base_url .. 'firmware/'
local SENSOR_URL	= FLUKSO.daemon.wan_base_url .. 'sensor/'

local SSL_NOT_YET_VALID = -150
local SSL_EXPIRED       = -151

-- gzipped syslog tmp file
local SYSLOG_TMP	= '/tmp/syslog.gz'
local SYSLOG_GZIP	= 'logread | gzip > ' .. SYSLOG_TMP

local function print_table(t)
	if t ~= nil then
		for k,v in pairs(t) do
			if (type(v) == "table") then
				print(k)
				print_table(v)
			else
				print(k,v)
			end
		end
	end
end

local function debug(value)
	local debug = true
	if (debug) then
		if (type(value) == 'table') then
			print_table(value)
		else
			print(value)
		end
	end
end

-- collect relevant monitoring points
local function collect_mp()
	local monitor = {}

	monitor.reset = tonumber(arg[1])
	-- monitor.version = tonumber(FLUKSO_VERSION)
	monitor.time = os.time()
	monitor.uptime  = math.floor(luci.sys.uptime())
	local sysinfo = nixio.sysinfo()
	monitor.memtotal = sysinfo.totalram
	monitor.memcached = sysinfo.sharedram
	monitor.membuffers = sysinfo.bufferram
	monitor.memfree = sysinfo.freeram

	os.execute(SYSLOG_GZIP)
	io.input(SYSLOG_TMP)
	local syslog_gz = io.read("*all")

	monitor.syslog = nixio.bin.b64encode(syslog_gz)

--	local defaultroute = luci.sys.net.defaultroute()
--	if defaultroute then
--		local device = defaultroute.device
--		monitor.ip = luci.util.exec("ifconfig " .. device):match("inet addr:([%d\.]*) ")
--		monitor.port = uci:get('uhttpd', 'restful', 'listen_http')[1]:match(":([%d]*)")
--	end

	return monitor
end

-- collect the parts of the network configuration that changed since the last run
local function collect_config()
	if uci:get("flukso", "daemon", "configchanged") == '0' then
		return
	end

	local LAN_CONFIG = uci:get_all("network", "lan")
	local WAN_CONFIG = uci:get_all("network", "wan")
	local wifidevs = {}
	uci:foreach("wireless", "wifi-iface", function(section) table.insert(wifidevs, section[".name"]) end)

	local config = {}
	config.lan = {}
	config.lan.enabled = (LAN_CONFIG.proto ~= "none") and 1 or 0
	config.lan.protocol = (LAN_CONFIG.proto ~= "none") and LAN_CONFIG.proto or undefined
	config.lan.ip = LAN_CONFIG.ipaddr
	config.lan.netmask = LAN_CONFIG.netmask
	config.lan.gateway = LAN_CONFIG.gateway
	config.lan.nameserver = LAN_CONFIG.dns
	config.wifi = {}
	config.wifi.essid = uci:get("wireless", wifidevs[1], "ssid")
	local enc = uci:get("wireless", wifidevs[1], "encryption")
	if enc == "none" then
		config.wifi.enc = "open"
	elseif enc == "wep" then
		config.wifi.enc = "wep"
	elseif enc == "psk" then
		config.wifi.enc = "wpa"
	elseif enc == "psk2" then
		config.wifi.enc = "wpa2"
	end
	config.wifi.psk = uci:get("wireless", wifidevs[1], "key")
	config.wifi.enabled = (WAN_CONFIG.proto ~= "none") and 1 or 0
	config.wifi.protocol = (WAN_CONFIG.proto ~= "none") and WAN_CONFIG.proto or undefined
	config.wifi.ip = WAN_CONFIG.ipaddr
	config.wifi.netmask = WAN_CONFIG.netmask
	config.wifi.gateway = WAN_CONFIG.gateway
	config.wifi.nameserver = WAN_CONFIG.dns
	local c = {}
	c.network = config
	return c
end

-- collect relevant firmware informations
local function collect_firmware()
   local FIRMWARE = uci:get_all('firmware', 'system')
--   for i, v in pairs(FIRMWARE) do
--      print('Firmware:', i, v)
--   end
   local firmware = {}
   firmware.tag         = FIRMWARE.tag
   firmware.build       = FIRMWARE.build
   firmware.version     = FIRMWARE.version
   firmware.releasetime = FIRMWARE.releasetime
   return firmware
end

-- download upgrade script (wget not ssl capable)
local function download_upgrade(upgrade)
   local headers = {}
   headers['X-Version'] = '1.0'
   headers['User-Agent'] = USER_AGENT
   headers['Connection'] = 'close'

   local options = {}
   options.sndtimeo = 5
   options.rcvtimeo = 5
   -- We don't enable peer cert verification so we can still update/upgrade
   -- the Fluksometer via the heartbeat call even when the cacert has expired.
   -- Disabling validation does mean that the server has to include an hmac
   -- digest in the reply that the Fluksometer needs to verify, this to prevent
   -- man-in-the-middle attacks.
   options.tls_context_set_verify = 'none'
   options.cacert = CACERT
   options.method  = 'GET'
   options.headers = headers

   local data = {}
   data.key = WAN_KEY
   options.body = luci.json.encode(data)

   local hash = nixio.crypto.hmac('sha1', WAN_KEY)
   hash:update(options.body)
   options.headers['X-Digest'] = hash:final()

   debug('cacert: ', CACERT)

   local httpclient = require 'luci.httpclient'
   local http_persist = httpclient.create_persistent()
   local url = DOWNLOAD_URL .. DEVICE
   local response_json, code, call_info = http_persist(url, options)

   if code == 200 then
      local response = luci.json.decode(response_json)     
      local file = assert(io.open("/tmp/upgrade.sh", "wb"))
      file:write(dec(response.data))
      file:close()
      os.execute('chmod a+x /tmp/upgrade.sh')
   else
      os.execute('/usr/bin/event 106')
      print('failed, code=', code)
      print('failed, info=', call_info)
      print('failed, resp=', response)
   end
end

local function check_network()
   debug("Check network configuration...")
   -- send a heartbeat
   local monitor = collect_mp()
   monitor.firmware = collect_firmware()
   monitor.type = "amperix1"

   local config = collect_config()
   if FLUKSO.daemon.wan_registered ~= '1' then
      monitor.key = WAN_KEY
   else
      if config ~= nil then
	 monitor.config = config
      end
   end

   local monitor_json = luci.json.encode(monitor)

   local headers = {}
   headers['Content-Type'] = 'application/json'
   headers['X-Version'] = '1.0'
   headers['User-Agent'] = USER_AGENT
   headers['Connection'] = 'close'
   local options = {}
   options.sndtimeo = 5
   options.rcvtimeo = 5
   options.tls_context_set_verify = 'peer'
   options.cacert = CACERT
   options.method  = 'POST'
   options.headers = headers
   options.body = luci.json.encode(monitor)

   local hash = nixio.crypto.hmac('sha1', WAN_KEY)
   hash:update(options.body)
   options.headers['X-Digest'] = hash:final()

   local http_persist = httpclient.create_persistent()
   local url = DEVICE_BASE_URL .. DEVICE
   local response_json, code, call_info = http_persist(url, options)
   debug("httprequest returned " .. code)
   local retval=true
   if code == 200 then
      -- network is working
      debug("Network ok.")
   else
      -- network is not working. Reset config
      debug("Network failed. Need to reset.")
      retval=false
   end
   return retval
end

local function reset_network()
   debug("Reseting network configuration...")
   local mac = uci:get("wireless", "radio0", "macaddr")
   os.execute('netstat -rn')
   os.execute('cp /rom/etc/config/firewall /etc/config/')
   os.execute('cp /rom/etc/config/network /etc/config/')
   os.execute('cp /rom/etc/config/wireless /etc/config/')
   uci:commit("wireless")
   if mac ~= nil then 
      debug("Macaddr is: ".. mac)
      uci:set("wireless", "radio0", "macaddr", mac)
      uci:commit("wireless")
   else
      debug("Macaddr was not found!")
   end
   uci:commit("network")
   uci:commit("wireless")
   uci:apply({"network", "wireless"})
   os.execute('netstat -rn')
   debug("Reseting network configuration done.")
end

local function get_sensor(sensor, idmap)
   debug("get_sensor(" .. sensor .. ", _)")
   local headers = {}
   headers['X-Version'] = '1.0'
   headers['User-Agent'] = USER_AGENT
   headers['Connection'] = 'close'

   local options = {}
   options.sndtimeo = 5
   options.rcvtimeo = 5
   -- We don't enable peer cert verification so we can still update/upgrade
   -- the Fluksometer via the heartbeat call even when the cacert has expired.
   -- Disabling validation does mean that the server has to include an hmac
   -- digest in the reply that the Fluksometer needs to verify, this to prevent
   -- man-in-the-middle attacks.
   options.tls_context_set_verify = 'none'
   options.cacert = CACERT
   options.method  = 'GET'
   options.headers = headers

   --local data = {}
   --data.key = WAN_KEY
   --options.body = luci.json.encode(data)

   local hash = nixio.crypto.hmac('sha1', WAN_KEY)
   --hash:update(options.body)
   options.headers['X-Digest'] = hash:final()

   local httpclient = require 'luci.httpclient'
   local http_persist = httpclient.create_persistent()
   local url = SENSOR_URL .. sensor
   local response_json, code, call_info = http_persist(url, options)

   if code == 200 then
      debug("Sensor response: " .. response_json)
      local response = luci.json.decode(response_json)[1]
      if response == nil then
        return 1
      end

      if response.config["function"] ~= "undefined" then
        debug("Sensor " .. idmap[sensor] .. " enabled as " .. response.config["function"])

        uci:set("flukso", idmap[sensor], "enable", 1)
        uci:set("flukso", idmap[sensor], "function", response.config["function"])
        --uci:set("flukso", idmap[sensor], "unit", response.config["unit"]) --not needed
        if response.config["class"] == "analog" then
          uci:set("flukso", idmap[sensor], "class", response.config["class"])
          uci:set("flukso", idmap[sensor], "voltage", response.config["voltage"])
          uci:set("flukso", idmap[sensor], "current", response.config["current"])
        elseif response.config["class"] == "pulse" then
          uci:set("flukso", idmap[sensor], "class", response.config["class"])
          uci:set("flukso", idmap[sensor], "constant", response.config["constant"])
        else
          print("Invalid response.")
          return 1
        end
        -- we do not want to enable reconfiguring of sensor ports. Aggregation can happen in the
        -- presentation layer.
        --if response.config["port"] ~= nil then
        --  uci:set_list("flukso", idmap[sensor], "phase", {response.config["port"]})
        --end
      else
        debug("Sensor " .. idmap[sensor] .. " disabled.")
        uci:set("flukso", idmap[sensor], "enable", 0)
      end
      uci:save("flukso")
      uci:commit("flukso")

      return 0
   else
      print("error, code=" .. code)
      print("error, call_info")
      print_table(call_info)
      return 1
   end
end

-- Register sensor at the server
local function register_sensors(http_persist, options)
	local MAX_PROV_SENSORS		= tonumber(FLUKSO.main.max_provisioned_sensors)
	for i = 1, MAX_PROV_SENSORS do
		if FLUKSO[tostring(i)] ~= nil and FLUKSO[tostring(i)].id then
			local sensor_id = FLUKSO[tostring(i)].id

			options.body = sensor_json(FLUKSO, tostring(i))
			options.headers['Content-Length'] = tostring(#options.body)

			local hash = nixio.crypto.hmac('sha1', WAN_KEY)
			hash:update(options.body)
			options.headers['X-Digest'] = hash:final()

			local url = SENSOR_BASE_URL .. sensor_id
			local response, code, call_info = http_persist(url, options)

			local level

			if code == 200 or code == 204 then
				level = 'info'
			else
				level = 'err'
				err = true
			end

			nixio.syslog(level, string.format('%s %s: %s', options.method, url, code))
			print(string.format('%s %s: %s', options.method, url, code))

			-- if available, send additional error info to the syslog
			if type(call_info) == 'string' then
				nixio.syslog('err', call_info)
				print(call_info)
			elseif type(call_info) == 'table'  then
				local auth_error = call_info.headers['WWW-Authenticate']

				if auth_error then
					nixio.syslog('err', string.format('WWW-Authenticate: %s', auth_error))
					print(string.format('WWW-Authenticate: %s', auth_error))
				end
			end
		end
	end
end

-- terminate when WAN reporting is not set
if not WAN_ENABLED then
	os.exit(2)
end

-- open the connection to the syslog deamon, specifying our identity
nixio.openlog('heartbeat', 'pid')

local monitor = collect_mp()
monitor.firmware = collect_firmware()
monitor.type = "amperix1"

local config = collect_config()
debug(config)
if FLUKSO.daemon.wan_registered ~= '1' then
  monitor.key = WAN_KEY
else
  if config ~= nil then
    monitor.config = config
  end
end

local monitor_json = luci.json.encode(monitor)

debug("Json: " .. monitor_json)


-- phone home
local headers = {}
headers['Content-Type'] = 'application/json'
headers['X-Version'] = '1.0'
headers['User-Agent'] = USER_AGENT
headers['Connection'] = 'close'

local options = {}
options.sndtimeo = 5
options.rcvtimeo = 5
-- We don't enable peer cert verification so we can still update/upgrade
-- the Fluksometer via the heartbeat call even when the cacert has expired.
-- Disabling validation does mean that the server has to include an hmac
-- digest in the reply that the Fluksometer needs to verify, this to prevent
-- man-in-the-middle attacks.
options.tls_context_set_verify = 'peer'
 options.cacert = CACERT
options.method  = 'POST'
options.headers = headers
options.body = luci.json.encode(monitor)

local hash = nixio.crypto.hmac('sha1', WAN_KEY)
hash:update(options.body)
options.headers['X-Digest'] = hash:final()

local http_persist = httpclient.create_persistent()
local url = DEVICE_BASE_URL .. DEVICE
local response_json, code, call_info = http_persist(url, options)

if code == 200 then
  nixio.syslog('info', string.format('%s %s: %s', options.method, url, code))
  uci:set('flukso', 'daemon', 'configchanged', 0)
  if FLUKSO.daemon.wan_registered ~= '1' then
    FLUKSO.daemon.wan_registered = 1
    uci:set('flukso', 'daemon', 'wan_registered', 1)
    uci:save("flukso")
    uci:commit("flukso")
    -- when we just registered the device we also have to inform all known sensors
    register_sensors(http_persist, options)
  end
  debug(FLUKSO.daemon)
elseif code == 481 then
  nixio.syslog('info', string.format('%s %s: %s', options.method, url, code))
else
  nixio.syslog('err', string.format('%s %s: %s', options.method, url, code))

        print('failed, code=', code)
        if type(call_info) == 'table' then
                print('failed, info=', print_table(call_info))
        elseif type(call_info) == 'string' then
                print('failed, info=', print(call_info))
        end
	if code == 404 then
		os.execute('/usr/bin/fsync')
	end
        print('failed, response=', response_json)

	-- SSL_EXPIRED: The certificate presented by the server is expired
	-- SSL_NOT_YET_VALID: The certificate presented by the server will be valid in the future but is not yet valid
	-- those two errors are most likely caused by an incorrect local time
	-- in all these cases we call ntpclient to synchronize our local time
	if code == SSL_NOT_YET_VALID or code == SSL_EXPIRED then
	nixio.syslog('info', 'trying to set correct time')
	local output = io.popen('ntpd -n -q -d -p pool.ntp.org')
	nixio.syslog('info', 'output of ntpd: ' .. output:read('*all'))
output:close()
	end

	-- if available, send additional error info to the syslog
	if type(call_info) == 'string' then
		nixio.syslog('err', call_info)
	elseif type(call_info) == 'table'  then
		local auth_error = call_info.headers['WWW-Authenticate']

		if auth_error then
			nixio.syslog('err', string.format('WWW-Authenticate: %s', auth_error))
		end
	end

	os.exit(3)
end

-- verify the reply's digest
hash = nixio.crypto.hmac('sha1', WAN_KEY)
hash:update(response_json)
if call_info.headers['X-Digest'] ~= hash:final() then
	nixio.syslog('err', 'Incorrect digest in the heartbeat reply. Discard response.')
	os.exit(4)
end

debug("Response_json: " .. response_json)
local response = luci.json.decode(response_json)

if response.support then
	local support = response.support
	md5 = nixio.crypto.hmac('md5', support.devicekey)
	hash = md5:final()

	debug(support)

	if not FLUKSO.support or FLUKSO.support.hash ~= hash then
		uci:set("flukso", "support", "mysmartgrid")
		uci:set("flukso", "support", "hash", hash)

		uci:set("flukso", "support", "tunnelPort", support.tunnelPort)
		uci:set("flukso", "support", "host", support.host)
		uci:set("flukso", "support", "port", support.port)
		uci:set("flukso", "support", "user", support.user)
		uci:set("flukso", "support", "hostkey", support.hostkey)
		uci:set("flukso", "support", "techkey", support.techkey)

		uci:save("flukso")
		uci:commit("flukso")

		os.execute("mkdir -p /root/.ssh")
		local file = assert(io.open("/root/.ssh/id_dss", "wb"))
		file:write(dec(support.devicekey))
		file:close()

		os.execute("/etc/init.d/reverse-ssh restart")
		os.execute("/etc/init.d/reverse-ssh enable")
        else
                os.execute("/etc/init.d/reverse-ssh start")
	end
else
	os.execute("/etc/init.d/reverse-ssh stop")
	os.execute("/etc/init.d/reverse-ssh disable")

	uci:delete("flukso", "support")
	uci:save("flukso")
	uci:commit("flukso")

	os.remove("/root/.ssh/id_dss")
end

debug("Response:")
debug(response.config)
-- TODO: sanity checks
if response.config then
	uci:set("flukso", "daemon", "configchanged", 1)
	uci:save("flukso")
	uci:commit("flukso")
	local system = uci:get_first('system','system')
	uci:set("system", system, "firstconfig", 0)
	uci:save("system")
	uci:commit("system")
	local config = response.config
	if config.network then
		debug("network found")
		local network = config.network
		if network.lan then
			if network.lan.enabled > 0 then
				debug("lan enabled")
				if network.lan.protocol == 'static' then
					debug("lan static")
					--parse further settings
					uci:set("network", "lan", "proto", "static")
					uci:set("network", "lan", "ipaddr", network.lan.ip)
					uci:set("network", "lan", "netmask", network.lan.netmask)
					uci:set("network", "lan", "gateway", network.lan.gateway)
					uci:set("network", "lan", "dns", network.lan.nameserver)
				elseif network.lan.protocol == 'dhcp' then
					debug("lan dhcp")
					--set protocol dhcp and remove the other fields
					uci:set("network", "lan", "proto", "dhcp")
					uci:delete("network", "lan", "ipaddr")
					uci:delete("network", "lan", "netmask")
					uci:delete("network", "lan", "gateway")
					uci:delete("network", "lan", "dns")
				else
					debug("lan protocol " .. network.lan.protocol .. " unknown")
					--unknown protocol
					uci:set("network", "lan", "proto", "none")
					uci:delete("network", "lan", "ipaddr")
					uci:delete("network", "lan", "netmask")
					uci:delete("network", "lan", "gateway")
					uci:delete("network", "lan", "dns")
				end
			else
				debug("lan disabled")
				--disable lan
				uci:set("network", "lan", "proto", "none")
				uci:delete("network", "lan", "ipaddr")
				uci:delete("network", "lan", "netmask")
				uci:delete("network", "lan", "gateway")
				uci:delete("network", "lan", "dns")
			end
			uci:save("network")
			uci:commit("network")
		end
		if network.wifi then
			debug("wifi found")
			local wifidevs = {}
			uci:foreach("wireless", "wifi-iface", function(section) table.insert(wifidevs, section[".name"]) end)
			if network.wifi.enabled > 0 then
				debug("wifi enabled")
				uci:set("wireless", "radio0", "disabled", 0)
				--set essid
				uci:set("wireless", wifidevs[1], "ssid", network.wifi.essid)
				--handle enc
				if network.wifi.enc == 'open' then
					uci:set("wireless", wifidevs[1], "encryption", "none")
					uci:delete("wireless", wifidevs[1], "key")
				elseif network.wifi.enc == 'wep' then
					uci:set("wireless", wifidevs[1], "encryption", "wep")
					uci:set("wireless", wifidevs[1], "key", network.wifi.psk)
				elseif network.wifi.enc == 'wpa' then
					uci:set("wireless", wifidevs[1], "encryption", "psk")
					uci:set("wireless", wifidevs[1], "key", network.wifi.psk)
				elseif network.wifi.enc == 'wpa2' then
					uci:set("wireless", wifidevs[1], "encryption", "psk2")
					uci:set("wireless", wifidevs[1], "key", network.wifi.psk)
				else
					--don't know what to do here
				end
				if network.wifi.protocol == 'static' then
					--parse further settings
					uci:set("network", "wan", "proto", "static")
					uci:set("network", "wan", "ipaddr", network.wifi.ip)
					uci:set("network", "wan", "netmask", network.wifi.netmask)
					uci:set("network", "wan", "gateway", network.wifi.gateway)
					uci:set("network", "wan", "dns", network.wifi.nameserver)
				elseif network.wifi.protocol == 'dhcp' then
					--set protocol dhcp and ignore the rest
					uci:set("network", "wan", "proto", "dhcp")
					uci:delete("network", "wan", "ipaddr")
					uci:delete("network", "wan", "netmask")
					uci:delete("network", "wan", "gateway")
					uci:delete("network", "wan", "dns")
				else
					--unknown protocol
					uci:set("network", "wan", "proto", "none")
					uci:delete("network", "wan", "ipaddr")
					uci:delete("network", "wan", "netmask")
					uci:delete("network", "wan", "gateway")
					uci:delete("network", "wan", "dns")
				end
			else
				debug("wifi disabled")
				--disable wifi
				uci:set("network", "wan", "proto", "none")
				uci:delete("network", "wan", "ipaddr")
				uci:delete("network", "wan", "netmask")
				uci:delete("network", "wan", "gateway")
				uci:delete("network", "wan", "dns")
				uci:set("wireless", "radio0", "disabled", 1)
				uci:delete("wireless", wifidevs[1], "ssid")
				uci:delete("wireless", wifidevs[1], "key")
				uci:delete("wireless", wifidevs[1], "encryption")
			end
			uci:save("network")
			uci:save("wireless")
			uci:commit("network")
			uci:commit("wireless")
		end
		uci:apply({"network", "wireless"})
		if( check_network() ) then
		   os.execute('/usr/bin/event 107')
		else
		   reset_network()
		   os.execute('/usr/bin/event 108')
		   os.exit(1)
		end
	end
	if config.sensors then
		local sensormap = {}
		uci:foreach("flukso", "sensor", function(x) sensormap[x['id']] = x['.name'] end)
		--for each sensor pull configuration via seperate API call -- do we want some kind of worker queue for this task?
		--afterwards call fsync to update the configuration (also on the sensor board) and inform the server of the new configuration
		for _, sensor in ipairs(config.sensors) do
			debug(sensor)
			if get_sensor(sensor, sensormap) > 0 then -- something went wrong, try again next time
				nixio.syslog('warning', string.format('Fetching settings for sensor %s failed.', sensor))
				print("Fetching setting for sensor " .. sensor .. " failed.")
			end
		end
		os.execute('/usr/bin/fsync')
	end
end

-- check whether we have to reset or upgrade
if response.upgrade > 0 then
   download_upgrade(response.upgrade)
   local retval  = os.execute('/tmp/upgrade.sh')
   if retval == 0 then
      os.execute('/usr/bin/event 105')
   else
      os.execute('/usr/bin/event 106')
   end
   os.execute('rm -f /tmp/upgrade.sh')
end
-- if response.upgrade == monitor.version then
-- 	os.execute('reboot')
-- elseif response.upgrade > monitor.version then
--    download_upgrade(response.upgrade)
--    os.execute('/tmp/upgrade.sh')
--    os.execute('rm -f /tmp/upgrade.sh')
-- end
