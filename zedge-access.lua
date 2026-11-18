local manifest = {
  id = 'zedge-access',
  name = 'Accessible Zedge',
  version = '2.2',
  author = 'Silak',
  description = 'Accessibility fixes for Zedge: names on Play buttons, prices of paid items, one-step download of free items, named tabs, numbered wallpapers, collections with their contents, alarm time, days and choices, credit offers, and closing Zedge pop-ups.',
  minApiVersion = 5,
  testedApiVersion = 5,
  apps = { 'net.zedge.android' },
  permissions = { 'screen', 'speech', 'actions', 'input', 'dialogs' },
  settings = {
    { key = 'autoClose', type = 'switch', title = 'Close Zedge pop-ups', default = true },
    { key = 'debugLog', type = 'switch', title = 'Write to log', summary = 'For troubleshooting: writes what the script does to its log', default = false },
  },
  commands = {
    { id = 'download', title = 'Download to device' },
    { id = 'alarmTime', title = 'Set alarm time' },
  },
  rules = {
    { id = 'downloadIcon', label = 'Download count' },
    { id = 'actionButton', label = 'See all' },
    { id = 'menu_overflow', label = 'More options' },
    { id = 'stroke', hide = true },
  },
}

-- Tabs in search results, in the order Zedge shows them.
local TAB_NAMES = { 'Wallpapers', 'Video wallpapers', 'Ringtones', 'Notification sounds', 'Collections' }

-- Days of the alarm, with the short names Zedge may use for them.
local DAYS = {
  monday = { 'Monday', 'Po', 'Mon' },
  tuesday = { 'Tuesday', 'Ut', 'Tue' },
  wednesday = { 'Wednesday', 'St', 'Wed' },
  thursday = { 'Thursday', 'Št', 'Thu' },
  friday = { 'Friday', 'Pi', 'Fri' },
  saturday = { 'Saturday', 'So', 'Sat' },
  sunday = { 'Sunday', 'Ne', 'Sun' },
}

-- Writes to the script's log, only with "Write to log" on.
local function log(text)
  if sf.settings.get('debugLog') then sf.log.info(text) end
end

-- Whether an item has this view id, short or full.
local function is(item, name)
  local id = item and item.id
  return id ~= nil and (id == name or id:sub(-(#name + 1)) == '/' .. name)
end

local function idStarts(item, prefix)
  local id = item and item.id
  if id == nil then return false end
  id = id:match('/(.*)$') or id
  return id:sub(1, #prefix) == prefix
end

local function idEnds(item, suffix)
  local id = item and item.id
  return id ~= nil and id:sub(-#suffix) == suffix
end

local function textOf(item)
  if item == nil then return nil end
  local t = item.text
  if t ~= nil and t ~= '' then return t end
  return nil
end

-- "Ƶ10" as "costs 10 credits".
local function priceText(pill)
  local t = textOf(pill)
  if t == nil then return nil end
  local n = t:match('[%d][%d%s,.]*')
  if n == nil then return nil end
  return 'costs ' .. n .. ' credits'
end

local function priceIn(container)
  if container == nil then return nil end
  return priceText(container:find({ id = 'pricePill' }))
end

-- All text inside an item, apart from one child, joined.
local function textsInside(item, skip)
  local parts = {}
  for _, child in ipairs(item:findAll({ visible = true }, 30)) do
    if skip == nil or child ~= skip then
      local t = textOf(child) or child.contentDescription
      if t ~= nil and t ~= '' and (skip == nil or t ~= textOf(skip)) then
        parts[#parts + 1] = t
      end
    end
  end
  return parts
end

-- The name of the sound a Play button belongs to, from the nearest items around it.
local function soundNear(button)
  local p = button:parent()
  for _ = 1, 3 do
    if p == nil then return nil end
    local d = p.contentDescription
    if d ~= nil and d ~= '' then return d, p end
    local t = textOf(p:find({ id = 'soundItemTitle' })) or textOf(p:find({ id = 'title' }))
    if t ~= nil then return t, p end
    p = p:parent()
  end
  return nil
end

-- What the screen holds, checked a moment after it changes.
local state = {
  onItemPage = false, -- an item's own page, with its Set button
  itemPrice = nil, -- the price of the item on that page, or nil when free
  timePicker = false, -- the alarm time picker is on screen
  chosen = {}, -- the alarm sound and mission chosen last, by list
}

-- Changes what is said, and logs it.
local function say(text)
  log('Focus: ' .. text)
  return text
end

-- The alarm time picker: its numbers, split into hours and minutes by the colon.
local function wheels(picker)
  local colonX, numbers = nil, {}
  for _, t in ipairs(picker:findAll({ className = 'TextView' }, 50)) do
    local text = textOf(t)
    local b = t.bounds
    if text == ':' then
      colonX = (b.left + b.right) / 2
    elseif text ~= nil and text:match('^%d+$') then
      numbers[#numbers + 1] = { item = t, value = tonumber(text), x = (b.left + b.right) / 2, y = (b.top + b.bottom) / 2 }
    end
  end
  if colonX == nil then return nil end
  local pb = picker.bounds
  local centerY = (pb.top + pb.bottom) / 2
  local result = { hours = {}, minutes = {}, centerY = centerY }
  for _, n in ipairs(numbers) do
    local column = n.x < colonX and result.hours or result.minutes
    column[#column + 1] = n
  end
  -- The selected number of each wheel is the one in the middle.
  for _, column in ipairs({ result.hours, result.minutes }) do
    table.sort(column, function(a, b) return a.y < b.y end)
    local best
    for _, n in ipairs(column) do
      if best == nil or math.abs(n.y - centerY) < math.abs(best.y - centerY) then best = n end
    end
    column.selected = best
    column.rowHeight = #column > 1 and (column[#column].y - column[1].y) / (#column - 1) or 192
    column.x = best and best.x
  end
  return result
end

-- Works out what to say for a focused item, or nil to keep SandFly's text. It asks Zedge
-- for the items around, which takes longer than the 30 ms SandFly gives onFocus, so it runs
-- from a timer after onFocus has returned.
local function describeFocus(item)
  -- Play buttons say the sound's name, and Stop while it plays.
  if is(item, 'playButton') then
    local name, around = soundNear(item)
    if name == nil then return nil end
    local playing = around ~= nil and around:find({ id = 'progressBar', visible = true }) ~= nil
    return say((playing and 'Stop ' or 'Play ') .. name)
  end

  -- Sounds in lists: name, length, tags and price.
  if is(item, 'audioItem') and item.contentDescription then
    local parts = { item.contentDescription }
    local duration = textOf(item:find({ id = 'duration' }))
    local tags = textOf(item:find({ id = 'tags' }))
    local price = priceIn(item)
    if duration then parts[#parts + 1] = duration end
    if tags then parts[#parts + 1] = tags end
    if price then parts[#parts + 1] = price end
    return say(table.concat(parts, ', '))
  end

  -- Wallpapers in a grid: numbered, with their badge and price.
  if is(item, 'wallpaperLandingItem') or is(item, 'dynamicWallpaperLandingItem') then
    local parent = item:parent()
    if parent == nil then return nil end
    local index = 0
    for _, child in ipairs(parent:children()) do
      if is(child, 'wallpaperLandingItem') or is(child, 'dynamicWallpaperLandingItem') then
        index = index + 1
        if child == item then break end
      end
    end
    local parts = { 'Wallpaper ' .. index }
    local badge = item:find({ id = 'iconBadge' })
    if badge and badge.contentDescription then parts[#parts + 1] = badge.contentDescription end
    local price = priceIn(item)
    if price then parts[#parts + 1] = price end
    return say(table.concat(parts, ', '))
  end

  -- A wallpaper on its own page: its name instead of "Image".
  if is(item, 'itemView') then
    local parent = item:parent()
    local d = parent and parent.contentDescription
    if d ~= nil and d ~= '' then
      local price = priceIn(item)
      return say(d .. ', wallpaper' .. (price and (', ' .. price) or ''))
    end
  end

  -- The Set button of a paid item says its price.
  if is(item, 'itemPageSetButton') and state.itemPrice then
    return say('Set, ' .. state.itemPrice)
  end

  -- Collections in a list: name, what they hold, and who made them.
  if is(item, 'collectionItem') and item:find({ id = 'collectionName' }) then
    local parts = { textOf(item:find({ id = 'collectionName' })) or item.contentDescription or 'Collection' }
    local stats = item:find({ id = 'contentStats' })
    if stats then
      for _, child in ipairs(stats:children()) do
        if child.contentDescription and child.contentDescription ~= '' then
          parts[#parts + 1] = child.contentDescription
        end
      end
    end
    local author = textOf(item:find({ id = 'author' }))
    if author then parts[#parts + 1] = author end
    return say(table.concat(parts, ', '))
  end

  -- Search categories with their number of results.
  if is(item, 'searchItemContentType') and item.contentDescription then
    local count = textOf(item:find({ id = 'trailingCount' }))
    if count then return say(item.contentDescription .. ', ' .. count .. ' results') end
    return nil
  end

  -- Tabs in search results, which only show a number.
  if is(item, 'contentTypeTab') then
    local parent = item:parent()
    if parent == nil then return nil end
    local index, tabs = nil, 0
    for _, child in ipairs(parent:children()) do
      if is(child, 'contentTypeTab') then
        tabs = tabs + 1
        if child == item then index = tabs end
      end
    end
    if index == nil or tabs ~= #TAB_NAMES then return nil end
    local text = TAB_NAMES[index] .. ', ' .. (item.contentDescription or '') .. ' results'
    if not item.clickable then text = text .. ', selected' end
    return say(text)
  end

  -- Tabs at the top and bottom: the one shown says it is selected.
  if (idEnds(item, 'TabButton') or idStarts(item, 'bottomNavigationBar')) and not item.clickable then
    local label = textOf(item:find({ className = 'TextView' }))
    if label then return say(label .. ', selected') end
  end

  -- Alarm days: the full day, and whether the alarm rings on it.
  if idStarts(item, 'dayChip_') then
    local key = item.id:match('dayChip_(%a+)$')
    local day = key and DAYS[key]
    if day == nil then return nil end
    local summary = sf.screen.find({ textContains = 'Every' })
    local text = textOf(summary)
    if text == nil then return say(day[1]) end
    local on = text:find('Every day', 1, true) ~= nil
    -- Compares whole words, as some short names, such as Št, are more than one byte.
    local words = {}
    for word in text:gmatch('[^,%s]+') do words[word] = true end
    for i = 2, #day do
      if words[day[i]] then on = true end
    end
    return say(day[1] .. (on and ', selected' or ', not selected'))
  end

  -- Alarm time wheels: hours or minutes, and which number is chosen.
  if item.className and item.className:sub(-8) == 'TextView' and textOf(item) and textOf(item):match('^%d+$') then
    local picker = item:parent()
    if is(picker, 'onboardingTimePicker') then
      local w = wheels(picker)
      if w then
        local inHours = false
        for _, n in ipairs(w.hours) do if n.item == item then inHours = true end end
        local column = inHours and w.hours or w.minutes
        local selected = column.selected and column.selected.item == item
        return say((inHours and 'Hours ' or 'Minutes ') .. textOf(item) .. (selected and ', selected' or '')
          .. '. Use the action Set alarm time')
      end
    end
  end

  -- Alarm sounds and missions: which one was chosen.
  if is(item, 'soundPickerItem') or idStarts(item, 'missionPicker') then
    local list = is(item, 'soundPickerItem') and 'sound' or 'mission'
    local parts = textsInside(item)
    if #parts == 0 then return nil end
    local name = parts[1]
    local chosen = state.chosen[list] == name
    return say(table.concat(parts, ', ') .. (chosen and ', selected' or ''))
  end

  -- Credit offers: the button together with the offer it belongs to.
  if is(item, 'offerwall_item_button') then
    local own = textOf(item:find({ className = 'TextView' })) or textOf(item)
    local offer = item:parent()
    if own == nil or offer == nil then return nil end
    local others = textsInside(offer, item)
    -- Leaves out the button's own text and the credit icons' names.
    local rest, amount = {}, nil
    for _, t in ipairs(others) do
      if t ~= own and t ~= 'Credits' and t ~= 'Free credits' then
        if amount == nil and t:match('^[%d%s]+$') then
          amount = t
        else
          rest[#rest + 1] = t
        end
      end
    end
    local extra = #rest > 0 and (', ' .. table.concat(rest, ', ')) or ''
    if own:match('€') or own:match('%$') then
      return say('Buy ' .. (amount or '') .. ' credits for ' .. own .. extra)
    end
    return say(own .. (amount and (', ' .. amount .. ' credits') or '') .. extra)
  end
  return nil
end

-- Items describeFocus changes, told apart by their id and fields alone, with no call to Zedge.
local function needsDescription(item)
  local id = item.id or ''
  if is(item, 'playButton') or is(item, 'wallpaperLandingItem') or is(item, 'dynamicWallpaperLandingItem')
      or is(item, 'itemView') or is(item, 'collectionItem') or is(item, 'contentTypeTab')
      or is(item, 'soundPickerItem') or is(item, 'offerwall_item_button')
      or idStarts(item, 'dayChip_') or idStarts(item, 'missionPicker') then
    return true
  end
  if (is(item, 'audioItem') or is(item, 'searchItemContentType')) and item.contentDescription then return true end
  if is(item, 'itemPageSetButton') and state.itemPrice then return true end
  if (idEnds(item, 'TabButton') or idStarts(item, 'bottomNavigationBar')) and not item.clickable then return true end
  -- A number that may be on the alarm time wheels.
  local text = item.text
  return item.className ~= nil and item.className:sub(-8) == 'TextView' and text ~= nil and text:match('^%d+$') ~= nil
end

-- onFocus only decides, from the item alone, whether to say something else. If so, it keeps
-- SandFly quiet and a timer works the text out and says it, unless focus has moved on by then.
local focusCount = 0
sf.onFocus(function(item, text)
  focusCount = focusCount + 1
  if not needsDescription(item) then return nil end
  local count = focusCount
  sf.setTimeout(function()
    local ok, described = pcall(describeFocus, item)
    if count ~= focusCount then return end
    local say = (ok and described) or text
    if say ~= nil and say ~= '' then sf.speak(say, { interrupt = true }) end
  end, 0)
  return false
end)

-- Remembers the alarm sound and mission chosen, which Zedge only shows on screen.
sf.onClick(function(event)
  local node = event.node
  if node == nil then return end
  if is(node, 'soundPickerItem') or idStarts(node, 'missionPicker') then
    local list = is(node, 'soundPickerItem') and 'sound' or 'mission'
    local parts = textsInside(node)
    if parts[1] then
      state.chosen[list] = parts[1]
      log('Chosen ' .. list .. ': ' .. parts[1])
    end
    return
  end
  if node:find({ textContains = 'Save to Media' }) ~= nil then
    log('Save to Media Folder tapped')
    sf.setTimeout(function() sf.speak('Saved to device') end, 800)
  end
end)

-- Download: Set, then Save to Media Folder, and says whether it worked. Never for paid items.
local function download()
  local set = sf.screen.find('itemPageSetButton')
  if set == nil then
    sf.speak('Open a ringtone or wallpaper first', { interrupt = true })
    return
  end
  if state.itemPrice then
    log('Download refused: ' .. state.itemPrice)
    sf.speak('This item ' .. state.itemPrice .. '. Use the Set button to buy it.', { interrupt = true })
    return
  end
  set:click()
  local label = sf.screen.waitFor({ textContains = 'Save to Media' }, 4000)
  if label == nil then
    log('Download: Save to Media Folder not found')
    sf.speak('Could not find Save to Media Folder', { interrupt = true })
    return
  end
  local row = label:parent()
  local ok = row ~= nil and row:click()
  if not ok then ok = label:tap() end
  sf.sleep(800)
  log(ok and 'Download: saved' or 'Download: failed')
  sf.speak(ok and 'Saved to device' or 'Saving failed', { interrupt = true })
end

-- Turns one wheel of the alarm time to a number, checking after each turn.
local function turnWheel(columnName, target, modulo)
  for _ = 1, 40 do
    local picker = sf.screen.find('onboardingTimePicker')
    local w = picker and wheels(picker)
    local column = w and w[columnName]
    if column == nil or column.selected == nil then return false end
    local current = column.selected.value
    if current == target then return true end
    local d = (target - current) % modulo
    if d > modulo / 2 then d = d - modulo end
    local steps = math.min(math.abs(d), 3)
    local dir = d > 0 and 1 or -1
    local y = w.centerY
    -- Moving a finger up turns the wheel to higher numbers.
    sf.touch.swipe(column.x, y, column.x, y - dir * steps * column.rowHeight, 500 * steps)
    sf.sleep(400)
  end
  return false
end

local function setAlarmTime()
  if sf.screen.find('onboardingTimePicker') == nil then
    sf.speak('Open the alarm time first', { interrupt = true })
    return
  end
  local answer = sf.ui.prompt('Alarm time', { hint = 'Hours and minutes, for example 07:30' })
  if answer == nil then return end
  local h, m = answer:match('^%s*(%d%d?)%s*[:.%s]%s*(%d%d?)%s*$')
  if h == nil then
    h = answer:match('^%s*(%d%d?)%s*$')
    m = h and '0'
  end
  h, m = tonumber(h), tonumber(m)
  if h == nil or m == nil or h > 23 or m > 59 then
    sf.speak('Write the time as hours and minutes, for example 07:30', { interrupt = true })
    return
  end
  local ok = turnWheel('hours', h, 24) and turnWheel('minutes', m, 60)
  local picker = sf.screen.find('onboardingTimePicker')
  local w = picker and wheels(picker)
  if ok and w then
    local text = string.format('%02d:%02d', w.hours.selected.value, w.minutes.selected.value)
    log('Alarm time set to ' .. text)
    sf.speak('Alarm time ' .. text, { interrupt = true })
  else
    log('Alarm time: could not set ' .. answer)
    sf.speak('Could not set the time', { interrupt = true })
  end
end

sf.onCommand('download', function() download() end)
sf.onCommand('alarmTime', function() setAlarmTime() end)

sf.onActions(function()
  local actions = {}
  if state.onItemPage and not state.itemPrice then
    actions[#actions + 1] = { title = 'Download to device', first = true, run = download }
  end
  if state.timePicker then
    actions[#actions + 1] = { title = 'Set alarm time', first = true, run = setAlarmTime }
  end
  if #actions > 0 then return actions end
  return nil
end)

-- The price of the item in the middle of an item page, or nil when it is free.
local function currentPrice()
  local width = sf.device.info().screen.width
  for _, pill in ipairs(sf.screen.findAll({ id = 'pricePill' }, 10)) do
    local card = pill:parent()
    for _ = 1, 4 do
      if card == nil then break end
      if is(card, 'audioItemView') or is(card, 'itemView') then break end
      card = card:parent()
    end
    local b = card and card.bounds
    if b and b.left < width / 2 and b.right > width / 2 then return priceText(pill) end
  end
  return nil
end

-- Closes Zedge pop-ups, and notes what the screen holds.
local function checkScreen()
  state.onItemPage = sf.screen.find('itemPageSetButton') ~= nil
  state.itemPrice = state.onItemPage and currentPrice() or nil
  state.timePicker = sf.screen.find('onboardingTimePicker') ~= nil
  if not sf.settings.get('autoClose') then return end

  -- Full-screen promotions.
  local dismiss = sf.screen.find('dismissButton')
  if dismiss ~= nil then
    if not dismiss:click() then dismiss:tap() end
    log('Closed a Zedge promotion')
    sf.speak('Closed Zedge pop-up')
    return
  end

  -- The rating prompt.
  if sf.screen.find({ textContains = 'Rate your Zedge' }) ~= nil then
    local close = sf.screen.find({ contentDescription = 'Close', clickable = true })
      or sf.screen.find({ contentDescription = 'Close' })
    if close ~= nil then
      if not close:click() then close:tap() end
      log('Closed the rating prompt')
      sf.speak('Closed rating prompt')
    end
    return
  end

  -- Tips with a Got it button.
  local gotIt = sf.screen.find({ text = 'Got it' })
  if gotIt ~= nil then
    local p = gotIt:parent()
    if not (p ~= nil and p.clickable and p:click()) then gotIt:tap() end
    log('Closed a Got it tip')
  end
end

-- Checks the screen a moment after it changes, not on every small change.
local pending = false
local function scheduleCheck()
  if pending then return end
  pending = true
  sf.setTimeout(function()
    pending = false
    checkScreen()
  end, 700)
end

sf.onWindowChange(scheduleCheck)
sf.onContentChange(scheduleCheck)
sf.onAppEnter(scheduleCheck)
