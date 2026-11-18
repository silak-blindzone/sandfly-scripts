local manifest = {
  id = 'clear-notifications',
  name = 'Clear notifications',
  version = '2.1',
  author = 'Silak',
  description = 'In the notification shade, presses Clear all. On the lock screen, which has no such button, dismisses the notifications one by one.',
  minApiVersion = 2,
  testedApiVersion = 5,
  apps = { 'com.android.systemui' },
  permissions = { 'input', 'screen', 'actions', 'speech' },
  commands = {
    { id = 'clear_all', title = 'Clear all notifications' },
  },
}

local tr = sf._
local ACTION_DISMISS = 1048576

-- The button by its id, which doesn't depend on the language, and by its name in the phone's
-- language in case a system update changes the id.
local function queries()
  return {
    'notification_dismiss_view',
    { textContains = tr('Clear all notifications') },
  }
end

local function windowRoots()
  local roots = {}
  for _, window in ipairs(sf.screen.windows()) do
    if window.root ~= nil then roots[#roots + 1] = window.root end
  end
  return roots
end

local function findButton()
  for _, query in ipairs(queries()) do
    local button = sf.screen.find(query)
    if button ~= nil then return button end
  end
  for _, root in ipairs(windowRoots()) do
    for _, query in ipairs(queries()) do
      local button = root:find(query)
      if button ~= nil then return button end
    end
  end
  return nil
end

local function canDismiss(item)
  if item.dismissable then return true end
  for _, action in ipairs(item.actions or {}) do
    if action.id == ACTION_DISMISS then return true end
  end
  return false
end

-- Notifications that can be swiped away, found by their Dismiss action rather than by text.
local function dismissableItems()
  local found = {}
  for _, root in ipairs(windowRoots()) do
    if root.packageName == 'com.android.systemui' then
      for _, item in ipairs(root:findAll({ visible = true }, 200)) do
        if canDismiss(item) then found[#found + 1] = item end
      end
    end
  end
  return found
end

local function dismissOneByOne()
  local count = 0
  -- Each round the list moves up and shows more, so it takes a few rounds.
  for _ = 1, 10 do
    local items = dismissableItems()
    if #items == 0 then break end
    local done = 0
    for _, item in ipairs(items) do
      if item:dismiss() then done = done + 1 end
      sf.sleep(150)
    end
    if done == 0 then break end
    count = count + done
    sf.sleep(400)
  end
  return count
end

sf.onCommand('clear_all', function()
  local button = findButton()
  if button ~= nil then
    if not button:click() then button:tap() end
    return
  end
  local count = dismissOneByOne()
  if count == 0 then
    sf.speak(tr('There are no notifications that can be cleared'), { interrupt = true })
  else
    sf.speak(sf.ngettext('{count} notification cleared', '{count} notifications cleared', count, { count = count }),
      { interrupt = true })
  end
end)
