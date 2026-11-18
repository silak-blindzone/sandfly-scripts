local manifest = {
  id = 'watch',
  name = 'Watch',
  version = '3.0',
  author = 'Silak',
  description = 'Tells the time by vibration: a long vibration is a ten, a short one a unit, and a weak short one a zero, with a longer pause between hours and minutes. It vibrates through Android directly, so it works with SandFly\'s vibration off. The lengths, pauses, speed and strength can be changed in its settings. Ported from a Jieshuo plugin.',
  minApiVersion = 4,
  testedApiVersion = 5,
  onDemand = true,
  permissions = { 'input', 'java', 'speech' },
  commands = {
    { id = 'vibrate_time', title = 'Vibrate the time' },
  },
  settings = {
    { key = 'speed', type = 'list', title = 'Speed', default = '1',
      options = {
        { value = '2', label = 'Much slower' },
        { value = '1.5', label = 'Slower' },
        { value = '1', label = 'Normal' },
        { value = '0.75', label = 'Faster' },
        { value = '0.5', label = 'Much faster' },
      } },
    { key = 'strength', type = 'list', title = 'Strength', default = '100',
      options = {
        { value = '50', label = 'Weak' },
        { value = '100', label = 'Normal' },
        { value = '180', label = 'Strong' },
        { value = '255', label = 'Strongest' },
      } },
    { key = 'longVibration', type = 'number', title = 'Long vibration (a ten), ms', summary = '300 by default', default = 300 },
    { key = 'shortVibration', type = 'number', title = 'Short vibration (a unit), ms', summary = '50 by default', default = 50 },
    { key = 'zeroVibration', type = 'number', title = 'Zero vibration, ms', summary = '20 by default', default = 20 },
    { key = 'pause', type = 'number', title = 'Pause between vibrations, ms', summary = '200 by default', default = 200 },
    { key = 'longPause', type = 'number', title = 'Pause between hours and minutes, ms', summary = '1000 by default', default = 1000 },
    { key = 'hour12', type = 'switch', title = '12-hour clock', summary = 'Vibrates 3 instead of 15', default = false },
    { key = 'hoursOnly', type = 'switch', title = 'Hours only', summary = 'Leaves out the minutes', default = false },
    { key = 'speak', type = 'switch', title = 'Also say the time', default = false },
  },
}

local tr = sf._

-- The zero vibration stays weak, as in the original plugin, whatever the strength.
local ZERO_AMPLITUDE = 10

local TalkBackService = java.import('com.google.android.accessibility.talkback.TalkBackService')
local VibrationEffect = java.import('android.os.VibrationEffect')

-- A number setting, kept within sensible bounds.
local function number(key, fallback, low, high)
  local v = tonumber(sf.settings.get(key)) or fallback
  return math.max(low, math.min(high, math.floor(v)))
end

-- The settings, with the speed applied to every length and pause.
local function config()
  local speed = tonumber(sf.settings.get('speed')) or 1
  local function scaled(key, fallback, low, high)
    return math.max(1, math.floor(number(key, fallback, low, high) * speed))
  end
  return {
    longVibration = scaled('longVibration', 300, 10, 3000),
    shortVibration = scaled('shortVibration', 50, 10, 3000),
    zeroVibration = scaled('zeroVibration', 20, 5, 3000),
    pause = scaled('pause', 200, 0, 5000),
    longPause = scaled('longPause', 1000, 0, 10000),
    amplitude = number('strength', 100, 1, 255),
  }
end

-- Android's vibrator, outside SandFly's vibration setting.
local function vibrator()
  local context = TalkBackService:getInstance()
  if context == nil then return nil end
  local v = context:getSystemService('vibrator')
  if v == nil or not v:hasVibrator() then return nil end
  return v
end

-- Adds the vibrations for one number, hours or minutes, as { length, strength, pause after }.
local function addNumber(parts, value, c)
  if value == 0 then
    parts[#parts + 1] = { c.zeroVibration, ZERO_AMPLITUDE, 0 }
    return
  end
  for _ = 1, value // 10 do
    parts[#parts + 1] = { c.longVibration, c.amplitude, c.pause }
  end
  for _ = 1, value % 10 do
    parts[#parts + 1] = { c.shortVibration, c.amplitude, c.pause }
  end
end

local function timePattern(hours, minutes, c, hoursOnly)
  local parts = {}
  addNumber(parts, hours, c)
  if hoursOnly then return parts end
  -- The longer pause comes on top of the usual one, as in the original plugin.
  local last = parts[#parts]
  last[3] = last[3] + c.longPause
  addNumber(parts, minutes, c)
  return parts
end

-- Each run gets a number, so that a new run stops the one before.
local run = 0

local function vibrateTime()
  local v = vibrator()
  if v == nil then
    sf.log.warn('No vibrator available')
    return
  end
  run = run + 1
  local mine = run
  v:cancel()
  -- Without amplitude control, the phone vibrates at its own strength, and the zero is told
  -- apart by being shorter.
  local amplitudes = v:hasAmplitudeControl()
  local now = os.date('*t')
  local hours = now.hour
  if sf.settings.get('hour12') then
    hours = hours % 12
    if hours == 0 then hours = 12 end
  end
  local hoursOnly = sf.settings.get('hoursOnly') == true
  if sf.settings.get('speak') then
    sf.speak(hoursOnly and string.format('%d', hours) or string.format('%d:%02d', hours, now.min))
  end
  for _, part in ipairs(timePattern(hours, now.min, config(), hoursOnly)) do
    if run ~= mine then return end
    local amplitude = amplitudes and part[2] or VibrationEffect.DEFAULT_AMPLITUDE
    v:vibrate(VibrationEffect:createOneShot(part[1], amplitude))
    sf.sleep(part[1] + part[3])
  end
end

sf.onCommand('vibrate_time', vibrateTime)
