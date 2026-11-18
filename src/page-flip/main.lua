local manifest = {
  id = 'page-flip',
  name = 'Page by page',
  version = '1.1',
  author = 'Silak',
  description = 'Moves through a long list a screen at a time, as Jieshuo does: scrolls the list that focus is in a page forward or back, and focuses the first new item, which is then read. Assign the two commands to gestures in SandFly\'s gesture settings.',
  minApiVersion = 4,
  testedApiVersion = 6,
  onDemand = true,
  permissions = { 'screen', 'actions', 'speech' },
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
  table.sort(found, function(a, b) return a.bounds.top < b.bounds.top end)
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

-- Waits until the list stops moving: the top of its first row is the same in two checks.
local function waitUntilSettled(list)
  local previous = nil
  for _ = 1, 15 do
    sf.sleep(100)
    local now = list:refresh()
    if now == nil then return nil end
    local first = rows(now)[1]
    local top = first and first.bounds.top
    if top ~= nil and top == previous then return now end
    previous = top
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

local function flip(forward)
  local action = forward and SCROLL_FORWARD or SCROLL_BACKWARD
  local list = listOf(sf.screen.focused(), action)
  if list == nil then
    sf.speak(tr('There is no list here to move through by page'), { interrupt = true })
    return
  end
  if not hasAction(list, action) then
    sf.speak(forward and tr('End of list') or tr('Start of list'), { interrupt = true })
    return
  end
  local before = {}
  for _, row in ipairs(rows(list)) do before[key(row)] = true end

  local moved = forward and list:scrollForward() or list:scrollBackward()
  if not moved then
    sf.speak(forward and tr('End of list') or tr('Start of list'), { interrupt = true })
    return
  end
  -- The scroll sound, as Jieshuo plays when it turns a page.
  sf.playSound('scroll')
  list = waitUntilSettled(list)
  if list == nil then return end

  -- The first row that wasn't on screen before, or the first row if every row is new.
  local now = rows(list)
  local target = nil
  for _, row in ipairs(now) do
    if not before[key(row)] then target = row break end
  end
  target = target or now[1]
  if target == nil or not focusRow(target) then
    sf.speak(tr('Could not move focus to the new page'), { interrupt = true })
  end
end

sf.onCommand('next', function() flip(true) end)
sf.onCommand('previous', function() flip(false) end)
