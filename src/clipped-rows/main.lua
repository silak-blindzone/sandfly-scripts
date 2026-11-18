local manifest = {
  id = 'clipped-rows',
  name = 'Whole rows at the edge',
  version = '2.0',
  author = 'Silak',
  description = 'SandFly reads a list row that is half under the navigation or status bar as just its position, such as "11 of 26". This adds the texts in the row. It works in any language.',
  minApiVersion = 2,
  testedApiVersion = 5,
  permissions = { 'screen', 'speech' },
  settings = {
    { key = 'debugLog', type = 'switch', title = 'Write to the log', summary = 'For finding problems: logs each row it completes', default = false },
  },
}

-- Rows this close to the top or bottom of the screen can be under the status or navigation bar.
local EDGE = 260

-- Apps whose rows another script reads, so that a row isn't read twice: Aaron's WhatsApp
-- messages, and Accessible Zedge.
local SKIP_PACKAGES = {
  ['com.whatsapp'] = true,
  ['com.whatsapp.w4b'] = true,
  ['net.zedge.android'] = true,
}

local screenHeight = nil
local function height()
  if screenHeight == nil then
    local info = sf.device.info()
    screenHeight = (info and info.screen and info.screen.height) or 2400
  end
  return screenHeight
end

local function trim(s) return (s or ''):gsub('^%s+', ''):gsub('%s+$', '') end

-- The texts in the row that SandFly didn't say, or nil when it said one, as the row isn't cut off.
local function missingTexts(item, said)
  local missing = {}
  for _, child in ipairs(item:findAll({}, 8)) do
    local t = trim(child.text)
    if t == '' then t = trim(child.contentDescription) end
    if t ~= '' then
      if said:find(t, 1, true) then return nil end
      missing[#missing + 1] = t
    end
  end
  if #missing == 0 then return nil end
  return missing
end

-- onFocus decides from the item alone, with no call to the app, as SandFly gives it only 30 ms.
-- For a row at the edge, it keeps SandFly quiet, and a timer reads the row's texts and says
-- what's needed, unless focus has moved on by then.
local focusCount = 0
sf.onFocus(function(item, said)
  focusCount = focusCount + 1
  if SKIP_PACKAGES[item.packageName or ''] then return nil end
  if item.text ~= nil or item.contentDescription ~= nil then return nil end
  if (item.childCount or 0) == 0 then return nil end
  local b = item.bounds
  if b == nil or (b.bottom < height() - EDGE and b.top > EDGE) then return nil end

  said = said or ''
  local count = focusCount
  sf.setTimeout(function()
    local ok, missing = pcall(missingTexts, item, said)
    if count ~= focusCount then return end
    local text = said
    if ok and missing ~= nil then
      if sf.settings.get('debugLog') then sf.log('Added: ' .. table.concat(missing, ', ') .. ' | was: ' .. said) end
      local extra = table.concat(missing, ', ')
      text = trim(said) == '' and extra or (extra .. ', ' .. said)
    end
    if trim(text) ~= '' then sf.speak(text, { interrupt = true }) end
  end, 0)
  return false
end)
