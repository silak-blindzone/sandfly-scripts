local manifest = {
  id = 'translate-focused',
  name = 'Translate the focused text',
  version = '3.1',
  author = 'Silak',
  description = 'Translates the focused item\'s text into the phone\'s language with Google Translate (NVDA-style endpoint plus a PA endpoint fallback), and reads the translation. When Google can\'t be reached, it uses the service in SandFly\'s Translation settings. A name or number that can\'t be translated is read as it is.',
  minApiVersion = 2,
  testedApiVersion = 5,
  onDemand = true,
  permissions = { 'screen', 'network', 'speech' },
  commands = {
    { id = 'translate', title = 'Translate the focused text' },
  },
}

local tr = sf._

local function trim(s) return (s or ''):gsub('^%s+', ''):gsub('%s+$', '') end

-- Why SandFly's own translation failed, as it reports it ("Translation failed: KIND").
local function reasons()
  return {
    DETECTION_DOWNLOADING = tr('Language detection is still downloading. Try again in a moment.'),
    CONNECTION = tr('The translation service can\'t be reached.'),
    NOT_SET_UP = tr('The translation service isn\'t set up.'),
    QUOTA = tr('The translation service has used up its limit.'),
    API_KEY = tr('The translation service\'s key isn\'t valid.'),
  }
end

-- The item's text, or for an item without one, such as a list row, the texts inside it.
local function focusedText()
  local item = sf.screen.focused()
  if item == nil then return nil end
  local own = trim(item.text)
  if own == '' then own = trim(item.contentDescription) end
  if own ~= '' then return own end
  local parts = {}
  for _, child in ipairs(item:findAll({ visible = true }, 50)) do
    local t = trim(child.text)
    if t == '' then t = trim(child.contentDescription) end
    if t ~= '' then parts[#parts + 1] = t end
  end
  if #parts > 0 then return table.concat(parts, '. ') end
  return nil
end

-- The phone's language, such as 'sk' or 'en'.
local function targetLanguage()
  local tag = (sf.language and sf.language()) or (sf.locale and sf.locale()) or 'en'
  return (tag:match('^%a+') or 'en'):lower()
end

local function urlEncode(str)
  return (str:gsub('[^%w%-%._~]', function(c) return string.format('%%%02X', string.byte(c)) end))
end

-- Google Translate's free service, the one Instant Translate in NVDA uses. Gives the
-- translation, or nil.
-- Google's translation endpoint, following the request format used by
-- NVDA Instant Translate: Mozilla User-Agent and the dj=1 JSON response.
local function googleTranslate(text)
  local url = 'https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl='
    .. targetLanguage() .. '&dt=t&dj=1&q=' .. urlEncode(text)
  local ok, res = pcall(sf.fetch, url, {
    method = 'GET',
    headers = {
      ['User-Agent'] = 'Mozilla/5.0',
      ['Accept'] = 'application/json, text/plain, */*',
    },
    timeout = 15000, -- milliseconds
  })
  if not ok or res == nil or not res.ok then
    sf.log('Google error: ' .. tostring(ok and res and res.status or res))
    return nil
  end
  local okJson, data = pcall(function() return res:json() end)
  if not okJson or type(data) ~= 'table' then return nil end

  -- dj=1 returns an object with a sentences array.
  local parts = {}
  if type(data.sentences) == 'table' then
    for _, sentence in ipairs(data.sentences) do
      if type(sentence) == 'table' and type(sentence.trans) == 'string' then
        parts[#parts + 1] = sentence.trans
      end
    end
  -- Retain compatibility with the older compact response format.
  elseif type(data[1]) == 'table' then
    for _, segment in ipairs(data[1]) do
      if type(segment) == 'table' and type(segment[1]) == 'string' then
        parts[#parts + 1] = segment[1]
      end
    end
  end

  local out = trim(table.concat(parts))
  if out == '' then return nil end
  return out
end

-- Alternative Google Translate endpoint used by several community translators.
-- This is a publicly shared key, not a private key belonging to this project.
local GOOGLE_PA_API_KEY = 'AIzaSyDLEeFI5OtFBwYBIoK_jj5m32rZK5CkCXA'

local function googleTranslatePA(text)
  local url = 'https://translate-pa.googleapis.com/v1/translate?params.client=gtx'
    .. '&dataTypes=TRANSLATION'
    .. '&key=' .. GOOGLE_PA_API_KEY
    .. '&query.sourceLanguage=auto'
    .. '&query.targetLanguage=' .. targetLanguage()
    .. '&query.text=' .. urlEncode(text)
  local ok, res = pcall(sf.fetch, url, {
    method = 'GET',
    headers = {
      ['User-Agent'] = 'Mozilla/5.0',
      ['Accept'] = 'application/json, text/plain, */*',
    },
    timeout = 15000,
  })
  if not ok or res == nil or not res.ok then
    sf.log('Google PA error: ' .. tostring(ok and res and res.status or res))
    return nil
  end
  local okJson, data = pcall(function() return res:json() end)
  if not okJson or type(data) ~= 'table' then return nil end
  local out = trim(data.translation)
  if out == '' then return nil end
  return out
end

sf.onCommand('translate', function()
  local text = focusedText()
  if text == nil then
    sf.speak(tr('The focused item has no text to translate'), { interrupt = true })
    return
  end
  -- Try SandFly's configured translation service first.
  local ok, result = pcall(sf.translate, text)
  if ok and result ~= nil and trim(result.text) ~= '' then
    sf.speak(result.text, { interrupt = true })
    return
  end

  -- If the configured service fails, try Google's free endpoint and then its PA endpoint.
  local translated = googleTranslate(text)
  if translated == nil then translated = googleTranslatePA(text) end
  if translated ~= nil then
    sf.speak(translated, { interrupt = true })
    return
  end

  if not ok then
    local err = tostring(result)
    sf.log('Translation error: ' .. err)
    -- A name, a number or a language the service doesn't know: read the text as it is.
    if err:find('NOT_DETECTED', 1, true) or err:find('LANGUAGE', 1, true) then
      sf.speak(text, { interrupt = true })
      return
    end
    local reason = tr('Check the translation service in SandFly\'s settings.')
    for kind, message in pairs(reasons()) do
      if err:find(kind, 1, true) then reason = message break end
    end
    sf.speak(tr('Translation failed.') .. ' ' .. reason, { interrupt = true })
    return
  end
  sf.speak(text, { interrupt = true })
end)
