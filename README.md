# SandFly scripts by Silak

Lua scripts for the [SandFly](https://github.com/aaron-gh/SandFly) screen reader for Android. Each script speaks English, and Slovak when the phone is set to Slovak.

To use them, add this repository as a script source: in SandFly settings, go to **Apps** > **Scripts** > **Script sources** > **Add source**, and enter `github.com/silak-blindzone/sandfly-scripts`. Install a script from the source, and SandFly updates it from here when a newer version comes out.

| Script | App | Does |
|---|---|---|
| `chatgpt-access.zip` | ChatGPT | Reads a whole answer at once in a window you can read by line, word and character, skips the buttons under an answer when swiping and puts them in its Actions menu, says You before your messages, describes or reads the text of pictures in the conversation, pages through the conversation, announces a finished answer and names the message field. |
| `clear-notifications.zip` | Notification shade | A command that presses Clear all. On the lock screen, which has no such button, it dismisses the notifications one by one. |
| `clear-recents.zip` | Recent apps (POCO Launcher, OnePlus) | A command that clears all recent apps. |
| `page-flip.zip` | All apps | Moves through a long list a screen at a time, as Jieshuo does, and reads the first new item. |
| `power-menu.zip` | HyperOS and OnePlus power menus | One swipe of one finger, in the directions each menu gives. HyperOS: swipe up to power off, or down to restart. OnePlus: swipe up to restart, or down to power off. Both are also in the Actions menu of the slider. |
| `telegram-voice.zip` | Telegram | The first gesture starts and locks a voice message, and the second sends it, with SandFly muted while the recording starts. |
| `translate-focused.zip` | All apps | Translates the focused text into the phone's language with Google Translate, as Instant Translate does in NVDA. |
| `watch.zip` | All apps | Tells the time by vibration, or by haptic taps on phones that have them. One command can tell the time when the phone is locked and run another SandFly command, such as Lock or unlock touch, when it is unlocked. Ported from a Jieshuo plugin. |
| `whatsapp-voice.zip` | WhatsApp | The first gesture starts and locks a voice message, and the second sends it, with SandFly muted while the recording starts. |
| `wifi-tester.zip` | All apps | A tone whose pitch follows the Wi-Fi signal, to find the best spot. Ported from a Jieshuo plugin. |
| `zedge-access.lua` | Zedge | Names on Play buttons, prices, one-step download of free items, named tabs, numbered wallpapers, collections, alarm settings and closing pop-ups. |

Commands without a fixed gesture are assigned in SandFly's gesture settings, under **Gestures**, or for one app under **Gestures** > **Gestures in apps**.

## Changing a script

The scripts are in `src/`, one folder each, named after the script's `id`. After changing one, raise its `version` in the manifest and build it:

```
python tools/build.py whatsapp-voice
```

The build writes the file SandFly installs at the top of the repository: `<id>.zip` for a script with translations, or `<id>.lua` for a script that is only `main.lua`. `tools/check.py src/<id>` checks a script's Lua syntax, the rules for on-demand scripts, and that every text has a Slovak translation; it needs `pip install luaparser`.

How to write scripts is in [Writing SandFly scripts](https://github.com/aaron-gh/SandFly/blob/master/docs/scripting.md).
