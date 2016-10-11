#! /usr/bin/env lua

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
local httpclient = require 'luci.httpclient'

-- parse and load /etc/config/flukso
local FLUKSO		= uci:get_all('flukso')

-- WAN settings
local WAN_ENABLED	= (FLUKSO.daemon.enable_wan_branch == '1')

local WAN_BASE_URL	= FLUKSO.daemon.wan_base_url .. 'event/'
local WAN_KEY		= '0123456789abcdef0123456789abcdef'
uci:foreach('system', 'system', function(x) WAN_KEY = x.key end) -- quirky but it works

local DEVICE		= '0123456789abcdef0123456789abcdef'
uci:foreach('system', 'system', function(x) DEVICE = x.device end)

-- https header helpers
local FLUKSO_VERSION	= '000'
uci:foreach('system', 'system', function(x) FLUKSO_VERSION = x.version end)

local USER_AGENT	= 'Fluksometer v' .. FLUKSO_VERSION
local CACERT		= FLUKSO.daemon.cacert

-- send the event
local function send_event(event_id)
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
   options.method  = 'POST'
   options.headers = headers

   local data = {}
   data.device = DEVICE
   options.body = luci.json.encode(data)
   print('Device', options.body )

   local hash = nixio.crypto.hmac('sha1', WAN_KEY)
   hash:update(options.body)
   options.headers['X-Digest'] = hash:final()

   local httpclient = require 'luci.httpclient'
   local http_persist = httpclient.create_persistent()
   local url = WAN_BASE_URL .. event_id
   print('Url: ' ,  url)
   local response_json, code, call_info = http_persist(url, options)

   if code == 200 then
      nixio.syslog('info', string.format('%s %s: %s', options.method, url, code))
      print('OK')
   else
      nixio.syslog('err', string.format('%s %s: %s', options.method, url, code))
      print('Failed', code )
   end
end


-- terminate when WAN reporting is not set
if not WAN_ENABLED then
	os.exit(2)
end

send_event(arg[1])