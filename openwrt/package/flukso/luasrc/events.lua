#! /usr/bin/env lua

local nixio      = require 'nixio'
nixio.fs         = require 'nixio.fs'
local uci        = require 'luci.model.uci'.cursor()

-- parse and load /etc/config/flukso
local FLUKSO = uci:get_all('flukso')

local DAEMON 		= os.getenv('DAEMON') or 'fluksod'
local DAEMON_PATH 	= os.getenv('DAEMON_PATH') or '/var/run/' .. DAEMON

local CTRL_PATH	= '/var/run/spid/ctrl'
local CTRL_PATH_IN	= CTRL_PATH .. '/in'
local CTRL_PATH_OUT	= CTRL_PATH .. '/out'

local O_RDWR		= nixio.open_flags('rdwr')
local O_RDWR_NONBLOCK   = nixio.open_flags('rdwr', 'nonblock')
local O_RDWR_CREAT	= nixio.open_flags('rdwr', 'creat')

local POLLIN        = nixio.poll_flags('in')


function brownout_event()

	local WAN_ENABLED	= (FLUKSO.daemon.enable_wan_branch == '1')
	-- Terminate when WAN reporting is not set
	if not WAN_ENABLED then
		os.exit(2)
	end

	luci.json        = require 'luci.json'
	local httpclient = require 'luci.httpclient'

	local FLUKSO_VERSION = '000'
	uci:foreach('system', 'system', function(x) FLUKSO_VERSION = x.version end)

	local USER_AGENT	= 'Fluksometer v' .. FLUKSO_VERSION

	local DEVICE		= '0123456789abcdef0123456789abcdef'
	uci:foreach('system', 'system', function(x) DEVICE = x.device end)

	local WAN_KEY		= '0123456789abcdef0123456789abcdef'
	uci:foreach('system', 'system', function(x) WAN_KEY = x.key end) -- quirky but it works

	local WAN_BASE_URL  = FLUKSO.daemon.wan_base_url .. 'event/'

	local headers = {}
	headers['Content-Type'] = 'application/json'
	headers['X-Version'] = '1.0'
	headers['User-Agent'] = USER_AGENT
	headers['Connection'] = 'close'

	local event = {}
	event.id = 104

	local options = {}

	options.sndtimeo = 5
	options.rcvtimeo = 5

	
	options.tls_context_set_verify = 'none'

	options.method  = 'POST'
	options.headers = headers
	options.body = luci.json.encode(event)

	local hash = nixio.crypto.hmac('sha1', WAN_KEY)
	hash:update(options.body)
	options.headers['X-Digest'] = hash:final()

	local http_persist = httpclient.create_persistent()
	local url = WAN_BASE_URL .. DEVICE
	local response_json, code, call_info = http_persist(url, options)

	print(url)
	print(code)

	if code == 200 then
		nixio.syslog('info', string.format('%s %s: %s', options.method, url, code))
	else
		nixio.syslog('err', string.format('%s %s: %s', options.method, url, code))

		-- if available, send additional error info to the syslog
		if type(call_info) == 'string' then
			nixio.syslog('err', call_info)
			print(call_info)
		elseif type(call_info) == 'table'  then
			local auth_error = call_info.headers['WWW-Authenticate']
			print(auth_error)
			if auth_error then
				nixio.syslog('err', string.format('WWW-Authenticate: %s', auth_error))
			end
		end

		os.exit(3)
	end
end



local ctrl = { fdin = nixio.open(CTRL_PATH_IN, O_RDWR_NONBLOCK),
	fdout = nixio.open(CTRL_PATH_OUT, O_RDWR) }

ctrl.fdin:write('gb\n')

local count
for line in ctrl.fdout:linesource() do
	print(line)
	if line:find("gb") then
		count = tonumber(line:sub(4))
		break
	end
end

--local oldcount = uci:get("flukso", "main", "brownouts")
local oldcount = FLUKSO.events.brownouts
print(tonumber(oldcount))
if oldcount == nil then
	uci:set("flukso", "events", "brownouts", count) -- Set initial brownout count

	uci:save("flukso")
	uci:commit("flukso")
	uci:apply({"flukso"}) -- Apply changes

elseif tonumber(oldcount) < count then
	brownout_event()
	uci:set("flukso", "events", "brownouts", count) -- Set new brownout count

	uci:save("flukso")
	uci:commit("flukso")
	uci:apply({"flukso"}) -- Apply changes
end


print(count)
