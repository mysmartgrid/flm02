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
local luci       = require 'luci'
luci.sys         = require 'luci.sys'
luci.json        = require 'luci.json'
local httpclient = require 'luci.httpclient'

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

local WAN_BASE_URL	= FLUKSO.daemon.wan_base_url .. 'device/'
local WAN_KEY		= '0123456789abcdef0123456789abcdef'
uci:foreach('system', 'system', function(x) WAN_KEY = x.key end) -- quirky but it works

local DEVICE		= '0123456789abcdef0123456789abcdef'
uci:foreach('system', 'system', function(x) DEVICE = x.device end)

local UPGRADE_URL	= FLUKSO.daemon.upgrade_url

-- https header helpers
local FLUKSO_VERSION	= '000'
uci:foreach('system', 'system', function(x) FLUKSO_VERSION = x.version end)

local USER_AGENT	= 'Fluksometer v' .. FLUKSO_VERSION
local CACERT		= FLUKSO.daemon.cacert

-- gzipped syslog tmp file
local SYSLOG_TMP	= '/tmp/syslog.gz'
local SYSLOG_GZIP	= 'logread | gzip > ' .. SYSLOG_TMP

-- collect relevant monitoring points
local function collect_mp()
	local monitor = {}

	monitor.reset = tonumber(arg[1])
	monitor.version = tonumber(FLUKSO_VERSION)
	monitor.time = os.time()
	monitor.uptime  = math.floor(luci.sys.uptime())
	system, model, monitor.memtotal, monitor.memcached, monitor.membuffers, monitor.memfree = luci.sys.sysinfo()

	os.execute(SYSLOG_GZIP)
	io.input(SYSLOG_TMP)
	local syslog_gz = io.read("*all")

	monitor.syslog = nixio.bin.b64encode(syslog_gz)

	return monitor
end

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

-- terminate when WAN reporting is not set
if not WAN_ENABLED then
	os.exit(2)
end

-- open the connection to the syslog deamon, specifying our identity
nixio.openlog('heartbeat', 'pid')

local monitor = collect_mp()
monitor.firmware = collect_firmware()
local monitor_json = luci.json.encode(monitor)


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
local url = WAN_BASE_URL .. DEVICE
local response_json, code, call_info = http_persist(url, options)

if code == 200 then
	nixio.syslog('info', string.format('%s %s: %s', options.method, url, code))
else
	nixio.syslog('err', string.format('%s %s: %s', options.method, url, code))

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

local response = luci.json.decode(response_json)

if response.support then
	local support = response.support
	md5 = nixio.crypto.hmac('md5', support.devicekey)
	hash = md5:final()

	for i, v in pairs(support) do
		print(i, v)
	end

	if not FLUKSO.support or FLUKSO.support.hash ~= hash then
		uci:set("flukso", "support", "mysmartgrid")
		uci:set("flukso", "support", "hash", hash)

		uci:set("flukso", "support", "tunnelPort", support.tunnelPort)
		uci:set("flukso", "support", "host", support.host)
		uci:set("flukso", "support", "port", support.port)
		uci:set("flukso", "support", "user", support.user)
		uci:set("flukso", "support", "hostkey", support.hostkey)
		uci:set("flukso", "support", "techkey", support.techkey)

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
	uci:commit("flukso")

	os.remove("/root/.ssh/id_dss")
end

-- check whether we have to reset or upgrade
if response.upgrade == monitor.version then
	os.execute('reboot')
elseif response.upgrade > monitor.version then
	os.execute('wget -P /tmp ' .. UPGRADE_URL .. 'upgrade.' .. response.upgrade)
	os.execute('chmod a+x /tmp/upgrade.' .. response.upgrade)
	os.execute('/tmp/upgrade.' .. response.upgrade)
	os.execute('rm /tmp/upgrade.' .. response.upgrade)
end
