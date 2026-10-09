# Changelog

Changes to RobloxWatchdog.ps1, newest first. Project Miniwar AFK, programmer FG.

## 022 - 09-10-2026

Only one watchdog runs at a time. Closing the window hides it to the tray, so starting it again, or starting a new version while the old one was still in the tray, gave two watchdogs that each launched every account: a second client per account, and the Log window of either one only showed its own launches. A second copy now says the watchdog is already running and where to find it, writes that to the log file, and closes without launching anything. Older versions do not take the lock, so a running copy with the same exe name is also checked for. A restart after a crash waits for the crashed copy to be gone instead of refusing.

## 021 - 09-10-2026

Roblox 0.742 no longer logs "Sending disconnect with reason: 277", but "Client has been disconnected with reason:" with the reason as a sentence. Only the old line was being looked for, so not a single drop was seen any more and a kicked client stayed on its error screen for good. Both forms are now recognised. Found by deliberately having an alt join from a second device. When the same account is started again by hand, Roblox kicks the old client. That one stayed on its error screen until someone closed it, and treated as a drop, a third client would come after the grace period and kick the new one in turn. Now the old one is closed and the new one adopted.

## 020 - 08-10-2026

Colour palette updated: deep dark purple with a soft violet accent instead of magenta, and gold for a main. Buttons and tickboxes are rounded and paint themselves (RoundButton, RoundCheckBox: a flat CheckBox ignores CheckedBackColor), the tabs are pills instead of buttons with a line underneath, and the selected account row is no longer Windows blue. Overlaps fixed: the column headers were 120 wide and Memory covered Up, the note for an optional main lay over the box below it, and the strip at the top had no room for a third line. Every window now has a 16 pixel margin and even gaps; Add server is in the bottom button row. Its own icon (RobloxWatchdog.ico, a violet eye) for the exe, the windows and the tray, instead of the blank default Windows icon.

## 019 - 07-10-2026

New colour palette: dark purple with magenta as the accent and orange for a main. The tabs are no longer a TabControl but our own buttons: Windows draws tab headers itself and ignores BackColor, and even with OwnerDrawFixed the strip around them stays white. The server list draws its own rows, because a ListBox otherwise uses the Windows blue. Add server sat on top of the notice about the tray; the window is 48 pixels taller.

## 018 - 07-10-2026

Multiple servers. Each server has its own link, place, accounts, step list, relog time, anti-idle and limits; main is per server and optional on the extra servers. The settings window has been rebuilt with tabs (Servers, Account Manager, Windows, Alerts, Housekeeping) instead of one long column. A server can be added while running, with the Add server button: running accounts keep their session and window, new ones are added at the end and start in turn.

## 017 - 06-10-2026

Aggressive anti-idle now ignores the configured key or spot and walks and jumps instead. A character that moves and jumps is harder to mistake for someone sitting still than a single key press.

## 016 - 06-10-2026

Space picked nothing in the picker: Space and Enter activate the button that has focus, and that was the Pick button itself, so the prompt was answered and the button pressed again. The button is now disabled while picking. Also, ctrl, alt or shift can now be held with it, and starting no longer sends a Discord message unless it came back by itself after a crash.

## 015 - 06-10-2026

Anti-idle only took Space or a single letter. Now any letter, digit or named key that the step list also knows, or a spot in the window to click on, with a Pick button that writes down the key or the spot for you. Also fixed: the mouse movement in aggressive mode read Left and Top from a rectangle that calls them X and Y, so since 1.6.0 the cursor was moved to 0,0 instead of to the middle of the window.

## 014 - 06-10-2026

Remembering window positions did not work for many people. Three causes: the size was never compared, so only dragging was noticed and not resizing; it took 60 pixels before a drag counted; and when the move was denied, which happens when the clients run as administrator and the watchdog does not, there was nothing left to compare against and the whole feature did nothing. Now the actually measured rectangle is stored, even after a denied move. Also two buttons to save and restore the whole layout, sizes included.

## 013 - 06-10-2026

Pause stopped the relaunching but not the watching: logs were still read, it still decided an account had changed server, and it still closed a client over a disconnect that then could not be relaunched. Pause now does nothing at all, and on resume whatever the log files gained in the meantime is skipped. Also a setting to adopt the Roblox windows already open instead of closing them and starting again: the oldest becomes main and the rest alts in the order they started, each with its own log file found through the start time of the process. Closing and adopting are opposites, so only one of the two can be on in the settings window: the other turns off as soon as you turn one on.

## 012 - 06-10-2026

Roblox can refuse a join with 403 and challengedByGcs, after which the client shows the press and hold check. That looked like being stuck on an error, so the client was closed after 150 seconds and started again: three times in seven minutes on 05-10, and every attempt makes Roblox ask again. Now the window is left alone until someone does the check, with an alert about it, and after that the account simply carries on.

## 011 - 05-10-2026

Roblox writes the rejoin and the disconnect from different threads, so the order is not certain. In a teleport of six accounts, one of them had the rejoin 20 ms before the disconnect, and because only what came after was looked at, that client was closed and relaunched anyway. The game's own teleport message now decides it, since it never appears with a real drop. Also: the warning that focus is being refused now comes once instead of every minute per account. A teleport is in practice a relog: the character respawns and the inventory is back in the hotbar, so everything that was placed by hand has to be done again. It is now called that and reported, always for main and for a group of three or more at once. The notice that the setup is needed again used to depend on having a step list, so anyone doing it by hand heard nothing.

## 010 - 05-10-2026

The private server occasionally moves to a new instance and takes all the accounts with it. That was read as six separate drops and everything was restarted, while nothing was wrong. Now a new address is only judged at the end of the pass: if several accounts end up on the same new address, it is a move and everything stays. If an account is alone on an address where nobody else is, it really is gone. Anti-idle: focus was refused 22% of the time and that cost a minute each time; it is now asked for again straight away. Also a setting for aggressive anti-idle: twice as often, with walking, mouse movement and two key presses instead of one. A teleport makes the character respawn, so the setup is needed afterwards just as much as after a restart. That was missed since teleports no longer lead to a restart, which left main standing at spawn without rockets and without any notice. The watchdog now also checks whether a newer version is out and says so on the strip at the top, clickable through to the download page. Once every six hours, in the background, and if it fails nothing happens.

## 009 - 04-10-2026

Roblox sometimes refuses to start a second client by crashing in its own SingleInstanceGuard: the new launcher cannot reach the window of the running client and stops before there is a window. RAM reports nothing, because RAM did its part. That was waited out for 90 seconds and then retried endlessly, while retrying fixes nothing. Now the crash is recognised in the log file of the failed start and all clients are closed, main included, because that is the only thing that fixes it. After that they all start again, with at most one reset per ten minutes so it cannot bounce.

## 008 - 04-10-2026

The game teleports players between rounds: the client leaves the server, logs a disconnect and comes back to that same server five seconds later, in the same process. That was read as a drop and the healthy client was closed and started again: 728 of the 785 disconnects in the log file. Now it waits to see whether the client comes back to the same server by itself, and only relaunches if it does not. A process that disappeared is no longer proof either: a warm-started session is taken over instead of relaunched, and otherwise it is counted and reported. A session without a log file now keeps searching until it has one, because without a log file the watchdog sees nothing.

## 007 - 04-10-2026

RAM refuses a launch with text in the response instead of with a status code. That text was thrown away, so a refused launch waited 90 seconds for a window that never came and then retried endlessly without explanation. Now the launch stops immediately with RAM's message included, and the status window shows the last error per account.

## 006 - 26-09-2026

A status window instead of a console: the loop is now a state machine that takes one step per tick, so the window does not freeze during a launch. Tray icon, pause button, relaunching accounts individually and a visible notice when permissions are missing. The accounts are now spread over all monitors by screen area.

## 005 - 25-09-2026

A client that starts but never gets into the game is relaunched (there is no disconnect code for "failed to connect"), stray processes without a window are cleaned up, fatal errors go to the log file instead of only the console.

## 004 - 23-09-2026

Frame rate cap against CPU usage, anti-idle: window to the front and a key press so Roblox does not kick the client after 20 minutes.

## 003 - 22-09-2026

Security: settings moved to LOCALAPPDATA, password encrypted (DPAPI), file permissions locked down, private server link validated, PID reuse handled. Robustness: errors in the loop no longer fatal, backoff after failed launches, HTTP timeout, log file, truncated log file handled.

## 002 - 21-09-2026

Disconnect detection through the Roblox log files, main is also relaunched and tiled (slot 0).

## 001 - 19-09-2026

Password required, fallback without LinkCode removed, RAM response logged, a new window is the success check, full private server link through JobId.
