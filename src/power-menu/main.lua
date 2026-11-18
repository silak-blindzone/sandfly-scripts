local manifest = {
  id = 'power-menu',
  name = 'Power menu',
  version = '2.0',
  author = 'Silak',
  description = 'Makes the HyperOS power menu usable: swipe up twice to power off, or down twice to restart. Both are also in the Actions menu of the slider.',
  minApiVersion = 5,
  testedApiVersion = 5,
  apps = { 'miui.systemui.plugin' },
  permissions = { 'screen', 'actions', 'input', 'speech' },
  commands = {
    { id = 'up', title = 'Power off (swipe up twice)', gesture = 'swipeUp' },
    { id = 'down', title = 'Restart (swipe down twice)', gesture = 'swipeDown' },
  },
}

local tr = sf._
local CONFIRM_SECONDS = 4
local ACTION_SET_PROGRESS = 16908349
local ACTION_SCROLL_FORWARD = 4096
local ACTION_SCROLL_BACKWARD = 8192

-- The power slider, told by its layout: a tall SeekBar in the middle of the screen with no action
-- to set a value. The volume slider is at the edge and can be set.
local function isPowerSlider(item, screenWidth)
  local b = item.bounds
  if b == nil or item.className == nil or item.className:sub(-7) ~= 'SeekBar' then return false end
  local w, h = b.right - b.left, b.bottom - b.top
  if w <= 0 or h < w * 3 then return false end
  local center = (b.left + b.right) / 2
  if math.abs(center - screenWidth / 2) > screenWidth * 0.1 then return false end
  for _, a in ipairs(item.actions or {}) do
    if a.id == ACTION_SET_PROGRESS or a.id == ACTION_SCROLL_FORWARD or a.id == ACTION_SCROLL_BACKWARD then
      return false
    end
  end
  return true
end

-- The screen's width, from the device, which needs no call to the menu.
local function screenWidth()
  local info = sf.device.info()
  return (info and info.screen and info.screen.width) or 1200
end

local function findSlider()
  for _, window in ipairs(sf.screen.windows()) do
    local root = window.root
    if root ~= nil and root.packageName == 'miui.systemui.plugin' then
      for _, item in ipairs(root:findAll({ className = 'SeekBar' }, 20)) do
        if isPowerSlider(item, screenWidth()) then return item end
      end
    end
  end
  return nil
end

local function drag(slider, up)
  local b = slider.bounds
  local x = math.floor((b.left + b.right) / 2)
  local y = math.floor((b.top + b.bottom) / 2)
  local target = up and (b.top + 20) or (b.bottom - 20)
  -- At once and fast: a finger touching the screen during the drag would cancel it and close
  -- the menu.
  local ok = sf.touch.swipe(x, y, x, target, 250)
  sf.speak(up and tr('Powering off') or tr('Restarting'), { interrupt = true })
  return ok
end

local pending = nil -- { up = true or false, at = seconds }

local function onSwipe(up)
  local slider = findSlider()
  if slider == nil then return false end
  local now = os.time()
  if pending ~= nil and pending.up == up and now - pending.at <= CONFIRM_SECONDS then
    pending = nil
    drag(slider, up)
    return true
  end
  pending = { up = up, at = now }
  sf.speak(up and tr('Power off? Swipe up again.') or tr('Restart? Swipe down again.'), { interrupt = true })
  return true
end

sf.onCommand('up', function() return onSwipe(true) end)
sf.onCommand('down', function() return onSwipe(false) end)

sf.onFocus(function(item)
  if item.packageName == 'miui.systemui.plugin' and isPowerSlider(item, screenWidth()) then
    return { speak = tr('Power menu. Swipe up twice to power off, or down twice to restart.') }
  end
end)

-- The Actions menu is offered on the slider only, told from the item alone, so that it opens
-- at once. The slider is looked up again when an action runs.
sf.onActions(function(item)
  if item == nil or not isPowerSlider(item, screenWidth()) then return nil end
  local function act(up)
    return function()
      local slider = findSlider()
      if slider then drag(slider, up) end
    end
  end
  return {
    { title = tr('Power off'), first = true, run = act(true) },
    { title = tr('Restart'), first = true, run = act(false) },
  }
end)
