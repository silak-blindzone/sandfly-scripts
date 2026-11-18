local manifest = {
  id = 'wifi-tester',
  name = 'Wi-Fi tester',
  version = '1.0',
  author = 'Silak',
  description = 'Plays a tone whose pitch follows the Wi-Fi signal, low for weak and high for strong, so you can walk around and find the best spot. It says the network, signal and band when it starts and the best signal when it stops. Run the command again to stop early. Ported from a Jieshuo plugin.',
  minApiVersion = 4,
  testedApiVersion = 5,
  onDemand = true,
  permissions = { 'input', 'speech', 'java' },
  commands = {
    { id = 'toggle', title = 'Start or stop the Wi-Fi tester' },
  },
  settings = {
    { key = 'mode', type = 'list', title = 'Sound', default = 'tone',
      options = {
        { value = 'tone', label = 'Continuous tone' },
        { value = 'beeps', label = 'Beeps, faster for a stronger signal' },
        { value = 'speech', label = 'Speak the signal every 3 seconds' },
      } },
    { key = 'seconds', type = 'list', title = 'Stop after', default = '30',
      options = {
        { value = '15', label = '15 seconds' },
        { value = '30', label = '30 seconds' },
        { value = '60', label = '1 minute' },
        { value = '120', label = '2 minutes' },
        { value = '600', label = '10 minutes' },
      } },
    { key = 'markChanges', type = 'switch', title = 'Click on each new reading',
      summary = 'Android measures the signal about every 3 seconds. A higher click means better, a lower one worse.',
      default = true },
    { key = 'sayStart', type = 'switch', title = 'Say the network and signal at the start', default = true },
    { key = 'sayBest', type = 'switch', title = 'Say the best signal at the end', default = true },
  },
}

local tr = sf._

-- The tone of the original plugin: 20 steps from 110 to 523 Hz.
local MIN_FREQUENCY, MAX_FREQUENCY, LEVELS = 110, 523, 20
local TICK_MS = 150
-- Below this the signal is treated as none, as Android reports -127 when it has no value.
local NO_SIGNAL = -120

local TalkBackService = java.import('com.google.android.accessibility.talkback.TalkBackService')
local WifiManager = java.import('android.net.wifi.WifiManager')

local function wifiManager()
  local context = TalkBackService:getInstance()
  if context == nil then return nil end
  return context:getApplicationContext():getSystemService('wifi')
end

-- The connected network, or nil: { rssi, ssid, mhz, mbps }.
local function readWifi(wm)
  if wm == nil or not wm:isWifiEnabled() then return nil end
  local info = wm:getConnectionInfo()
  if info == nil or info:getNetworkId() == -1 then return nil end
  local rssi = info:getRssi()
  if rssi == nil or rssi < NO_SIGNAL then return nil end
  local ssid = tostring(info:getSSID() or ''):gsub('^"', ''):gsub('"$', '')
  -- Android hides the name without location access.
  if ssid == '' or ssid:find('unknown ssid', 1, true) then ssid = nil end
  return { rssi = rssi, ssid = ssid, mhz = info:getFrequency(), mbps = info:getLinkSpeed() }
end

local function level(rssi)
  return WifiManager:calculateSignalLevel(rssi, LEVELS) + 1
end

local function frequency(lvl)
  return MIN_FREQUENCY + (MAX_FREQUENCY - MIN_FREQUENCY) / (LEVELS - 1) * (lvl - 1)
end

local function quality(rssi)
  if rssi >= -50 then return tr('excellent') end
  if rssi >= -60 then return tr('very good') end
  if rssi >= -67 then return tr('good') end
  if rssi >= -75 then return tr('weak') end
  return tr('very weak')
end

local function band(mhz)
  if mhz == nil or mhz <= 0 then return nil end
  if mhz < 3000 then return '2.4 GHz' end
  if mhz < 5900 then return '5 GHz' end
  return '6 GHz'
end

local function signalText(w)
  return tr('{dbm} dBm, {quality}', { dbm = w.rssi, quality = quality(w.rssi) })
end

local function startText(w)
  local parts = {}
  if w.ssid ~= nil then parts[#parts + 1] = w.ssid end
  parts[#parts + 1] = signalText(w)
  local b = band(w.mhz)
  if b ~= nil then parts[#parts + 1] = b end
  if w.mbps ~= nil and w.mbps > 0 then parts[#parts + 1] = tr('{speed} Mb/s', { speed = w.mbps }) end
  return table.concat(parts, ', ')
end

-- Each run gets a number; running the command again stops the current run.
local run = 0
local running = false

local function measure()
  local wm = wifiManager()
  local first = readWifi(wm)
  if first == nil then
    sf.speak(tr('Wi-Fi isn\'t connected'), { interrupt = true })
    return
  end
  run = run + 1
  local mine = run
  running = true
  local mode = sf.settings.get('mode') or 'tone'
  local seconds = tonumber(sf.settings.get('seconds')) or 30
  local best = first
  if sf.settings.get('sayStart') ~= false then sf.speak(startText(first), { interrupt = true, wait = mode ~= 'tone' }) end

  local started = sf.clock()
  local nextBeep, nextSpeech = 0, sf.clock() + 3000
  local last = first
  local mark = sf.settings.get('markChanges') ~= false
  while running and run == mine and sf.clock() - started < seconds * 1000 do
    local w = readWifi(wm)
    if w ~= nil then
      -- A new reading from Android: a short click, higher if the signal got better.
      if mark and w.rssi ~= last.rssi then
        sf.playTone(w.rssi > last.rssi and 1500 or 700, 25)
      end
      last = w
      if w.rssi > best.rssi then best = w end
    end
    local lvl = w ~= nil and level(w.rssi) or 1
    local now = sf.clock()
    if mode == 'tone' then
      -- Overlapping a little, so that the tone sounds continuous.
      sf.playTone(frequency(lvl), TICK_MS + 30)
    elseif mode == 'beeps' and now >= nextBeep then
      sf.playTone(frequency(lvl), 60)
      -- From one beep a second for the weakest signal to about eight for the strongest.
      nextBeep = now + 1000 - (lvl - 1) * 45
    elseif mode == 'speech' and now >= nextSpeech then
      sf.speak(w ~= nil and signalText(w) or tr('No signal'), { interrupt = true })
      nextSpeech = now + 3000
    end
    sf.sleep(TICK_MS)
  end
  if run ~= mine then return end
  running = false
  if sf.settings.get('sayBest') ~= false then
    sf.speak(tr('Stopped. Best signal {best}, last {last}.', { best = signalText(best), last = signalText(last) }),
      { interrupt = true })
  else
    sf.speak(tr('Stopped'), { interrupt = true })
  end
end

sf.onCommand('toggle', function()
  if running then
    running = false
    return
  end
  measure()
end)
