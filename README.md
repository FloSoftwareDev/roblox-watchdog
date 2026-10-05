download

[Download RobloxWatchdog.exe](https://github.com/FloSoftwareDev/roblox-watchdog/releases/latest/download/RobloxWatchdog.exe)

what it does

launches your alts into the private server through Roblox Account Manager (RAM, required, see below)
relaunches any account that crashes or gets kicked, main included
leaves a client alone when the game teleports it and it comes straight back by itself
notices a client that launched but never got into the game and relaunches it
relogs alts every X minutes so they don't go stale (main is never relogged)
keeps the clients awake so Roblox doesn't kick them for being idle
caps Roblox's frame rate so the clients don't eat your CPU rendering frames nobody looks at
tiles all the windows so they don't stack, spread over all your monitors, and puts them back where you dragged them
if your PC runs low on RAM, it closes the heaviest alt instead of letting everything freeze (or set it to 0 and it won't)
clears out the leftover Roblox processes that pile up in Task Manager
tells you on Discord when something actually needs you
starts itself again if it crashes
tells you when there is a newer version, on the strip at the top of the window
keeps retrying with a growing delay when a launch fails, instead of dying

you need Roblox Account Manager

[Roblox Account Manager](https://github.com/ic3w0lf22/Roblox-Account-Manager) (RAM) is required. This watchdog does not log into anything by itself and never touches your passwords or cookies. It only tells RAM "launch this account into this place", and RAM does the actual logging in. Without RAM running, nothing will start.

So the order is: install RAM, add your accounts to it, then run this.

RAM was archived in October 2024, so it isn't maintained any more, but 3.7.2 still works. Grab it from the Releases page of that repo.

setup

In RAM go to Settings > Developer: turn on Enable Web Server, Allow LaunchAccount Method, and set a Webserver Password (6+ characters)
Don't run RAM as admin, or autoclickers won't work on the Roblox windows. If you do run it as admin then the clients are admin too, and Windows won't let a normal program touch them: tiling, anti-idle and closing strays all get denied. In that case run the watchdog as admin as well. The window says which it is along the top.
Start your main account first
Fill in: alt usernames (one per line), place ID, private server link (paste the full share link), RAM port + password, and the limits
Hit start and go touch grass

The usernames have to match the accounts in RAM exactly, capitals included. RAM answers an unknown name with "Invalid Account" and nothing launches, so if an account never starts, check for a digit 1 where there should be a letter l, or an O where there should be a 0. The window and the log now say so instead of leaving you guessing.

heads up: by default it closes any other Roblox windows besides your main when it starts. Untick "Close other Roblox windows on start" if you don't want that.

also: it works out which client is your main by taking the oldest one that's already running. If you start it with an alt open and your main closed, that alt gets treated as main, which means it never gets relogged and never gets closed to free memory. There is no way to ask a running client which account it is, so if that matters, close everything before starting.

the window

A strip along the top says whether it's running as administrator, because that one thing silently breaks tiling, anti-idle and stray cleanup.

The same strip tells you when a newer version is out, and clicking it opens the download. It asks GitHub once at startup and every six hours after, in the background, and if there is no connection it just says nothing.

Under that: how many accounts are playing, free memory, strays closed, how long the watchdog has been up, and how long since the last disconnect. Then a row per account with a coloured dot, what it's doing, its memory, how long it's been up, and how many times it has dropped. The drop count goes amber at five, which is how you spot one account that's having a worse time than the others. Select a row and the line underneath shows its total uptime and when it last dropped, and why.

Select one or several accounts and you can relaunch or pause just those. Pause on its own stops relaunching, anti-idle and stray cleanup without closing anything, for when you want to work or record.

Closing the window keeps the watchdog running in the tray. Use Exit, or the tray menu, to actually stop it.

discord alerts

Paste a webhook url into the settings and hit Test, which sends a message straight away so you know it works before you rely on it.

It only sends things worth looking at: it started, it crashed and whether it's coming back, an account has failed five launches in a row, memory ran out with nothing left to close, it's missing permissions, and several accounts dropping at once. Ordinary single disconnects are not sent, because there were 152 of them in four days and that would be noise rather than a notification.

Relogs are sent for main, and for any group of three or more at once, because the character and inventory come back reset and that is work you have to redo. A single alt relogging only goes in the log. If you have a step list the message says whether it ran itself or is waiting for you to press Run.

"Discord alerts every min" is a periodic status message and is off by default. The alerts above work whether or not you turn it on.

if it crashes

It starts itself again, and that copy goes straight in without showing the settings window, because nobody is there to press Start. Pressing Exit is not a crash, so a deliberate stop stays stopped. If it crashes three times in ten minutes it gives up and stays down rather than respawning for ever, and it tells you on Discord either way.

This catches the watchdog erroring, which is what happened on 24-09 when it died and the accounts sat dead for 74 minutes. It won't catch the process being killed outright, from Task Manager or by Windows, because nothing gets to run in that case.

about the frame rate cap

Running a bunch of clients is usually CPU bound, not RAM bound. Uncapped, each client renders as fast as it can and burns a whole lot of cores for an AFK farm that doesn't need it. 6 clients on a 12 core CPU went from 10 cores down to under 7 just by capping to 30.

The cap goes into Roblox's own settings, and Roblox resets it to unlimited whenever a client closes, so the watchdog writes it again at startup and before every launch. Set it to 0 if you'd rather leave Roblox alone.

A client only picks up the cap when it launches, so an already running client (like a main you adopted) keeps whatever it started with until it relaunches.

about anti-idle

Roblox kicks a client after 20 minutes without input, and it only counts input while the window has focus. So there is no way around it: the window has to come to the front for a moment to get the keystroke. The watchdog puts your previous window back straight after, so it isn't supposed to interrupt what you were doing.

Default is every 15 minutes per account, and each account is on its own timer starting from when it joined, so they don't all do it at once. Max is 18, because 20 is when Roblox pulls the plug. Set it to 0 to turn it off.

"Aggressive anti-idle" does it twice as often (15 becomes 7), holds a movement key so the character actually walks, nudges the mouse inside the window, and presses the key twice instead of once. Use it if a game has its own idle check that watches more than keyboard input. It costs a bit more focus flicker, which is why it is off by default.

Getting focus is the weak point, not the keystroke. Windows refused it on 1301 of 5867 attempts in four days of log, 22%, mostly while someone was actually using the PC, and every refusal used to mean waiting another minute. It now asks again straight away, twice normally and four times in aggressive mode, before giving up and trying in a minute.

Default key is Space, which is the most reliable thing to register as input but does make your character jump. Any single letter works too, so pick something your game ignores if jumping is a problem.

Two things to know. With several accounts you'll see a brief focus flicker every few minutes, and if you happen to be typing at that exact moment the keystroke goes to Roblox instead of to you. And if Windows refuses to hand over focus, the keystroke is skipped and it tries again a minute later rather than fighting for it.

about the window layout

Accounts are shared out over your monitors in proportion to how much screen area each one has, and then tiled inside each screen. Nothing is tiled across the gap between two monitors, so no window ever ends up half on one screen and half on the other. Main keeps the top left slot on your main screen.

On a 2560x1440 plus a 1920x1080, six accounts go from 853x700 each to four at 1280x720 and two at 960x1080, which is roughly 60% more room per window.

Drag a window somewhere and that's where that account goes from then on, instead of back into the grid. Roblox nudging its own window by a few pixels doesn't count as you moving it. Untick "Put windows back where I dragged them" to go back to the grid and forget the saved spots.

Untick "Spread the windows over all monitors" to keep everything on the main screen, which is handy if you are recording or want the second screen for something else.

about closing alts for memory

"Kill an alt below free MB" closes the heaviest alt when free memory drops under it, so the machine doesn't grind to a halt. Main is never closed.

Set it to 0 if you don't want that at all. If your PC sits at full memory the whole time anyway, having an alt closed is worse than just letting it run, and 0 turns it off completely.

It also won't close more than one alt every two minutes. A closing client takes a while to hand its memory back, and the check runs every ten seconds, so without that gap a machine that stays low would close one alt after another until there were none left.

when nothing will launch at all

Roblox sometimes refuses to start another client by crashing inside its own single
instance guard. The new client looks for the running client's guard window, cannot reach
it, and gives up before any window appears. RAM reports success, because RAM did its part
and asked for the launch, so from the outside it just looks like nothing happened.

Waiting it out does not help and neither does retrying: the only thing that clears it is
every Roblox process being gone, main included. The watchdog now spots the crash in the
failed launch's own log, says so, closes everything and starts all the accounts again. It
tells you on Discord, because closing main is not something it should do quietly, and it
will not do it more than once every ten minutes.

If you ever see it by hand, that is the fix: close every Roblox window, then start again.

about relogs, which are not disconnects

The game puts players back into the game by teleporting them. The client leaves the server,
writes a disconnect line in its log, and rejoins about five seconds later without the window
ever closing. Roblox calls it a teleport, but what the account gets is a relog: the character
respawns and the inventory goes back into the hotbar, so anything you placed by hand has to
be placed again. The client itself is fine and does not need relaunching.

The watchdog used to read that disconnect line and close the client. 728 of the 785
disconnects in four days of log were teleports, so most of what it did was close a healthy
account and start it again, which puts your character back at spawn with its rockets
unplaced. If you ever found an account back at the start for no reason, that was this.

It now waits to see whether the client puts itself back on the same server. If it does,
the account is left alone and the window says how many times it has teleported. If nothing
comes back within 30 seconds it is treated as a real drop and relaunched. Every rejoin
measured took between 4.7 and 6.6 seconds, so 30 is a wide margin.

Coming back on a *different* server is decided at the end of the round rather than on the
spot, because one account cannot tell the difference on its own. If several accounts land
on the same new server, the private server itself moved and took them with it, and they
are all left alone. If an account is on an address no other account is on, it really has
been moved out of the farm and is relaunched. With a single account there is nobody to
corroborate it, so it gets relaunched to be safe.

The same goes for the process disappearing. Roblox can hand a session over to a new
process and let the old one exit, so a process going away is not proof the account is
gone. If exactly one client is unclaimed and sitting on in-game memory, the session is
picked up where it is instead of being relaunched. Otherwise it counts as a drop, which
it did not before, so a main that dies this way now reaches Discord instead of quietly
coming back.

about stuck clients and strays

There are two ways an account can die that a disconnect code never tells you about, and both used to leave you to find it by hand.

The first: the client launches fine, gets a window, and then fails to reach the game server. It sits on an error screen forever. Roblox never writes a disconnect code for this, because it never connected in the first place, so watching for disconnects will never catch it. This actually happened on 25-09: a private server shut down, four accounts relaunched, all four failed to connect with "Failed to connect to server, no response" and sat there for 42 minutes. The watchdog now waits for the client to report that it is really in the game, and relaunches it if that hasn't happened within 150 seconds.

The second: Roblox spawns a helper process when a client shuts down, and those never exit. No window, about 175 MB each, and they build up until you go and force close them in Task Manager. The watchdog now closes any Roblox process it didn't launch that has no window and has been sitting there past the grace period. Default is 3 minutes, 0 turns it off. An untracked client that does have a window is left alone and only mentioned in the log, in case you started it yourself.

where things are saved

Everything lives in %LOCALAPPDATA%\RobloxWatchdog\:

RobloxWatchdog.json, your settings. The RAM password in it is encrypted for your Windows account only, so a copy of the file is useless anywhere else
RobloxWatchdog.log, everything the watchdog did, including why it stopped. The Log button in the window shows the same thing. "teleported and rejoined" lines are the normal case above and mean nothing is wrong
WindowPositions.json, where you dragged each account's window

Settings get saved, so next time it's just start.
