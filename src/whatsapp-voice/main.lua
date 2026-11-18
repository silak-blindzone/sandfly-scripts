local manifest = {
  id = 'whatsapp-voice',
  name = 'WhatsApp voice message',
  version = '3.1',
  author = 'Silak',
  description = 'In a WhatsApp chat, the first gesture starts and locks a voice message, and the second sends it. While the recording starts, SandFly is muted, so that nothing ends up in the message; touching the screen ends the mute.',
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

-- How far and how slowly to drag up from the microphone so that the recording locks.
local LOCK_DISTANCE = 600 -- pixels
local LOCK_DURATION = 1500 -- milliseconds
-- How long the mute lasts after the lock, for WhatsApp scrolling the chat to its end and for its
-- jump of focus to the recording bar. The mute also covers the sound of that scroll, so the chat
-- needn't be scrolled to its end first.
local AFTER_LOCK = 1200 -- milliseconds

-- WhatsApp's ids, which don't depend on the language.
local MIC = 'voice_note_btn' -- the microphone, while the message field is empty
local SEND = 'draft_send_v2' -- Send, shown only while a locked recording runs

-- SandFly's mute: speech, sounds and vibration. It ends on its own after the time given, and
-- when the user touches the screen; the script's own touches don't end it.
local mute = nil

local function unmute()
  if mute ~= nil then
    pcall(function() mute:release() end)
    mute = nil
  end
end

local function unmuteAfter(ms)
  local handle = mute
  if handle == nil then return end
  sf.setTimeout(function()
    if mute == handle then unmute() end
  end, ms)
end

local function startRecording(mic)
  local b = mic.bounds
  local x = (b.left + b.right) // 2
  local y = (b.top + b.bottom) // 2
  mute = sf.feedback.mute({ speech = true, sounds = true, vibration = true }, 6000)
  -- Touches the microphone and drags it up slowly: the recording starts and locks.
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
  if sf.screen.waitFor(SEND, 1500, 100) == nil then
    unmute()
    sf.speak(tr('The recording didn\'t lock'), { interrupt = true })
    return
  end
  unmuteAfter(AFTER_LOCK)
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
