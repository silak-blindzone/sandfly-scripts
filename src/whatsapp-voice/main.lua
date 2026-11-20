local manifest = {
  id = 'whatsapp-voice',
  name = 'WhatsApp voice message',
  version = '3.2',
  author = 'Silak',
  description = 'In a WhatsApp chat, the first gesture starts and locks a voice message, and the second sends it. While the recording starts, SandFly is muted and touch is locked, so that nothing ends up in the message and a stray touch can\'t cancel it.',
  minApiVersion = 6,
  testedApiVersion = 6,
  apps = {
    { package = 'com.whatsapp', activity = 'Conversation' },
  },
  permissions = { 'input', 'screen', 'actions', 'speech' },
  commands = {
    { id = 'voice', title = 'Record or send a voice message' },
  },
}

local tr = sf._

-- How far and how fast to drag up from the microphone so that the recording locks. WhatsApp
-- locks it even with a drag of 10 milliseconds; this leaves a margin. A short drag keeps the time
-- when the user's own touch could reach the app, while the script's drag passes the touch lock,
-- short.
local LOCK_DISTANCE = 600 -- pixels
local LOCK_DURATION = 60 -- milliseconds
-- The mute lasts until WhatsApp has scrolled the chat to its end and moved focus to the recording
-- bar, and at most this long after the lock. It also covers the sound of that scroll, so the chat
-- needn't be scrolled to its end first.
local AFTER_LOCK = 1200 -- milliseconds
local SETTLE = 150 -- milliseconds after the focus moved

-- WhatsApp's ids, which don't depend on the language.
local MIC = 'voice_note_btn' -- the microphone, while the message field is empty
local SEND = 'draft_send_v2' -- Send, shown only while a locked recording runs

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
  local b = mic.bounds
  local x = (b.left + b.right) // 2
  local y = (b.top + b.bottom) // 2
  local before = focusKey(sf.screen.focused())
  local start = sf.clock()
  lock = sf.touch.lock(6000)
  mute = sf.feedback.mute({ speech = true, sounds = true, vibration = true }, 6000)
  -- Touches the microphone and drags it up: the recording starts and locks.
  local ok = sf.touch.gesture({
    {
      points = { { x = x, y = y }, { x = x, y = math.max(0, y - LOCK_DISTANCE) } },
      start = 0,
      duration = LOCK_DURATION,
    },
  })
  if not ok then
    unmute()
    sf.speak(tr('Could not start recording'), { interrupt = true })
    return
  end
  -- Checks that the recording really locked: Send appears.
  if sf.screen.waitFor(SEND, 1500, 50) == nil then
    unmute()
    sf.speak(tr('The recording didn\'t lock'), { interrupt = true })
    return
  end
  unmuteAfterFocusJump(before, AFTER_LOCK, sf.clock() - start)
end

sf.onCommand('voice', function()
  -- A locked recording is running: send it.
  local send = sf.screen.find(SEND)
  if send ~= nil then
    if not send:click() then send:tap() end
    return
  end
  -- Otherwise start recording, if the message field is empty and the microphone is shown.
  local mic = sf.screen.find(MIC)
  if mic == nil then
    sf.speak(tr('Could not find the voice message button. Is the message field empty?'), { interrupt = true })
    return
  end
  startRecording(mic)
end)
