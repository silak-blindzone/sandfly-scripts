local manifest = {
  id = 'telegram-voice',
  name = 'Telegram voice message',
  version = '2.2',
  author = 'Silak',
  description = 'In a Telegram chat, the first gesture starts and locks a voice message, and the second sends it. While the recording starts, SandFly is muted and touch is locked, so that nothing ends up in the message and a stray touch can\'t cancel it. It finds the buttons by their place on the screen, so it works in any language.',
  minApiVersion = 6,
  testedApiVersion = 6,
  apps = { 'org.telegram.messenger' },
  permissions = { 'input', 'screen', 'actions', 'speech' },
  commands = {
    { id = 'voice', title = 'Record or send a voice message' },
  },
}

local tr = sf._

-- How far and how fast to drag up from the microphone so that the recording locks. Telegram
-- starts recording only after a press of about 230 milliseconds; a shorter one is a tap, which
-- switches the button between voice and video messages. This leaves a margin.
local LOCK_DISTANCE = 600 -- pixels
local LOCK_DURATION = 270 -- milliseconds
-- The mute lasts until Telegram has shown its hint and moved focus to the recording bar, and at
-- most this long after the lock.
local AFTER_LOCK = 1500 -- milliseconds
local SETTLE = 150 -- milliseconds after the focus moved

local function center(item)
  local b = item.bounds
  return (b.left + b.right) // 2, (b.top + b.bottom) // 2
end

local function contains(item, x, y)
  local b = item.bounds
  return b ~= nil and x >= b.left and x <= b.right and y >= b.top and y <= b.bottom
end

-- The message field: the only edit field in the bottom bar.
local function messageField()
  local height = sf.device.info().screen.height
  for _, it in ipairs(sf.screen.findAll({ className = 'EditText', visible = true }, 10)) do
    if it.bounds ~= nil and it.bounds.top > height * 0.6 then return it end
  end
  return nil
end

-- The items with a description to the right of the message field, in its row. With an empty
-- field these are the attach button and the microphone; once there is text, Telegram hides the
-- attach button and shows only Send. This goes by place, not by name.
local function buttonsBeside(field)
  local fb = field.bounds
  local list = {}
  for _, it in ipairs(sf.screen.findAll({ visible = true }, 200)) do
    local b = it.bounds
    if b ~= nil and it.contentDescription ~= nil and it.contentDescription ~= ''
        and b.left >= fb.right and b.top < fb.bottom and b.bottom > fb.top then
      list[#list + 1] = it
    end
  end
  table.sort(list, function(a, b) return a.bounds.left < b.bounds.left end)
  return list
end

-- Whether the field is empty. Telegram shows its hint as the field's text when it's empty, so
-- the text alone can't tell; the buttons beside it can.
local function isEmpty(field, buttons)
  if field.text == nil or field.text == '' then return true end
  if field.hint ~= nil and field.text == field.hint then return true end
  return #buttons >= 2
end

-- While a locked recording runs, the message field is gone and an item covers the spot where
-- the microphone was: Send.
local micX, micY = nil, nil
local function sendButton()
  if micX == nil or messageField() ~= nil then return nil end
  for _, it in ipairs(sf.screen.findAll({ visible = true }, 200)) do
    if (it.text ~= nil or it.contentDescription ~= nil) and contains(it, micX, micY) then return it end
  end
  return nil
end

-- SandFly's mute: speech, sounds and vibration. It ends on its own after the time given.
local mute = nil
-- The touch lock for the same time: the user's touches neither reach the app, where they could
-- cancel the drag, nor end the mute; the script's own drag still goes to the app. The mute also
-- silences any feedback of touches while touch is locked. Both volume keys end the lock.
local lock = nil

local function unmute()
  if lock ~= nil then
    pcall(function() lock:release() end)
    lock = nil
  end
  if mute ~= nil then
    pcall(function() mute:release() end)
    mute = nil
  end
end

-- Where focus is, to tell when it moves.
local function focusKey(item)
  if item == nil then return '' end
  local b = item.bounds or {}
  return table.concat({ item.id or '', item.text or '', item.contentDescription or '',
    tostring(b.left), tostring(b.top) }, '|')
end

-- Waits for the app's jump of focus to the recording bar at the bottom of the screen, at most
-- `ms`, and gives how long it took, or nil.
local function waitForFocusJump(before, ms)
  local height = sf.device.info().screen.height
  local start = sf.clock()
  while sf.clock() - start < ms do
    local f = sf.screen.focused()
    if f ~= nil and f.bounds ~= nil and focusKey(f) ~= before and f.bounds.top > height * 0.75 then
      return sf.clock() - start
    end
    sf.sleep(50)
  end
  return nil
end

-- Ends the mute once the app has moved focus to the recording bar, so that SandFly doesn't say
-- it into the message, and no later than `ms`.
local function unmuteAfterFocusJump(before, ms, lockedAfter)
  local jump = waitForFocusJump(before, ms)
  -- What SandFly would say about the new focus is dropped while muted; a moment more for it.
  if jump ~= nil then sf.sleep(SETTLE) end
  sf.log(string.format('Locked after %d ms; focus moved %s', lockedAfter,
    jump and string.format('%d ms after that', jump) or 'not seen'))
  unmute()
end

local function startRecording(mic)
  micX, micY = center(mic)
  local before = focusKey(sf.screen.focused())
  local start = sf.clock()
  lock = sf.touch.lock(6000)
  mute = sf.feedback.mute({ speech = true, sounds = true, vibration = true }, 6000)
  -- Touches the microphone and drags it up: the recording starts and locks.
  local ok = sf.touch.gesture({
    {
      points = { { x = micX, y = micY }, { x = micX, y = math.max(0, micY - LOCK_DISTANCE) } },
      start = 0,
      duration = LOCK_DURATION,
    },
  })
  if not ok then
    unmute()
    sf.speak(tr('Could not start recording'), { interrupt = true })
    return
  end
  -- Waits until the recording is locked: the message field is gone and Send is in its place.
  for _ = 1, 30 do
    if sendButton() ~= nil then
      unmuteAfterFocusJump(before, AFTER_LOCK, sf.clock() - start)
      return
    end
    sf.sleep(50)
  end
  unmute()
  sf.speak(tr('The recording didn\'t lock'), { interrupt = true })
end

sf.onCommand('voice', function()
  -- A locked recording is running: send it.
  local send = sendButton()
  if send ~= nil then
    if not send:click() then send:tap() end
    return
  end
  local field = messageField()
  if field == nil then
    sf.speak(tr('This works in a chat, where the message field is shown'), { interrupt = true })
    return
  end
  local buttons = buttonsBeside(field)
  if not isEmpty(field, buttons) then
    sf.speak(tr('There is text in the message field. Record a voice message with the field empty.'),
      { interrupt = true })
    return
  end
  -- The microphone is the right-most of them.
  local mic = buttons[#buttons]
  if mic == nil then
    sf.speak(tr('Could not find the voice message button'), { interrupt = true })
    return
  end
  startRecording(mic)
end)
