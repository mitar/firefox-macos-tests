-- Prints the menus of the macOS menu bar of a process, as System Events reports them: each menu's title in brackets,
-- then its items, "---" for a separator and "(disabled)" after an item which cannot be chosen.
--
-- Usage: osascript menus.applescript PID

on run argv
	set pid to (item 1 of argv) as integer
	tell application "System Events"
		set p to first application process whose unix id is pid
		set frontmost of p to true
		delay 1
		set out to "process " & (name of p) & ", frontmost " & (frontmost of p) & linefeed
		repeat with barItem in menu bar items of menu bar 1 of p
			set out to out & "[" & (name of barItem) & "]" & linefeed
			try
				repeat with menuItem in menu items of menu 1 of barItem
					set itemName to name of menuItem
					if itemName is missing value then
						set itemLine to "    ---"
					else
						set itemLine to "    " & itemName
						if not (enabled of menuItem) then set itemLine to itemLine & " (disabled)"
					end if
					set out to out & itemLine & linefeed
				end repeat
			end try
		end repeat
		return out
	end tell
end run
