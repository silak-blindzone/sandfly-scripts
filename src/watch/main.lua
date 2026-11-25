local manifest = {
  id = 'watch',
  name = 'Watch',
  version = '3.4',
  author = 'Silak',
  description = 'Tells the time by vibration: a long vibration is a ten, a short one a unit, and a weak short one a zero, with a longer pause between hours and minutes. In Haptic taps mode it taps instead: a long vibration is a ten, a tap a unit and a light tap a zero, using the best haptics the phone has, and plain vibrations on a phone without them. It vibrates through Android directly, so it works with SandFly\'s vibration off. The taps, lengths, pauses, speed and strength can be changed in its settings. The command Time when locked, a command when unlocked tells the time on the lock screen and runs the SandFly command chosen in When unlocked otherwise, such as Lock or unlock touch. Ported from a Jieshuo plugin.',
  minApiVersion = 4,
  testedApiVersion = 5,
  onDemand = true,
  permissions = { 'input', 'java', 'speech', 'system', 'clipboard' },
  commands = {
    { id = 'vibrate_time', title = 'Vibrate the time' },
    { id = 'time_or_command', title = 'Time when locked, a command when unlocked' },
  },
  settings = {
    -- The script adds every SandFly command to the options when it first runs a command.
    { key = 'unlockedCommand', type = 'list', title = 'When unlocked',
      summary = 'What Time when locked, a command when unlocked does with the phone unlocked',
      default = 'TOGGLE_TOUCH_LOCK',
      options = {
        { value = 'time', label = 'Vibrate the time' },
        { value = 'TOGGLE_TOUCH_LOCK', label = 'Lock or unlock touch' },
      } },
    { key = 'mode', type = 'list', title = 'Mode', default = 'haptic',
      options = {
        { value = 'vibration', label = 'Vibrations' },
        { value = 'haptic', label = 'Haptic taps' },
      } },
    { key = 'tenTap', type = 'list', title = 'Tap for a ten', summary = 'In Haptic taps mode', default = 'long',
      options = {
        { value = 'long', label = 'Long vibration' },
        { value = 'heavy', label = 'Heavy tap' },
        { value = 'double', label = 'Double tap' },
        { value = 'tap', label = 'Tap' },
        { value = 'light', label = 'Light tap' },
      } },
    { key = 'unitTap', type = 'list', title = 'Tap for a unit', summary = 'In Haptic taps mode', default = 'tap',
      options = {
        { value = 'heavy', label = 'Heavy tap' },
        { value = 'double', label = 'Double tap' },
        { value = 'tap', label = 'Tap' },
        { value = 'light', label = 'Light tap' },
      } },
    { key = 'zeroTap', type = 'list', title = 'Tap for a zero', summary = 'In Haptic taps mode', default = 'light',
      options = {
        { value = 'heavy', label = 'Heavy tap' },
        { value = 'double', label = 'Double tap' },
        { value = 'tap', label = 'Tap' },
        { value = 'light', label = 'Light tap' },
      } },
    { key = 'speed', type = 'list', title = 'Speed', default = '1',
      options = {
        { value = '2', label = 'Much slower' },
        { value = '1.5', label = 'Slower' },
        { value = '1', label = 'Normal' },
        { value = '0.75', label = 'Faster' },
        { value = '0.5', label = 'Much faster' },
      } },
    { key = 'strength', type = 'list', title = 'Strength', summary = 'For vibrations, and for taps on phones with the finest haptics', default = '100',
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
-- About how long a haptic tap lasts; the pause after it starts when it ends.
local TAP_LENGTH = 30
-- The gap between the two taps of a double tap made of single primitives.
local DOUBLE_GAP = 70

local TalkBackService = java.import('com.google.android.accessibility.talkback.TalkBackService')
local VibrationEffect = java.import('android.os.VibrationEffect')
local Composition = java.import('android.os.VibrationEffect$Composition')
local Vibrator = java.import('android.os.Vibrator')
local Integer = java.import('java.lang.Integer')
local Array = java.import('java.lang.reflect.Array')

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

-- An int[] for the Vibrator methods that take a list of effects or primitives.
local function ints(values)
  local array = Array:newInstance(Integer.TYPE, #values)
  for i, value in ipairs(values) do
    Array:setInt(array, i - 1, value)
  end
  return array
end

-- The haptics the phone can play: 'primitives' (the finest, with strength), 'effects'
-- (the system's predefined taps) or nil, when only plain vibrations are left.
local function hapticKind(v)
  local ok, all = pcall(function()
    return v:areAllPrimitivesSupported(ints({
      Composition.PRIMITIVE_CLICK, Composition.PRIMITIVE_THUD, Composition.PRIMITIVE_TICK }))
  end)
  if ok and all then return 'primitives' end
  ok, all = pcall(function()
    return v:areAllEffectsSupported(ints({
      VibrationEffect.EFFECT_CLICK, VibrationEffect.EFFECT_HEAVY_CLICK,
      VibrationEffect.EFFECT_DOUBLE_CLICK, VibrationEffect.EFFECT_TICK }))
  end)
  if ok and all == Vibrator.VIBRATION_EFFECT_SUPPORT_YES then return 'effects' end
  return nil
end

-- One tap as a composition of primitives, at the chosen strength.
local function primitiveTap(tap, scale)
  local c = VibrationEffect:startComposition()
  if tap == 'heavy' then
    c:addPrimitive(Composition.PRIMITIVE_THUD, scale)
  elseif tap == 'double' then
    c:addPrimitive(Composition.PRIMITIVE_CLICK, scale)
    c:addPrimitive(Composition.PRIMITIVE_CLICK, scale, DOUBLE_GAP)
  elseif tap == 'light' then
    c:addPrimitive(Composition.PRIMITIVE_TICK, scale)
  else
    c:addPrimitive(Composition.PRIMITIVE_CLICK, scale)
  end
  return c:compose()
end

local EFFECTS = {
  heavy = 'EFFECT_HEAVY_CLICK',
  double = 'EFFECT_DOUBLE_CLICK',
  tap = 'EFFECT_CLICK',
  light = 'EFFECT_TICK',
}

-- The three taps, for a ten, a unit and a zero, as vibration effects. A ten can also be the long
-- vibration of Vibrations mode, which is easier to tell from a tap than any tap is.
local function taps(kind, c)
  local function effect(key, fallback)
    local tap = sf.settings.get(key) or fallback
    if tap == 'long' and key == 'tenTap' then
      return VibrationEffect:createOneShot(c.longVibration, c.amplitude), c.longVibration
    end
    if EFFECTS[tap] == nil then tap = fallback end
    if kind == 'primitives' then
      return primitiveTap(tap, c.amplitude / 255)
    end
    return VibrationEffect:createPredefined(VibrationEffect[EFFECTS[tap]])
  end
  local result = { lengths = {} }
  for digit, setting in pairs({ ten = { 'tenTap', 'long' }, unit = { 'unitTap', 'tap' },
                                zero = { 'zeroTap', 'light' } }) do
    local e, length = effect(setting[1], setting[2])
    result[digit] = e
    result.lengths[digit] = length or TAP_LENGTH
  end
  return result
end

-- Adds one number, hours or minutes, as { 'ten' | 'unit' | 'zero', pause after }.
local function addNumber(parts, value, c)
  if value == 0 then
    parts[#parts + 1] = { 'zero', 0 }
    return
  end
  for _ = 1, value // 10 do
    parts[#parts + 1] = { 'ten', c.pause }
  end
  for _ = 1, value % 10 do
    parts[#parts + 1] = { 'unit', c.pause }
  end
end

local function timePattern(hours, minutes, c, hoursOnly)
  local parts = {}
  addNumber(parts, hours, c)
  if hoursOnly then return parts end
  -- The longer pause comes on top of the usual one, as in the original plugin.
  local last = parts[#parts]
  last[2] = last[2] + c.longPause
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
  local c = config()
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

  local tapEffects = nil
  if sf.settings.get('mode') == 'haptic' then
    local kind = hapticKind(v)
    if kind == nil then
      sf.log.info('This phone has no haptic taps; using vibrations')
    else
      local ok, result = pcall(taps, kind, c)
      if ok then
        tapEffects = result
        sf.log.info('Haptic taps: ' .. kind)
      else
        sf.log.warn('Haptic taps failed, using vibrations: ' .. tostring(result))
      end
    end
  end
  -- Without amplitude control, the phone vibrates at its own strength, and the zero is told
  -- apart by being shorter.
  local amplitudes = v:hasAmplitudeControl()
  local lengths = { ten = c.longVibration, unit = c.shortVibration, zero = c.zeroVibration }

  for _, part in ipairs(timePattern(hours, now.min, c, hoursOnly)) do
    if run ~= mine then return end
    local digit, pauseAfter = part[1], part[2]
    if tapEffects then
      v:vibrate(tapEffects[digit])
      sf.sleep(tapEffects.lengths[digit] + pauseAfter)
    else
      local amplitude = digit == 'zero' and ZERO_AMPLITUDE or c.amplitude
      if not amplitudes then amplitude = VibrationEffect.DEFAULT_AMPLITUDE end
      v:vibrate(VibrationEffect:createOneShot(lengths[digit], amplitude))
      sf.sleep(lengths[digit] + pauseAfter)
    end
  end
end

-- Whether the phone is locked or its screen is off, when the time is told instead of the command.
local function isLocked()
  local context = TalkBackService:getInstance()
  if context == nil then return true end
  local power = context:getSystemService('power')
  if power ~= nil and not power:isInteractive() then return true end
  local keyguard = context:getSystemService('keyguard')
  return keyguard ~= nil and keyguard:isKeyguardLocked()
end

-- Most characters the options of a list may hold, values and labels together.
local MAX_OPTION_CHARS = 16384
local MAX_OPTIONS = 500

-- Lists every SandFly command in When unlocked, after Vibrate the time, so that the user can
-- choose any of them in the settings of the script.
local function listCommands()
  local options = { { value = 'time', label = tr('Vibrate the time') } }
  local chars = #options[1].value + #options[1].label
  for _, command in ipairs(sf.commands.list()) do
    local size = #command.id + #command.title
    if #options >= MAX_OPTIONS or chars + size > MAX_OPTION_CHARS then break end
    options[#options + 1] = { value = command.id, label = command.title }
    chars = chars + size
  end
  sf.settings.setOptions('unlockedCommand', options)
end

local function timeOrCommand()
  local command = sf.settings.get('unlockedCommand')
  if command == nil or command == 'time' or isLocked() then
    vibrateTime()
    return
  end
  local ok, result = pcall(sf.commands.run, command)
  if not ok then
    sf.log.warn('Cannot run ' .. tostring(command) .. ': ' .. tostring(result))
  end
end

local ok, failure = pcall(listCommands)
if not ok then
  sf.log.warn('Cannot list the SandFly commands: ' .. tostring(failure))
end

sf.onCommand('vibrate_time', vibrateTime)
sf.onCommand('time_or_command', timeOrCommand)
