local manifest = {
  id = 'clear-recents',
  name = 'Clear recent apps',
  version = '2.2',
  author = 'Silak',
  description = 'On the recent apps screen, presses the button that clears all recent apps. Works with the HyperOS and OnePlus recent apps screens.',
  minApiVersion = 2,
  testedApiVersion = 5,
  apps = {
    { package = 'com.mi.android.globallauncher', activity = 'RecentsActivity' },
    { package = 'com.android.launcher', activity = 'RecentsActivity' },
  },
  permissions = { 'input', 'screen', 'actions', 'speech' },
  commands = {
    { id = 'clear_all', title = 'Clear all recent apps' },
  },
}

local tr = sf._

-- The button by its id, which doesn't depend on the language: clearAnimView on HyperOS and btn_clear
-- on OnePlus. Its name in the phone's language is only a fallback, in case a launcher update changes
-- the id.
local function queries()
  return {
    'clearAnimView',
    'btn_clear',
    { contentDescription = tr('Clear all recent apps') },
    { textContains = tr('Clear all') },
  }
end

sf.onCommand('clear_all', function()
  for _, query in ipairs(queries()) do
    local button = sf.screen.find(query)
    if button ~= nil then
      if not button:click() then button:tap() end
      return
    end
  end
  sf.speak(tr('Could not find the button that clears recent apps'), { interrupt = true })
end)
