-------------------------------------------------
-- LuaMidi Library Class
-- <p>All modules are available through it.
-- It also presents useful functions to handle
-- MIDI files.
-- 
-- @classmod LuaMidi
-- @author Pedro Alves
-- @license MIT
-------------------------------------------------

local LuaMidi = {}

LuaMidi.Constants = require 'LuaMidi.Constants'
LuaMidi.Chunk = require 'LuaMidi.Chunk'
LuaMidi.MetaEvent = require 'LuaMidi.MetaEvent'
LuaMidi.NoteEvent = require 'LuaMidi.NoteEvent'
LuaMidi.OpenNoteOffEvent = require 'LuaMidi.OpenNoteOffEvent'
LuaMidi.OpenNoteOnEvent = require 'LuaMidi.OpenNoteOnEvent'
LuaMidi.NoteOffEvent = require 'LuaMidi.NoteOffEvent'
LuaMidi.NoteOnEvent = require 'LuaMidi.NoteOnEvent'
LuaMidi.ProgramChangeEvent = require 'LuaMidi.ProgramChangeEvent'
LuaMidi.Track = require 'LuaMidi.Track'
LuaMidi.Util = require 'LuaMidi.Util'
LuaMidi.Writer = require 'LuaMidi.Writer'

-------------------------------------------------
-- Functions
-- @section Functions
-------------------------------------------------

-------------------------------------------------
-- Reads all tracks from a MIDI file and convert
-- them to LuaMidi's Track objects.
--
-- @string path the MIDI file path
--
-- @return an array of the tracks
--
-- @see Track
-------------------------------------------------
function LuaMidi.get_MIDI_tracks(path)
   local MIDI = io.open(path, 'rb')
   if MIDI then
      local buffer = {}
      local bytes = MIDI:read("*a")
      for i=1, #bytes do
         buffer[#buffer+1] = string.byte(bytes:sub(i,i))
      end
      MIDI:close()
      local append = false
      local track_list = {}
      local track_number = 0
      for i=1, #buffer do
         if LuaMidi.Util.is_track_header({buffer[i], buffer[i+1], buffer[i+2], buffer[i+3]}) then
            append = true
            track_number = track_number + 1
            track_list[track_number] = {}
         end
         if buffer[i] == 0x00 and
            buffer[i+1] == 0xFF and
            buffer[i+2] == 0x2F and
            buffer[i+3] == 0x00 then
            append = false
         end
         if append then
            table.insert(track_list[track_number],buffer[i])
         end
      end
      for track_number, raw_track in ipairs(track_list) do
         local track = {
            type = {raw_track[1], raw_track[2], raw_track[3], raw_track[4]},
            events = {},
            metadata = {},
            size = {},
            data = {},
         }
         for i=1, 8 do table.remove(raw_track,1) end
         
         local metadata_types = LuaMidi.Constants.METADATA_TYPES
         
         local current_time_stamp = {}
         local is_time_stamp = true
         
         local function next_time_stamp(i, bytes_to_skip)
            current_time_stamp = {}
            is_time_stamp = true
--            print("skip "..bytes_to_skip)
            return i + bytes_to_skip
         end
         
         local function sum_time_stamp(time_stamp)
            local total = 0
            for i=1, #time_stamp do
               total = total + time_stamp[i]
            end
            return total
         end
         
         local notes_off = {}
         
         local i=1
         while i <= #raw_track do
         
            while is_time_stamp do
               current_time_stamp[#current_time_stamp+1] = raw_track[i]
               if raw_track[i] < 0x80 then
                  is_time_stamp = false
               end
               i = i + 1
            end
            
            if raw_track[i] == 0xFF then -- METADATA
            
               local raw_metadata = {}
               local length_byte = i+2
               local data_length = raw_track[length_byte] + 1
               for j=i, length_byte + data_length do
                  raw_metadata[#raw_metadata+1] = raw_track[j-1]
               end
               local converted_data
               if raw_track[i+1] < 0x08 then
                  converted_data = ""
                  for j=5, #raw_metadata do
                     converted_data = converted_data..string.char(raw_metadata[j])
                  end
               elseif raw_track[i+1] == LuaMidi.Constants.META_TEMPO_ID then
                  local data_bytes = {raw_track[i+3], raw_track[i+4], raw_track[i+5]}
                  local ms = LuaMidi.Util.number_from_bytes(data_bytes)
                  local bpm = LuaMidi.Util.round(60000000/ms)
                  converted_data = tostring(ms).." ms ("..bpm.."bpm)"
               elseif raw_track[i+1] == LuaMidi.Constants.META_TIME_SIGNATURE_ID then
                  converted_data = raw_track[i+3]
                  converted_data = converted_data.."/"..math.ceil(2^raw_track[i+4])
               elseif raw_track[i+1] == LuaMidi.Constants.META_KEY_SIGNATURE_ID then
                  local majmin = {'major', 'minor'}
                  local keys = {{'C','A'},{'G','E'},{'D','B'},{'A','F#'},
                     {'E','C#'},{'B','G#'},{'F#','D#'},{'C#','A#'}}
                  local sharps_num = tostring(raw_track[i+3])
                  converted_data = sharps_num.."#"
                  converted_data = converted_data.." ("..keys[sharps_num+1][raw_track[i+4]+1].." "..majmin[raw_track[i+4]+1]..")"
               end
               local subtype = metadata_types[raw_track[i+1]]
               track.metadata[subtype] = converted_data
               local event = {
                  type = 'meta',
                  subtype = subtype,
                  data = raw_metadata,
                  time_stamp = sum_time_stamp(current_time_stamp),
               }
               event = setmetatable(event, { __index = LuaMidi.MetaEvent })
               track.events[#track.events+1] = event
               i = next_time_stamp(i, data_length+1)
               
            elseif raw_track[i] < 0x80 and raw_track[i+1] == LuaMidi.Constants.PROGRAM_CHANGE_STATUS then
            
               local event = {
                  type = 'program-change',
                  data = { raw_track[i], raw_track[i+1], raw_track[i+2] },
                  time_stamp = sum_time_stamp(current_time_stamp),
               }
               event = setmetatable(event, { __index = LuaMidi.ProgramChangeEvent })
               track.events[#track.events+1] = event
               current_time_stamp = {}
               is_time_stamp = true
               
            elseif raw_track[i] >= 0x90 and raw_track[i] <= 0x9F then -- NOTE ON
            
               local channel = raw_track[i]-0x8F
               local pitch = { raw_track[i+1] }
               local pitch_code = raw_track[i+1]
               local velocity = raw_track[i+2]
               
               do
                  local notes = LuaMidi.Util.table_invert(LuaMidi.Constants.NOTES)
                  pitch[1] = notes[pitch_code]
               end
              
               local raw_note = {}
               do
               
                  for i=1, #current_time_stamp do
                     raw_note[i] = current_time_stamp[i]
                  end
                  
                  raw_note[#raw_note+1] = channel+0x8F
                  raw_note[#raw_note+1] = pitch_code
                  raw_note[#raw_note+1] = velocity

               end
               
               local event = {
                  type = 'note',
                  data = raw_note,
                  channel = channel,
                  pitch = pitch,
                  pitch_code = pitch_code,
                  is_incomplete = true,
                  rest = sum_time_stamp(current_time_stamp),
                  velocity = LuaMidi.Util.round(velocity / 127 * 100),
                  sequential = false,
                  repetition = 1,
                  time_stamp = sum_time_stamp(current_time_stamp),
               }
               event = setmetatable(event, { __index = LuaMidi.NoteEvent })
               track.events[#track.events+1] = event
               i = next_time_stamp(i, 2)
            
            elseif raw_track[i] >= 0x80 and raw_track[i] <= 0x8F then -- NOTE OFF
               
               local event = {
                  type = 'note_off',
                  channel = raw_track[i]-0x7F,
                  pitch_code = raw_track[i+1],
                  velocity = raw_track[i+2],
                  time_stamp = sum_time_stamp(current_time_stamp),
               }
               
               track.events[#track.events+1] = event
               i = next_time_stamp(i, 2)
               
            end
            
            i = i + 1
         
            do -- matches note signals (on with off)
            
               for i=1, #track.events do
                  if track.events[i].type == 'note' then
                     local note_on = track.events[i]
                     local delta_time = 0
                     for j=i, #track.events do
                        delta_time = track.events[j].time_stamp
                        if track.events[j].type == 'note_off' then
                           local note_off = track.events[j]
                           if note_off.channel == note_on.channel and
                              note_off.pitch_code == note_on.pitch_code and
                              note_on.is_incomplete then
                              
                              note_on.duration = 'T'..tostring(delta_time-1)
                              note_on.is_incomplete = nil
                              break
                           end
                        end
                     end
                  end
               end
            end
         end
         
         do
         
            local events = {}
            for i=1, #track.events do
               events[i] = track.events[i]
            end
            track.events = {}
            
            for i=1, #events do
               if events[i].type ~= 'note_off' then
                  events[i].time_stamp = nil
                  events[i].pitch_code = nil
                  track.events[#track.events+1] = events[i]
               end
            end
            
            for i=1, #track.events do
               if track.events[i].type == 'note' then
                  track.events[i] = LuaMidi.NoteEvent.new(track.events[i])
               end
            end
                     
         end
         
         track = setmetatable(track, { __index = LuaMidi.Track })
         track_list[track_number] = track
      end
      return track_list
   end 
   return false
end

-------------------------------------------------
-- Adds tracks to a MIDI file.
--
-- @string input the original MIDI file path
-- @param tracks a track object or a table of tracks
-- @string[opt=`input`] output altered MIDI file path
--
-- @return `true` if successful, `false` if not
--
-- @see Track
-------------------------------------------------
function LuaMidi.add_tracks_to_MIDI(input, tracks, output)
   if not output then output = input end
   if input:sub(#input-3) ~= ".mid" and input:sub(#input-4) ~= ".midi" then
      return false
   end
   local MIDI = io.open(input, 'rb')
   if MIDI then
      local buffer = {}
      for line in MIDI:lines() do
         for i=1, #line do
            buffer[#buffer+1] = string.byte(line:sub(i,i))
         end
      end
      MIDI:close()
      if not (buffer[1] == 0x4D and
         buffer[2] == 0x54 and
         buffer[3] == 0x68 and
         buffer[4] == 0x64) then
         return false
      end
      if #tracks == 0 and tracks.type then
         if LuaMidi.Util.is_track_header(tracks.type) then
            tracks = {tracks}
         end
      end
      buffer[10] = 0x01
      local original_n_tracks = 0
      for i=1, #buffer do
         if LuaMidi.Util.is_track_header({buffer[i], buffer[i+1], buffer[i+2], buffer[i+3]}) then
            original_n_tracks = original_n_tracks + 1
         end
      end
      local bytes_n_tracks = LuaMidi.Util.number_to_bytes(original_n_tracks + #tracks, 2)
      buffer[11] = bytes_n_tracks[1]
      buffer[12] = bytes_n_tracks[2]
      local tracks_bytes = {}
      for _, track in ipairs(tracks) do
         track:add_events(LuaMidi.MetaEvent.new({data = LuaMidi.Constants.META_END_OF_TRACK_ID}))
         local raw_track = LuaMidi.Util.table_concat(track.type, track.size)
         raw_track = LuaMidi.Util.table_concat(raw_track, track.data)
         tracks_bytes[#tracks_bytes+1] = raw_track
      end
      for _, track in ipairs(tracks_bytes) do
         buffer = LuaMidi.Util.table_concat(buffer, track)
      end
      MIDI = io.open(output, 'wb')
      local unpack = unpack or table.unpack
      buffer = string.char(unpack(buffer))
      MIDI:write(buffer)
      MIDI:close()
      return true
   end
   return false
end

return LuaMidi
