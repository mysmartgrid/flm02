local os, math, table, string =
      os, math, table, string

local getfenv, setmetatable, pairs, ipairs =
      getfenv, setmetatable, pairs, ipairs

local print = print

module('buffer')

local function round_to(value, range)
	return math.floor(value / range) * range
end

local buffer_ops = {}

function buffer_ops.add_value(self, sensor_id, timestamp, value)
	local priv = self[".priv"]

	local slot_base_ts = round_to(timestamp, priv.bin_timespan)

	if priv.bins[sensor_id] == nil then
		priv.bins[sensor_id] = {
			rb_begin = 1,
			rb_used = 0,
			points = {},
		}
		for i = 1, priv.bin_count do
			priv.bins[sensor_id].points[i] = {
				base_ts = slot_base_ts + (i - 1) * priv.bin_timespan,
				state = {},
			}
		end
	end

	local bin = priv.bins[sensor_id]
	local result = nil

	if bin.rb_used == 0 then
		bin.points[bin.rb_begin].base_ts = slot_base_ts
		bin.points[bin.rb_begin].state = {}
		bin.rb_used = 1
	end

	if slot_base_ts < bin.points[bin.rb_begin].base_ts then
		return nil, "backward jump in timestamp"
	end

	while slot_base_ts >= bin.points[bin.rb_begin].base_ts + bin.rb_used * priv.bin_timespan
			and bin.rb_used < priv.bin_count do
		local next_slot_idx = bin.rb_begin + bin.rb_used
		if next_slot_idx > priv.bin_count then
			next_slot_idx = next_slot_idx - priv.bin_count
		end
		bin.points[next_slot_idx].base_ts = bin.points[bin.rb_begin].base_ts + bin.rb_used * priv.bin_timespan
		bin.points[next_slot_idx].state = {}
		bin.rb_used = bin.rb_used + 1
	end

	while slot_base_ts >= bin.points[bin.rb_begin].base_ts + bin.rb_used * priv.bin_timespan do
		if not result then
			result = {}
		end

		local old = bin.points[bin.rb_begin]

		result[#result + 1] = {
			ts = old.base_ts + math.floor(priv.bin_timespan / 2),
			value = priv.bin_aggregate_fn(old.state, nil, nil),
		}

		old.base_ts = old.base_ts + priv.bin_count * priv.bin_timespan
		old.state = {}

		bin.rb_begin = bin.rb_begin + 1
		if bin.rb_begin > priv.bin_count then
			bin.rb_begin = bin.rb_begin - priv.bin_count
		end
	end

	local used_bin_offset = math.floor((slot_base_ts - bin.points[bin.rb_begin].base_ts) / priv.bin_timespan)
	local bin_number = bin.rb_begin + used_bin_offset
	if bin_number > priv.bin_count then
		bin_number = bin_number - priv.bin_count
	end

	priv.bin_aggregate_fn(bin.points[bin_number].state, timestamp, value)

	return result
end

function buffer_ops.get_oldest_value(self, sensor_id, offset, peek)
	local priv = self[".priv"]
	local bin = priv.bins[sensor_id]

	if offset then
		peek = true
	end
	offset = offset or 0

	if not bin or bin.rb_used <= offset then
		return nil
	end

	local point_idx = bin.rb_begin + offset

	if point_idx > priv.bin_count then
		point_idx = point_idx - priv.bin_count
	end

	local oldest_point = bin.points[point_idx]
	local res_ts, res_val = oldest_point.base_ts + priv.bin_timespan / 2, priv.bin_aggregate_fn(oldest_point.state, nil, nil)

	if not peek then
		bin.points[bin.rb_begin].state = {}

		if bin.rb_begin == priv.bin_count then
			bin.rb_begin = 1
		else
			bin.rb_begin = bin.rb_begin + 1
		end
		bin.rb_used = bin.rb_used - 1
	end

	return res_ts, res_val
end

function buffer_ops.peek_oldest_value(self, sensor_id, offset)
	return self:get_oldest_value(sensor_id, offset, true)
end

function buffer_ops.get_sensors(self)
	local result = {}

	for k, v in pairs(self[".priv"].bins) do
		result[#result + 1] = k
	end

	return result
end

function buffer_ops.get_point_count(self, sensor_id)
	local bin = self[".priv"].bins[sensor_id]

	if not bin then
		return nil
	else
		return bin.rb_used
	end
end

local function new(bin_timespan, bin_count, bin_aggregate_fn)
	local buf_priv = {
		bin_timespan = bin_timespan,
		bin_count = bin_count,
		bin_aggregate_fn = bin_aggregate_fn,
		bins = {},
	}

	return setmetatable({
		[".priv"] = buf_priv,
	}, {
		__index = buffer_ops
	})
end

local aggregates = {}

function aggregates.average(state, timestamp, value)
	if timestamp == nil then
		if not state.sum then
			return nil
		else
			return (state.sum or 0) / (state.nvalues or 1)
		end
	end

	if not state.sum then
		state.nvalues = 0
		state.sum = 0
	end

	state.sum = state.sum + value
	state.nvalues = state.nvalues + 1
end

function aggregates.max(state, timestamp, value)
	if timestamp == nil then
		return state.value
	end

	state.value = math.max(state.value or -math.huge, value)
end

return {
	new = new,

	aggregates = aggregates,
}
