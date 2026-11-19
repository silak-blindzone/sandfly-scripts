local manifest = {
  id = 'page-flip',
  name = 'Page by page',
  version = '1.2',
  author = 'Silak',
  description = 'Moves through a long list a screen at a time, as Jieshuo does: scrolls the list that focus is in a page forward or back, and focuses the first new item, which is then read. Assign the two commands to gestures in SandFly\'s gesture settings.',
  minApiVersion = 6,
  testedApiVersion = 6,
  onDemand = true,
  permissions = { 'input', 'screen', 'actions', 'speech' },
  commands = {
    { id = 'next', title = 'Next page' },
    { id = 'previous', title = 'Previous page' },
  },
}

local tr = sf._

local SCROLL_FORWARD = 4096
local SCROLL_BACKWARD = 8192

local function hasAction(item, id)
  for _, a in ipairs(item.actions or {}) do
    if a.id == id then return true end
  end
  return false
end

local function endsWith(s, suffix)
  return s ~= nil and s:sub(-#suffix) == suffix
end

-- Lists a page scroll doesn't suit, as in Jieshuo: pagers, the launcher's home screens and number
-- pickers, which scroll sideways or by one value.
local function unsuitable(list)
  local class = list.className or ''
  return endsWith(class, 'ViewPager') or class:find('viewpager', 1, true) ~= nil
    or endsWith(class, 'NumberPicker') or endsWith(list.id or '', 'workspace')
end

-- The scrollable list that holds the focused item, or the largest one on screen.
local function listOf(focused, action)
  local node = focused
  for _ = 1, 25 do
    if node == nil then break end
    if node.scrollable and not unsuitable(node) then return node end
    node = node:parent()
  end
  local best, area = nil, 0
  for _, l in ipairs(sf.screen.findAll({ scrollable = true, visible = true }, 20)) do
    local b = l.bounds
    local a = b and (b.right - b.left) * (b.bottom - b.top) or 0
    if not unsuitable(l) and hasAction(l, action) and a > area then best, area = l, a end
  end
  return best
end

-- The rows of the list on screen, top to bottom: its visible children with a size.
local function rows(list)
  local found = {}
  local lb = list.bounds
  for _, child in ipairs(list:children()) do
    local b = child.bounds
    if child.visible ~= false and b ~= nil and b.bottom > b.top
        and b.bottom > lb.top and b.top < lb.bottom then
      found[#found + 1] = child
    end
  end
  table.sort(found, function(a, b)
    if a.bounds.top ~= b.bounds.top then return a.bounds.top < b.bounds.top end
    return a.bounds.left < b.bounds.left
  end)
  return found
end

-- A key that tells rows apart across a scroll: their texts, as rows move but keep their content.
local function key(row)
  local parts = { row.text or '', row.contentDescription or '' }
  for _, t in ipairs(row:findAll({ visible = true }, 8)) do
    parts[#parts + 1] = (t.text or '') .. '|' .. (t.contentDescription or '')
  end
  return table.concat(parts, '/')
end

-- What the first row of the list is and where: it changes while the list moves.
local function firstRow(list)
  local first = rows(list)[1]
  if first == nil then return '' end
  return key(first) .. '@' .. tostring(first.bounds.top)
end

-- How often the list is checked while it moves, how many checks in a row it must stay still to
-- count as stopped, and how long a slower phone may take to start moving it.
local CHECK = 50 -- milliseconds
local STILL = 2 -- checks
local START = 600 -- milliseconds
local LONGEST = 2000 -- milliseconds

-- Waits until the list stops moving: its first row stays the same for STILL checks in a row.
-- Calls onMove once, as soon as the list has moved. A list that hasn't moved after START counts
-- as settled.
local function waitUntilSettled(list, start, onMove)
  local previous, moved, waited, still = start, false, 0, 0
  while waited < LONGEST do
    sf.sleep(CHECK)
    waited = waited + CHECK
    local now = list:refresh()
    if now == nil then return nil end
    local current = firstRow(now)
    if not moved and current ~= start then
      moved = true
      onMove()
    end
    if current == previous then still = still + 1 else still = 0 end
    if moved and still >= STILL then return now end
    if not moved and waited >= START then return now end
    previous = current
    list = now
  end
  return list:refresh()
end

-- Focuses a row, or the first item in it that can take focus.
local function focusRow(row)
  if row:focus() then return true end
  for _, item in ipairs(row:findAll({ visible = true }, 20)) do
    if (item.focusable or item.clickable) and item:focus() then return true end
  end
  return false
end

-- Where focus is, to tell whether a command moved it.
local function focusKey(item)
  if item == nil then return '' end
  local b = item.bounds or {}
  return table.concat({ item.id or '', item.text or '', item.contentDescription or '',
    tostring(b.left), tostring(b.top) }, '|')
end

local function inside(row, item)
  local r, b = row.bounds, item and item.bounds
  return r ~= nil and b ~= nil and b.left >= r.left and b.top >= r.top
    and b.right <= r.right and b.bottom <= r.bottom
end

-- At the start or end of the list, as in Jieshuo: focus goes to the first or last item on
-- screen, and only when it is already there does it say that this is the start or end.
local function toEdge(list, forward)
  local all = rows(list)
  local edge = forward and all[#all] or all[1]
  if edge ~= nil and not inside(edge, sf.screen.focused()) and focusRow(edge) then return end
  sf.speak(forward and tr('End of list') or tr('Start of list'), { interrupt = true })
end

local function flip(forward)
  local action = forward and SCROLL_FORWARD or SCROLL_BACKWARD
  local list = listOf(sf.screen.focused(), action)
  if list == nil then
    -- Nothing to scroll, such as a lock screen with a few notifications: as in Jieshuo, focus
    -- goes to the first or last item on screen, and when it is already there, this says the
    -- start or end, as in a list. The command runs muted, so that an item focus stays on isn't
    -- read again; when focus moved, the command runs again with speech, which reads the item
    -- focus is now on.
    local command = forward and 'LAST_IN_SCREEN' or 'FIRST_IN_SCREEN'
    local before = focusKey(sf.screen.focused())
    local mute = sf.feedback.mute({ speech = true, sounds = true }, 2000)
    -- The command has moved focus by the time it returns, so there is nothing to wait for.
    local ran = sf.commands.run(command)
    local now = sf.screen.focused()
    if not ran or now == nil or focusKey(now) == before then
      pcall(function() mute:release() end)
      if not ran then
        sf.speak(tr('There is no list here to move through by page'), { interrupt = true })
      else
        sf.speak(forward and tr('End of list') or tr('Start of list'), { interrupt = true })
      end
      return
    end
    pcall(function() mute:release() end)
    sf.commands.run(command)
    return
  end
  if not hasAction(list, action) then
    toEdge(list, forward)
    return
  end
  local before = {}
  for _, row in ipairs(rows(list)) do before[key(row)] = true end
  local start = firstRow(list)

  local moved = forward and list:scrollForward() or list:scrollBackward()
  if not moved then
    toEdge(list, forward)
    return
  end
  -- The scroll sound, as Jieshuo plays when it turns a page, as soon as the list really moves.
  list = waitUntilSettled(list, start, function() sf.playSound('scroll') end)
  if list == nil then return end

  -- The rows that weren't on screen before, top to bottom. When none is new, the list didn't
  -- move.
  local function newRows(l)
    local found = {}
    for _, row in ipairs(rows(l)) do
      if not before[key(row)] then found[#found + 1] = row end
    end
    return found
  end
  local fresh = newRows(list)
  if #fresh == 0 then
    toEdge(list, forward)
    return
  end
  -- Focus goes to the first new row that takes it, such as when the first is still partly off
  -- screen; if none does, the list is read again once, in case the app replaced its rows.
  for attempt = 1, 2 do
    for _, row in ipairs(fresh) do
      if focusRow(row) then return end
    end
    if attempt == 1 then
      local again = list:refresh()
      if again == nil then break end
      fresh = newRows(again)
    end
  end
  sf.speak(tr('Could not move focus to the new page'), { interrupt = true })
end

sf.onCommand('next', function() flip(true) end)
sf.onCommand('previous', function() flip(false) end)
