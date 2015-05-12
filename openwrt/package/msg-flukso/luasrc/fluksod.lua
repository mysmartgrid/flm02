#! /usr/bin/env lua

--[[
    
    fluksod.lua - Lua part of the Flukso daemon

    Copyright (C) 2013 Bart Van Der Meerssche <bart@flukso.net>

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


local dbg        = require 'dbg'
local nixio      = require 'nixio'
nixio.fs         = require 'nixio.fs'
local uci        = require 'luci.model.uci'.cursor()
local json       = require 'luci.json'
local httpclient = require 'luci.httpclient'
local data       = require 'flukso.data'
local ntp        = require 'flukso.ntpd'
local wsapi      = require 'flukso.wsapi'
local buffer     = require 'flukso.buffer'

require 'nixio.util'

-- parse and load /etc/config/flukso
local FLUKSO            = uci:get_all('flukso')

local arg = arg or {} -- needed when this code is not loaded via the interpreter

local DEBUG             = (arg[1] == '-d')
local LOGMASK           = FLUKSO.daemon.logmask or 'info'
nixio.setlogmask(LOGMASK)

local DAEMON            = os.getenv('DAEMON') or 'fluksod'
local DAEMON_PATH       = os.getenv('DAEMON_PATH') or '/var/run/' .. DAEMON
local WS_IN             = DAEMON_PATH .. '/ws_in'
local WS_OUT            = DAEMON_PATH .. '/ws_out'

local DELTA_PATH        = '/var/run/spid/delta'
local DELTA_PATH_IN     = DELTA_PATH .. '/in'
local DELTA_PATH_OUT    = DELTA_PATH .. '/out'

local O_RDWR            = nixio.open_flags('rdwr')
local O_RD_NONBLOCK     = nixio.open_flags('rdonly', 'nonblock')
local O_WR              = nixio.open_flags('wronly')
local O_RDWR_NONBLOCK   = nixio.open_flags('rdwr', 'nonblock')
local O_RDWR_CREAT      = nixio.open_flags('rdwr', 'creat')

local POLLIN            = nixio.poll_flags('in')
local POLLHUP           = nixio.poll_flags('hup')

-- set WAN parameters
local WAN_ENABLED       = (FLUKSO.daemon.enable_wan_branch == '1')

local MAX_TIME_OFFSET   = 300
local SSL_NOT_YET_VALID = -150
local SSL_EXPIRED       = -151
local API_TIME_ERROR    = 470
local TIMESTAMP_MIN     = 1234567890
local WAN_INTERVAL      = 300

local DEVICE		= '0123456789abcdef0123456789abcdef'
uci:foreach('system', 'system', function(x) DEVICE = x.device end)

local WAN_BASE_URL      = FLUKSO.daemon.wan_base_url .. 'sensor/'
local WAN_KEY           = '0123456789abcdef0123456789abcdef'
uci:foreach('system', 'system', function(x) WAN_KEY = x.key end) -- quirky but it works

-- https headers
local FLUKSO_VERSION    = '000'
uci:foreach('system', 'system', function(x) FLUKSO_VERSION = x.version end) -- quirky but it works, again

local USER_AGENT        = 'Fluksometer v' .. FLUKSO_VERSION
local CACERT            = FLUKSO.daemon.cacert

-- set LAN parameters
local LAN_ENABLED       = (FLUKSO.daemon.enable_lan_branch == '1')

local LAN_INTERVAL      = 0
local LAN_POLISH_CUTOFF	= 60
local LAN_PUBLISH_PATH	= DAEMON_PATH .. '/sensor'

local LAN_FACTOR = {
	['electricity']     =      3.6e6, -- 1 Wh/ms = 3.6e6 W
	['water']           = 24 * 3.6e6, -- 1 L/ms  = 24 * 3.6e6 L/day
	['gas']             = 24 * 3.6e6  -- 1 L/ms  = 24 * 3.6e6 L/day
}

local LAN_ID_TO_FACTOR  = { }
uci:foreach('flukso', 'sensor', function(x) LAN_ID_TO_FACTOR[x.id] = LAN_FACTOR[x['type']] end)

local LAN_UNIT = {
	['electricity']     = { counter = 'Wh', gauge =     'W' },
	['water']           = { counter =  'L', gauge = 'L/day' },
	['gas']             = { counter =  'L', gauge = 'L/day' }
}

local LAN_ID_TO_UNIT = { }
uci:foreach('flukso', 'sensor', function(x) LAN_ID_TO_UNIT[x.id] = LAN_UNIT[x['type']] end)

local WS_CONFIG = { }
uci:foreach('flukso', 'api', function(x)
	WS_CONFIG.url = x['server']
	WS_CONFIG.port = x['port']
	WS_CONFIG.user = x['user']
	WS_CONFIG.cacert = x['cacert']
end)

function resume(...)
	local status, err = coroutine.resume(...)

	if not status then
		error(err, 0)
	end
end

local ws = wsapi.new_device_client(WS_CONFIG.url, WS_CONFIG.port, WS_CONFIG.user, DEVICE, WAN_KEY, WS_CONFIG.cacert, WS_IN, WS_OUT)

local function dispatch(wan_child, lan_child)
	return coroutine.create(function()
		local delta = { fdin  = nixio.open(DELTA_PATH_IN, O_RDWR_NONBLOCK),
		                fdout = nixio.open(DELTA_PATH_OUT, O_RDWR_NONBLOCK) }

		if delta.fdin == nil or delta.fdout == nil then
			nixio.syslog('alert', 'cannot open the delta fifos')
			os.exit(1)
		end

		-- acquire an exclusive lock on the delta fifos or exit
		if not (delta.fdin:lock('tlock') and delta.fdout:lock('tlock')) then
			nixio.syslog('alert', 'detected a lock on the delta fifos')
			os.exit(2)
		end

		if LAN_ENABLED then
			nixio.fs.mkdirr(LAN_PUBLISH_PATH)

			for file in nixio.fs.dir(LAN_PUBLISH_PATH) do
				nixio.fs.unlink(file)
			end

			local function create_file(sensor_id)
				local file = LAN_PUBLISH_PATH .. '/' .. sensor_id

				nixio.fs.unlink(file)
				fd = nixio.open(file, O_RDWR_CREAT)
				fd:close()
			end

			uci:foreach('flukso', 'sensor', function(x) if x.enabled then create_file(x.id) end end)
		end

		local function tolua(num)
			return num + 1
		end

		local function process_delta()
			for line in delta.fdout:linesource() do
				if DEBUG then
					print(line)
				end

				local timestamp, data = line:match('^(%d+)%s+([%-%d%s]+)$')
				timestamp = tonumber(timestamp)

				for i, counter, extra in data:gmatch('(%d+)%s+([%-%d]+)%s+([%-%d]+)') do
					i = tonumber(i)
					counter = tonumber(counter)
					extra = tonumber(extra)

					-- map index(+1!) to sensor id and sensor type
					local sensor_id = FLUKSO[tostring(tolua(i))]['id']
					local sensor_class = FLUKSO[tostring(tolua(i))]['class']
					local sensor_derive = (FLUKSO[tostring(tolua(i))]['derive'] == '1')

					-- resume both branches
					if WAN_ENABLED then
						resume(wan_child, sensor_id, sensor_class, timestamp, counter, extra)
					end

					if LAN_ENABLED then
						if sensor_class == 'analog' then
							resume(lan_child, sensor_id, timestamp, extra)
						elseif sensor_class == 'pulse' or (sensor_class == 'cosem' and not sensor_derive) then
							resume(lan_child, sensor_id, timestamp, false, counter, extra)
						end
					end
				end
			end
		end

		local delta_p = { fd = delta.fdout, events = POLLIN, revents = 0 }
		local ws_p = { fd = ws.input_fd(), events = POLLIN, revents = 0 }
		local pollfds = { delta_p, ws_p }

		while true do
			if ws.valid then
				ws_p.fd = ws.input_fd()
				ws_p.events = POLLIN
			else
				ws_p.fd = delta_p.fd
				ws_p.events = 0
			end
			local poll = nixio.poll(pollfds, -1)
			if poll > 0 then
				if delta_p.revents == POLLIN then
					process_delta()
				end
				if ws_p.revents == POLLIN then
					resume(wan_child)
				elseif ws_p.revents == POLLHUP then
					ws.valid = false
				end
			end
		end
	end)
end

local function wan_handler(child)
	return coroutine.create(function(sensor_id, sensor_class, timestamp, counter, extra)
		local BIN_WIDTH = 60
		local BIN_COUNT = 1440 * (60 / BIN_WIDTH)
		local TRANSMIT_LOWER_LIMIT = 5 * (60 / BIN_WIDTH)

		local backoff_exp = 1
		local try_again_at = nil
		local MAX_BACKOFF_EXP = 6

		local bwh = buffer.new(BIN_WIDTH, BIN_COUNT, buffer.aggregates.max)

		local function send_values(buffer, sensor_id, suffix)
			if try_again_at and try_again_at > os.time() then
				return
			end

			local update_cmd = ws:new_update_value_command(sensor_id .. suffix)
			local values_used = 0
			while buffer:get_point_count(sensor_id) >= values_used + 1 do
				local _, val = buffer:peek_oldest_value(sensor_id, values_used)
				if val.ts and not update_cmd:append(val.ts, val.value) then
					break
				end
				values_used = values_used + 1
			end
			if update_cmd:run() then
				try_again_at = nil
				backoff_exp = 1
				for i = 1, values_used do
					buffer:get_oldest_value(sensor_id)
				end
			else
				if backoff_exp < MAX_BACKOFF_EXP then
					backoff_exp = backoff_exp + 1
				end
				try_again_at = 2^(backoff_exp - 1) * (1 + math.random())
				print("could not send values, try again in " .. try_again_at .. "s")
				try_again_at = try_again_at + os.time()
			end
		end

		local last_value_of = {}

		while true do
			if (sensor_class == "analog" or sensor_class == "pulse") and
					(not last_value_of[sensor_id] or last_value_of[sensor_id] < counter) then
				last_value_of[sensor_id] = counter
				bwh:add_value(sensor_id, timestamp, counter)
			end

			for _, sensor in pairs(bwh:get_sensors()) do
				if bwh:get_point_count(sensor) > TRANSMIT_LOWER_LIMIT then
					send_values(bwh, sensor, "")
				end
			end

			collectgarbage()
			resume(child, sensor_id, timestamp, counter)
			sensor_id, sensor_class, timestamp, counter, extra = coroutine.yield()
		end
	end)
end

local function lan_buffer(child)
	return coroutine.create(function(sensor_id, timestamp, power, counter, msec)
		local measurements = data.new()
		local threshold = os.time() + LAN_INTERVAL
		local previous = {}

		local topic_fmt = '/sensor/%s/gauge'
		local payload_fmt = '[%d,%d,"%s"]'

		local function diff(x, y)  -- calculates y - x
			if y >= x then
				return y - x
			else -- y wrapped around 32-bit boundary
				return 4294967296 - x + y
			end
		end

		while true do
			if not previous[sensor_id] then
				previous[sensor_id] = {}
			end

			if timestamp > (previous[sensor_id].timestamp or 0) then
				if not power then  -- we're dealing pulse message so first calculate power
					if previous[sensor_id].msec and msec > previous[sensor_id].msec then
						power = math.floor(
							diff(previous[sensor_id].counter, counter) /
							diff(previous[sensor_id].msec, msec) *
							(LAN_ID_TO_FACTOR[sensor_id] or 1000) +
							0.5)

					end

					-- if msec decreased, just update the value in the table
					-- but don't make any power calculations since the AVR might have gone through a reset
					previous[sensor_id].msec = msec
					previous[sensor_id].counter = counter
				end

				if power then
					if (timestamp - (previous[sensor_id].timestamp or 0)) > MAX_TIME_OFFSET then
						nixio.syslog('info', 'time warp detected. removing old sensor data')
						measurements:clear(sensor_id)
						collectgarbage()
					end

					local topic = string.format(topic_fmt, sensor_id)
					local unit = LAN_ID_TO_UNIT[sensor_id].gauge
					local payload = string.format(payload_fmt, timestamp, power, unit)

					measurements:add(sensor_id, timestamp, power)
					previous[sensor_id].timestamp = timestamp
				end
			end

			if timestamp > threshold and next(measurements) then  --checking whether table is not empty
				resume(child, measurements)
				threshold = os.time() + LAN_INTERVAL
			end

			sensor_id, timestamp, power, counter, msec = coroutine.yield()
		end
	end)
end

local function publish(child)
	return coroutine.create(function(measurements)
		nixio.fs.mkdirr(LAN_PUBLISH_PATH)

		for file in nixio.fs.dir(LAN_PUBLISH_PATH) do
			nixio.fs.unlink(file)
		end

		while true do
			measurements:polish(os.time(), LAN_POLISH_CUTOFF)
			local measurements_json = measurements:json_encode(LAN_POLISH_CUTOFF)

			for sensor_id, json in pairs(measurements_json) do
				local file = LAN_PUBLISH_PATH .. '/' .. sensor_id
				local tmpfile = '/tmp/.' .. sensor_id .. ".tmp"
				
				nixio.fs.writefile(tmpfile, json)
				nixio.fs.move(tmpfile, file)
			end

			resume(child, measurements)
			measurements = coroutine.yield()
		end
	end)
end

local function debug(child)
	return coroutine.create(function(measurements)
		while true do
			if DEBUG then
				dbg.vardump(measurements)
			end

			if child then
				resume(child, measurements)
			end

			measurements = coroutine.yield()
		end
	end)
end

local wan_chain =
	wan_handler(
		debug(nil)
	)

local lan_chain =
	lan_buffer(
		publish(
			debug(nil)
		)
	)

local chain = dispatch(wan_chain, lan_chain)

resume(chain)
