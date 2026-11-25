local manifest = {
  id = 'power-menu',
  name = 'Power menu',
  version = '2.2',
  author = 'Silak',
  description = 'Makes the HyperOS and OnePlus power menus usable. HyperOS: swipe up twice to power off, or down twice to restart. OnePlus, in the directions its menu gives but with one finger: swipe up to restart, or down to power off. Both are also in the Actions menu of the slider.',
  minApiVersion = 5,
  testedApiVersion = 5,
  apps = { 'miui.systemui.plugin', 'com.android.systemui' },
  permissions = { 'screen', 'actions', 'input', 'speech' },
  commands = {
    { id = 'up', title = 'Swipe up: power off twice on HyperOS, restart on OnePlus', gesture = 'swipeUp' },
    { id = 'down', title = 'Swipe down: restart twice on HyperOS, power off on OnePlus', gesture = 'swipeDown' },
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

-- The OnePlus (ColorOS) power menu: a round button in the middle of the screen, dragged up to the
-- restart icon or down to the power off icon, each about one button height away. The icons have no
-- description, so screen readers don't get them, and the button is told by its place: of the
-- menu's buttons, the full-screen Cancel button and Emergency SOS near the bottom are the others.
local function findOnePlusSlider(root)
  local menu = root:find({ id = 'com.android.systemui:id/oplus_shutdown_view_item' })
  if menu == nil then return nil end
  local area = menu.bounds
  if area == nil then return nil end
  local areaHeight = area.bottom - area.top
  for _, item in ipairs(menu:findAll({ className = 'Button' }, 10)) do
    local b = item.bounds
    if b ~= nil then
      local height = b.bottom - b.top
      local center = (b.top + b.bottom) / 2
      if height > 0 and height < areaHeight * 0.25
          and center > area.top + areaHeight * 0.3 and center < area.top + areaHeight * 0.7 then
        return {
          item = item,
          restartY = math.max(area.top + 1, b.top - height),
          powerOffY = math.min(area.bottom - 1, b.bottom + height),
        }
      end
    end
  end
  sf.log.warn('OnePlus power menu found, but not its button')
  return nil
end

-- The power slider on screen as { item, oneplus } and, on OnePlus, the drag targets; or nil.
local function findSlider()
  for _, window in ipairs(sf.screen.windows()) do
    local root = window.root
    if root ~= nil and root.packageName == 'miui.systemui.plugin' then
      for _, item in ipairs(root:findAll({ className = 'SeekBar' }, 20)) do
        if isPowerSlider(item, screenWidth()) then return { item = item } end
      end
    elseif root ~= nil and root.packageName == 'com.android.systemui' then
      local slider = findOnePlusSlider(root)
      if slider then
        slider.oneplus = true
        return slider
      end
    end
  end
  return nil
end

-- Whether the item is the power slider: the HyperOS one, told from the item alone, or the OnePlus
-- one, which only the screen around it tells apart.
local function isSliderItem(item)
  if item == nil then return false end
  if item.packageName == 'miui.systemui.plugin' then
    return isPowerSlider(item, screenWidth())
  end
  if item.packageName ~= 'com.android.systemui' or item.className == nil
      or item.className:sub(-6) ~= 'Button' then
    return false
  end
  local slider = findSlider()
  local a, b = slider and slider.item.bounds, item.bounds
  return a ~= nil and b ~= nil and a.left == b.left and a.top == b.top
    and a.right == b.right and a.bottom == b.bottom
end

-- Drags the slider to power off or to restart. HyperOS powers off at the top and restarts at the
-- bottom; OnePlus restarts at its restart icon above and powers off at the icon below.
local function drag(slider, powerOff)
  local b = slider.item.bounds
  local x = math.floor((b.left + b.right) / 2)
  local y = math.floor((b.top + b.bottom) / 2)
  local target
  if slider.oneplus then
    target = powerOff and slider.powerOffY or slider.restartY
  else
    target = powerOff and (b.top + 20) or (b.bottom - 20)
  end
  -- At once and fast: a finger touching the screen during the drag would cancel it and close
  -- the menu.
  local ok = sf.touch.swipe(x, y, x, target, slider.oneplus and 400 or 250)
  sf.speak(powerOff and tr('Powering off') or tr('Restarting'), { interrupt = true })
  return ok
end

local pending = nil -- { up = true or false, at = seconds }

-- HyperOS: a swipe up twice powers off, down twice restarts. OnePlus, in the directions its menu
-- gives: a swipe up restarts and down powers off, at once. The menu asks for two fingers, but
-- SandFly passes two-finger swipes to the app, and the menu takes them only from TalkBack.
local function onSwipe(up)
  local slider = findSlider()
  if slider == nil then return false end
  if slider.oneplus then
    drag(slider, not up)
    return true
  end
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

-- HyperOS's slider says nothing useful, and the OnePlus button asks for two fingers.
sf.onFocus(function(item)
  if not isSliderItem(item) then return nil end
  if item.packageName == 'miui.systemui.plugin' then
    return { speak = tr('Power menu. Swipe up twice to power off, or down twice to restart.') }
  end
  return { speak = tr('Power menu. Swipe up to restart, or down to power off.') }
end)

-- The Actions menu is offered on the slider only. The slider is looked up again when an action
-- runs.
sf.onActions(function(item)
  if not isSliderItem(item) then return nil end
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
