local manifest = {
  id = 'call-volume',
  name = 'Call volume fix',
  version = '1.1',
  author = 'Silak',
  description = 'For calls on Bluetooth headphones, where the speech of the screen reader can turn very quiet until the volume is moved up and back. A few seconds after a call starts on Bluetooth, it moves the call volume up and back itself and says so. The command Fix quiet speech in a call, in the SandFly menu, does the same at any time. Before and after each fix, and when a call starts, ends or moves to or from Bluetooth, it writes the state of the sound to its log, so that the cause can be found.',
  minApiVersion = 5,
  testedApiVersion = 7,
  permissions = { 'input', 'java', 'speech' },
  settings = {
    { key = 'autoFix', type = 'switch', title = 'Fix by itself in Bluetooth calls', default = true },
    { key = 'delay', type = 'number', title = 'Seconds before the fix', summary = '5 by default', default = 5 },
    { key = 'announce', type = 'switch', title = 'Say when it fixes the volume', default = true },
  },
  commands = {
    { id = 'fix', title = 'Fix quiet speech in a call', menu = true },
  },
}

local tr = sf._

local TalkBackService = java.import('com.google.android.accessibility.talkback.TalkBackService')

-- How often the state of a call is checked, in milliseconds.
local CHECK_MS = 3000
-- The pause between moving the volume one step and back.
local STEP_MS = 300

-- AudioManager values.
local MODE_IN_CALL = 2
local MODE_IN_COMMUNICATION = 3
local STREAM_VOICE_CALL = 0
local ADJUST_LOWER = -1
local ADJUST_RAISE = 1

local MODES = { [0] = 'normal', [1] = 'ringtone', [2] = 'in call', [3] = 'in communication' }

-- The streams written to the log.
local STREAMS = {
  { 'call', 0 }, { 'ring', 2 }, { 'media', 3 }, { 'notification', 5 }, { 'accessibility', 10 },
}

-- AudioDeviceInfo types.
local DEVICES = {
  [1] = 'earpiece', [2] = 'speaker', [3] = 'wired headset', [4] = 'wired headphones',
  [7] = 'Bluetooth call (SCO)', [8] = 'Bluetooth media (A2DP)', [22] = 'USB headset',
  [26] = 'Bluetooth LE headset', [27] = 'Bluetooth LE speaker',
}
local BLUETOOTH_CALL = { [7] = true, [26] = true }

local function audio()
  local context = TalkBackService:getInstance()
  if context == nil then return nil end
  return context:getSystemService('audio')
end

-- The type of the device that the call uses, or nil. Android 12 and later tell it; before that,
-- whether Bluetooth SCO is on.
local function callDevice(am)
  local ok, device = pcall(function() return am:getCommunicationDevice() end)
  if ok then
    if device == nil then return nil end
    return device:getType()
  end
  local okSco, sco = pcall(function() return am:isBluetoothScoOn() end)
  if okSco and sco then return 7 end
  return nil
end

local function isCall(am)
  local mode = am:getMode()
  return mode == MODE_IN_CALL or mode == MODE_IN_COMMUNICATION
end

-- The state of the sound as one line for the log.
local function describe(am)
  local parts = { 'mode ' .. (MODES[am:getMode()] or tostring(am:getMode())) }
  local device = callDevice(am)
  parts[#parts + 1] = 'device ' .. (device and (DEVICES[device] or ('type ' .. device)) or 'none')
  for _, stream in ipairs(STREAMS) do
    local ok, text = pcall(function()
      return string.format('%s %d/%d', stream[1], am:getStreamVolume(stream[2]),
        am:getStreamMaxVolume(stream[2]))
    end)
    if ok then parts[#parts + 1] = text end
  end
  return table.concat(parts, ', ')
end

local function note(event, am)
  sf.log.info(event .. ': ' .. describe(am))
end

-- Moves the call volume one step and back, as the volume keys do by hand. At the top, it goes
-- down first, so that the volume ends where it was.
local function nudge(am)
  local volume = am:getStreamVolume(STREAM_VOICE_CALL)
  local first, second = ADJUST_RAISE, ADJUST_LOWER
  if volume >= am:getStreamMaxVolume(STREAM_VOICE_CALL) then
    first, second = ADJUST_LOWER, ADJUST_RAISE
  end
  am:adjustStreamVolume(STREAM_VOICE_CALL, first, 0)
  sf.sleep(STEP_MS)
  am:adjustStreamVolume(STREAM_VOICE_CALL, second, 0)
end

local function fix(byItself)
  local am = audio()
  if am == nil then return end
  if not isCall(am) then
    if not byItself then sf.speak(tr('There is no call'), { interrupt = true }) end
    return
  end
  note(byItself and 'Before the fix by itself' or 'Before the fix', am)
  nudge(am)
  sf.sleep(STEP_MS)
  note('After the fix', am)
  if not byItself or sf.settings.get('announce') ~= false then
    sf.speak(tr('Volume fixed'), { interrupt = true })
  end
end

sf.onCommand('fix', function() fix(false) end)

local inCall, onBluetooth = false, false

local function fixLater()
  local seconds = tonumber(sf.settings.get('delay')) or 5
  seconds = math.max(1, math.min(60, math.floor(seconds)))
  sf.setTimeout(function()
    local am = audio()
    -- Only while the call is still on Bluetooth.
    if am ~= nil and isCall(am) and BLUETOOTH_CALL[callDevice(am) or 0] then
      fix(true)
    end
  end, seconds * 1000)
end

local function check()
  local ok, failure = pcall(function()
    local am = audio()
    if am == nil then return end
    local call = isCall(am)
    if call ~= inCall then
      inCall = call
      note(call and 'Call started' or 'Call ended', am)
    end
    local bluetooth = call and BLUETOOTH_CALL[callDevice(am) or 0] == true
    if bluetooth ~= onBluetooth then
      onBluetooth = bluetooth
      if call then
        note(bluetooth and 'Call on Bluetooth' or 'Call left Bluetooth', am)
      end
      if bluetooth and sf.settings.get('autoFix') ~= false then fixLater() end
    end
  end)
  if not ok then sf.log.warn('Checking the call failed: ' .. tostring(failure)) end
  sf.setTimeout(check, CHECK_MS)
end

check()
