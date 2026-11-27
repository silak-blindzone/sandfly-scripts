local manifest = {
  id = 'chatgpt-access',
  name = 'Accessible ChatGPT',
  version = '2.2',
  author = 'Silak',
  description = 'ChatGPT with a screen reader: reads a whole answer at once in a window you can read by line, word and character, skips the buttons under an answer when swiping and puts them in its Actions menu, says You before your messages, describes or reads the text of pictures in the conversation, pages through the conversation, announces a finished answer and names the message field.',
  minApiVersion = 5,
  testedApiVersion = 5,
  apps = { 'com.openai.chatgpt' },
  permissions = { 'screen', 'speech', 'actions', 'input', 'dialogs', 'clipboard' },
  settings = {
    { key = 'markYou', type = 'switch', title = 'Say You before your messages', default = true },
    { key = 'announceDone', type = 'switch', title = 'Announce a finished answer', default = true },
    { key = 'autoRead', type = 'switch', title = 'Read a finished answer at once', summary = 'Opens it in the reading window', default = false },
    { key = 'debugLog', type = 'switch', title = 'Write to the log', summary = 'For finding problems: logs what the script does', default = false },
  },
  commands = {
    { id = 'readLast', title = 'Read the last answer', menu = true },
    { id = 'page', title = 'Page through the conversation', control = true },
  },
  rules = {
    -- The message field has no description, only a hint above it.
    { match = { className = 'EditText' }, label = 'Message to ChatGPT' },
    -- The buttons under an answer: swiping skips them, and the Actions menu of the answer has
    -- them. Their names in Slovak, Czech and English.
    { match = { clickable = true, has = { contentDescription = 'Kopírovať' }, inside = { scrollable = true } }, hide = 'all' },
    { match = { clickable = true, has = { contentDescription = 'Dobrá odpoveď' }, inside = { scrollable = true } }, hide = 'all' },
    { match = { clickable = true, has = { contentDescription = 'Zlá odpoveď' }, inside = { scrollable = true } }, hide = 'all' },
    { match = { clickable = true, has = { contentDescription = 'Prečítať nahlas' }, inside = { scrollable = true } }, hide = 'all' },
    { match = { clickable = true, has = { contentDescription = 'Zdieľať' }, inside = { scrollable = true } }, hide = 'all' },
    { match = { clickable = true, has = { contentDescription = 'Ďalšie akcie' }, inside = { scrollable = true } }, hide = 'all' },
    { match = { clickable = true, has = { contentDescription = 'Kopírovat' }, inside = { scrollable = true } }, hide = 'all' },
    { match = { clickable = true, has = { contentDescription = 'Dobrá odpověď' }, inside = { scrollable = true } }, hide = 'all' },
    { match = { clickable = true, has = { contentDescription = 'Špatná odpověď' }, inside = { scrollable = true } }, hide = 'all' },
    { match = { clickable = true, has = { contentDescription = 'Přečíst nahlas' }, inside = { scrollable = true } }, hide = 'all' },
    { match = { clickable = true, has = { contentDescription = 'Sdílet' }, inside = { scrollable = true } }, hide = 'all' },
    { match = { clickable = true, has = { contentDescription = 'Další akce' }, inside = { scrollable = true } }, hide = 'all' },
    { match = { clickable = true, has = { contentDescription = 'Copy' }, inside = { scrollable = true } }, hide = 'all' },
    { match = { clickable = true, has = { contentDescription = 'Good response' }, inside = { scrollable = true } }, hide = 'all' },
    { match = { clickable = true, has = { contentDescription = 'Bad response' }, inside = { scrollable = true } }, hide = 'all' },
    { match = { clickable = true, has = { contentDescription = 'Read aloud' }, inside = { scrollable = true } }, hide = 'all' },
    { match = { clickable = true, has = { contentDescription = 'Share' }, inside = { scrollable = true } }, hide = 'all' },
    { match = { clickable = true, has = { contentDescription = 'More actions' }, inside = { scrollable = true } }, hide = 'all' },
    { match = { clickable = true, has = { text = 'Zdroje' }, inside = { scrollable = true } }, hide = 'all' },
    { match = { clickable = true, has = { text = 'Sources' }, inside = { scrollable = true } }, hide = 'all' },
  },
}

local tr = sf._

-- Fallback names, used only when the screen's layout doesn't match: the Copy button under an
-- answer, and the button that stops an answer being written.
local COPY = { 'Copy', 'Kopírovať' }
local STOP = { 'Stop', 'Stop generating', 'Stop streaming', 'Zastaviť', 'Zastaviť generovanie', 'Zastaviť streamovanie' }
local SCROLL_FORWARD = 4096

local function log(text)
  if sf.settings.get('debugLog') then sf.log.info(text) end
end

local function top(item) return item.bounds and item.bounds.top or 0 end
local function nonEmpty(s) return s ~= nil and s ~= '' end

-- One search of the screen, which the checks below share, as every call to ChatGPT takes time.
local function snapshot()
  return sf.screen.findAll({ visible = true }, 300)
end

-- Rows of buttons under answers, found by layout rather than by language: at least four small
-- clickable items without text at one height. Sorted top to bottom, each row left to right.
local function actionRows(nodes)
  local width = sf.device.info().screen.width
  local rows = {}
  for _, n in ipairs(nodes) do
    local b = n.bounds
    if n.clickable and b and not nonEmpty(n.text) and b.right - b.left < width * 0.15 and b.bottom > b.top then
      local row
      for _, r in ipairs(rows) do
        if math.abs(r.top - b.top) <= 8 then row = r break end
      end
      if row == nil then
        row = { top = b.top, bottom = b.bottom, items = {} }
        rows[#rows + 1] = row
      end
      row.items[#row.items + 1] = n
    end
  end
  local result = {}
  for _, r in ipairs(rows) do
    if #r.items >= 4 then
      table.sort(r.items, function(a, b) return a.bounds.left < b.bounds.left end)
      result[#result + 1] = r
    end
  end
  table.sort(result, function(a, b) return a.top < b.top end)
  return result
end

-- The conversation's texts top to bottom, without the top bar and the message field.
local function visibleTexts(nodes)
  local height = sf.device.info().screen.height
  local list = {}
  for _, t in ipairs(nodes) do
    local b = t.bounds
    if t.className ~= nil and t.className:sub(-8) == 'TextView' and b and b.bottom > b.top
        and b.top > height * 0.12 and b.bottom < height * 0.88 then
      list[#list + 1] = t
    end
  end
  table.sort(list, function(a, b) return top(a) < top(b) end)
  return list
end

-- The Copy buttons top to bottom: the first in each row under an answer, or by name.
local function copyButtons(nodes)
  local list = {}
  for _, row in ipairs(actionRows(nodes)) do list[#list + 1] = row.items[1] end
  if #list > 0 then return list end
  for _, n in ipairs(nodes) do
    for _, name in ipairs(COPY) do
      if n.contentDescription == name then list[#list + 1] = n end
    end
  end
  table.sort(list, function(a, b) return top(a) < top(b) end)
  return list
end

-- Copies an answer with its Copy button, shows it for reading, and puts the clipboard back.
local function readAnswer(copy)
  local button = copy
  if not button.clickable then
    local p = button:parent()
    if p ~= nil and p.clickable then button = p end
  end
  local before = sf.clipboard.get()
  local marker = '\1sandfly\1'
  sf.clipboard.set(marker)
  if not button:click() then button:tap() end
  local text
  for _ = 1, 20 do
    sf.sleep(100)
    text = sf.clipboard.get()
    if text ~= nil and text ~= marker then break end
  end
  sf.clipboard.set(before or '')
  if text == nil or text == marker or text == '' then
    log('Copying the answer failed')
    sf.speak(tr('Could not read the answer'), { interrupt = true })
    return
  end
  log('Answer: ' .. #text .. ' characters')
  sf.ui.text(tr('ChatGPT answer'), text)
end

local function readLast()
  local buttons = copyButtons(snapshot())
  if #buttons == 0 then
    sf.speak(tr('There is no answer on the screen. Move to one or to the end of the conversation.'), { interrupt = true })
    return
  end
  readAnswer(buttons[#buttons])
end

sf.onCommand('readLast', function() readLast() end)

-- Pages the conversation back or forward and focuses the first text.
sf.onCommand('page', function(event)
  local list = sf.screen.find({ scrollable = true })
  if list == nil then
    sf.speak(tr('This list can not be scrolled'), { interrupt = true })
    return
  end
  local back = event.direction == 'previous'
  local moved = back and list:scrollBackward() or (not back and list:scrollForward())
  if not moved then
    sf.speak(back and tr('Start of conversation') or tr('End of conversation'), { interrupt = true })
    return
  end
  sf.sleep(500)
  local texts = visibleTexts(snapshot())
  if texts[1] then texts[1]:focus() end
end)

-- Telling that ChatGPT has finished an answer, by layout: while it writes, text keeps appearing
-- below the last row of buttons, at the end of the conversation. The Stop button's name is a
-- fallback. One search of the screen serves both checks.
local function atConversationEnd()
  local list = sf.screen.find({ scrollable = true })
  if list == nil then return true end
  for _, a in ipairs(list.actions or {}) do
    if a.id == SCROLL_FORWARD then return false end
  end
  return true
end

local function isWriting()
  local nodes = snapshot()
  for _, n in ipairs(nodes) do
    for _, name in ipairs(STOP) do
      if n.contentDescription == name then return true end
    end
  end
  if not atConversationEnd() then return false end
  local rows = actionRows(nodes)
  if #rows == 0 then return false end
  local last = rows[#rows]
  for _, t in ipairs(visibleTexts(nodes)) do
    if top(t) > last.bottom then return true end
  end
  return false
end

local writing = false
local function checkAnswer()
  local now = isWriting()
  if now ~= writing then log(now and 'ChatGPT started writing' or 'ChatGPT finished') end
  if writing and not now then
    if sf.settings.get('autoRead') then
      sf.sleep(500)
      readLast()
    elseif sf.settings.get('announceDone') then
      sf.speak(tr('The answer is finished'))
    end
  end
  writing = now
end

local pending = false
local function scheduleCheck()
  if pending then return end
  pending = true
  sf.setTimeout(function()
    pending = false
    checkAnswer()
  end, 600)
end

sf.onContentChange(scheduleCheck)
sf.onWindowChange(scheduleCheck)

-- Your messages are bubbles at the right edge; the answers start at the left edge, and the
-- Sources button under an answer ends before the right edge.
local screenWidth = sf.device.info().screen.width

local function isYours(item)
  local b = item.bounds
  return b ~= nil and item.className ~= nil and item.className:sub(-8) == 'TextView'
    and b.left > screenWidth * 0.12 and b.right > screenWidth * 0.9
end

sf.onFocus(function(item)
  if sf.settings.get('markYou') ~= false and isYours(item) then
    return { before = tr('You:') }
  end
end)

-- Pictures in the conversation, by the names ChatGPT gives them.
local PICTURE = { ['Obrázok'] = true, ['Obrázek'] = true, ['Image'] = true }

local function isPicture(item)
  return item ~= nil and PICTURE[item.contentDescription or ''] == true
end

local function describePicture(item)
  item:focus()
  local ok, ran = pcall(sf.commands.run, 'DESCRIBE_IMAGE')
  if not ok or not ran then
    sf.speak(tr('Could not describe the picture'), { interrupt = true })
  end
end

local function readPictureText(item)
  local ok, result = pcall(item.recognizeText, item)
  local text = ok and result and result.text or ''
  text = text:gsub('^%s+', ''):gsub('%s+$', '')
  if text == '' then
    sf.speak(tr('There is no text in the picture, or it is not all on the screen'), { interrupt = true })
    return
  end
  sf.ui.text(tr('Text in the picture'), text)
end

-- The row of buttons under the answer that the item is in.
local function rowBelow(node, nodes)
  local y = top(node)
  for _, row in ipairs(actionRows(nodes)) do
    if row.top >= y then return row end
  end
  return nil
end

-- The name of a button in a row: its own description, or the text of an item inside it.
local function buttonName(button)
  if nonEmpty(button.contentDescription) then return button.contentDescription end
  for _, inner in ipairs(button:findAll({ visible = true }, 5)) do
    if nonEmpty(inner.contentDescription) then return inner.contentDescription end
    if nonEmpty(inner.text) then return inner.text end
  end
  return nil
end

-- On an answer's text: read the whole answer, or choose one of the buttons under it, by the
-- names ChatGPT gives them. The menu itself asks ChatGPT nothing, so it opens at once.
sf.onActions(function(item)
  if isPicture(item) then
    return {
      { title = tr('Describe the picture'), first = true, run = describePicture },
      { title = tr('Read the text in the picture'), first = true, run = readPictureText },
    }
  end
  if item == nil or item.className == nil or item.className:sub(-8) ~= 'TextView' then return nil end
  return {
    {
      title = tr('Read the whole answer'),
      first = true,
      run = function(node)
        local row = rowBelow(node, snapshot())
        if row ~= nil then readAnswer(row.items[1]) else readLast() end
      end,
    },
    {
      title = tr('Buttons under the answer'),
      first = true,
      run = function(node)
        local row = rowBelow(node, snapshot())
        if row == nil then
          sf.speak(tr('There are no buttons under this answer on the screen'), { interrupt = true })
          return
        end
        local options = {}
        for i, b in ipairs(row.items) do
          options[#options + 1] = { value = i, label = buttonName(b) or tr('Button {n}', { n = i }) }
        end
        local chosen = sf.ui.choose(tr('Buttons under the answer'), options)
        local button = chosen and row.items[chosen]
        if button ~= nil and not button:click() then button:tap() end
      end,
    },
  }
end)
