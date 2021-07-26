local Util = require('LuaMidi.Util')
local ArbitraryEvent = require('LuaMidi.ArbitraryEvent')

local GenericEvent = {}

function GenericEvent:build_data()
	self.data = {}

	local data = Util.num_to_var_length(self.timestamp)
	data[#data+1] = self.status + self.channel-1
	data[#data+1] = self.msg1

	local band = Util.bitwise.band
	if (band(self.status, 0xF0) ~= 0xC0 and band(self.status, 0xF0) ~= 0xD0) then	-- i.e. status with single byte data
		data[#data+1] = self.msg2
	end

	local event = ArbitraryEvent.new({data = data})
	self.data = Util.table_concat(self.data, event.data)
end

function GenericEvent.new(fields)
   local self = {
      type = 'generic_event',
	  status = fields.status or 0xB0,
      msg1 = fields.msg1,
      msg2 = fields.msg2,
      timestamp = fields.timestamp,
      channel = fields.channel,
   }
   if self.timestamp ~= nil then
      assert(type(self.timestamp) == 'number' and self.timestamp >= 0, "'timestamp' must be a positive integer representing the explicit number of ticks")
   else
      self.timestamp = 0
   end
   if self.channel ~= nil then
      assert(type(self.channel) == 'number' and self.channel >= 1 and self.channel <= 16, "'channel' must be an integer from 1 to 16")
   else
      self.channel = 1
   end
   
   setmetatable(self, { __index = GenericEvent })
   self:build_data()
   return self
end

-------------------------------------------------
--- Methods
-- @section methods
-------------------------------------------------

-------------------------------------------------
-- Prints event's data in a human-friendly style
-------------------------------------------------
function GenericEvent:print()
   local str = string.format("msg1:\t\t%s\n", tostring(self.msg1))
   str = str..string.format("msg2:\t%d\n", tostring(self.msg2))
   str = str..string.format("Channel:\t%d\n", tostring(self.channel))
   str = str..string.format("Timestamp:\t%d", tostring(self.timestamp))
   print("\nClass / Type:\tGenericEvent / '"..self.type.."'")
   print(str)
end

function GenericEvent:set_status(status)
	self.msg1 = status
	self:build_data()
	return self
end

-------------------------------------------------
-- Sets GenericEvent's msg1
--
-- @param msg1 takes the same values as the msg1
-- field passed to the constructor.
--
-- @return 	GenericEvent with new msg1
-------------------------------------------------
function GenericEvent:set_msg1(msg1)
   assert(type(msg1) == 'string' or type(msg1) == 'number', "'msg1' must be a string or a number")
   assert(Util.get_msg1(msg1), "Invalid 'msg1' value: "..msg1)
   self.msg1 = msg1
   self:build_data()
   return self
end

-------------------------------------------------
-- Sets GenericEvent's msg2
--
-- @number msg2 loudness of the note sound.
-- Values from 0-100.
--
-- @return 	GenericEvent with new msg2
-------------------------------------------------
function GenericEvent:set_msg2(msg2)
   self.msg2 = msg2
   self:build_data()
   return self
end

-------------------------------------------------
-- Sets GenericEvent's channel
--
-- @number channel MIDI channel # (1-16).
--
-- @return 	GenericEvent with new channel
-------------------------------------------------
function GenericEvent:set_channel(channel)
   assert(type(channel) == 'number' and channel >= 1 and channel <= 16, "'channel' must be an integer from 1 to 16")
   self.channel = channel
   self:build_data()
   return self
end

-------------------------------------------------
-- Sets GenericEvent's timestamp
--
-- @number timestamp value.
--
-- @return 	GenericEvent with new timestamp
-------------------------------------------------
function GenericEvent:set_timestamp(timestamp)
   assert(type(timestamp) == 'number' and timestamp >= 0, "'timestamp' must be a positive integer representing the explicit number of ticks")
   self.timestamp = timestamp
   self:build_data()
   return self
end

function GenericEvent:get_status()
   return self.status
end

-------------------------------------------------
-- Gets msg1 of GenericEvent
--
-- @return 	GenericEvent's msg1 value
-------------------------------------------------
function GenericEvent:get_msg1()
   return self.msg1
end

-------------------------------------------------
-- Gets msg2 of GenericEvent
--
-- @return 	GenericEvent's msg2 value
-------------------------------------------------
function GenericEvent:get_msg2()
   return Util.revert_msg2(self.msg2)
end

-------------------------------------------------
-- Gets channel # of GenericEvent
--
-- @return 	GenericEvent's channel value
-------------------------------------------------
function GenericEvent:get_channel()
   return self.channel
end

-------------------------------------------------
-- Gets timestamp of GenericEvent
--
-- @return  GenericEvent's timestamp value
-------------------------------------------------
function GenericEvent:get_timestamp()
   return self.timestamp
end

return GenericEvent
