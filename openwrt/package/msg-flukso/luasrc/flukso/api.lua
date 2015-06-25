#!/usr/bin/env lua

--[[
    
    api.lua - provide some helper functions for communication with the mySmartGrid server

    Copyright (C) 2015 Stephan Platz <platz@itwm.fraunhofer.de>

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

local uci			= require 'luci.model.uci'.cursor()

-- WAN settings
WAN_BASE_URL	= uci:get('flukso', 'daemon', 'wan_base_url')
SENSOR_BASE_URL	 = WAN_BASE_URL .. 'sensor/'
DEVICE_BASE_URL	 = WAN_BASE_URL .. 'device/'
WAN_KEY		 = '0123456789abcdef0123456789abcdef'
uci:foreach('system', 'system', function(x) WAN_KEY = x.key end) -- quirky but it works

DEVICE		= '0123456789abcdef0123456789abcdef'
uci:foreach('system', 'system', function(x) DEVICE = x.device end)

-- https header helpers
FLUKSO_VERSION = '000'
uci:foreach('system', 'system', function(x) FLUKSO_VERSION = x.version end)

USER_AGENT	= 'Fluksometer v' .. FLUKSO_VERSION
CACERT		= uci:get('flukso', 'daemon', 'cacert')

function sensor_json(flukso, i) -- type(i) --> "string"
	local config = {}

	config["device"]   = DEVICE
	config["class"]    = flukso[i]["class"]
	config["type"]     = flukso[i]["type"]
	config["function"] = flukso[i]["function"]
	config["voltage"]  = tonumber(flukso[i]["voltage"])
	config["current"]  = tonumber(flukso[i]["current"])
	config["constant"] = tonumber(flukso[i]["constant"])
	config["enable"]   = tonumber(flukso[i]["enable"])
	config["port"]     = tonumber(flukso[i]["port"])

	return luci.json.encode{ config = config }
end

