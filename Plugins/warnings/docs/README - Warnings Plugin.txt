Warnings Plugin
Version 1.50
Daniel Paul (danpaul88)
danpaul88@yahoo.co.uk


The warnings plugin for BRenBot 1.43 allows you to give warnings to players in the server, and have them qkicked, kicked and even banned after a specified number of warnings. It can also act as a swearbot, watching for specified words being said, which it will automatically issue warnings for.

The automatic word detection can also be enabled in the IRC channel, but be aware that BRenBot MUST have +op in the IRC channel to be able to kick people after they reach the IRC warnings limit. If it does not have +op it will not be able to kick them, and malicious users could crash / severely lag your bot by flooding it with disallowed words and causing it to send a lot of text to the IRC server. Due to the way perl's IRC module works, this would cause the bot to lag behind the server, as it outputs all the messages.

It should also be noted that although the autowarn_words.cfg file only has words in it by default, you CAN add phrases by putting the whole phrase on one line. Although this feature is untested, it should work. If it does not let me know and I will fix it for the next version.

The settings in the .xml file have comments explaining what they do, so I won't bother explaining them in here. If you need help feel free to ask!

If you want to ask any questions, request new features or report bugs please post on the Renegade Public forums (www.renegadeforums.com) in the Technical Support -> Other area, or email me.

###############
Installation
###############

Simply extract the contents of the .zip file to your BRenBot folder. If you are updating from an earlier version of the plugin you can do not need to extract autowarn_words.cfg.

If you do not want to redo all your settings in warnings.xml you should follow the instructions in the file 'Updating.txt'. Otherwise you should extract this new one and put your settings into it.

###############
Changelog
###############

1.51
 - Updated to work correctly in BRenBot 1.53
 - Package renamed to brwarnings to avoid conflicts with warnings module in Perl
 - Renamed autowarn_words.cfg to warnings_words.cfg and moved it to the plugins folder

1.50
 - Updated to work properly with updated IRC system in BRenBot 1.51
 - Removed internal logging system, all logs will now be in BRenBot's main logging system, and can be accessed with !logsearch
 - Removed ircMessagePrefix option
 - Removed !getlogs command

1.42
 - Support for updating through brLoader

1.40
 - Updated to be backwards compatible with BRenBot 1.50
 - Added banner and reason to !autoKB

1.35
 - Updated to support BRenBot 1.51. Will NOT work on earlier versions

1.33
 - Linux compatibility fix

1.32
 - Minor bugfix to prevent the number of expired warnings showing as 0E00E0 when the irc expire time and normal expire times are different

1.31
 - Updated warnings.xml to be compatable with 1.43 build 20 and above

1.3
 - No longer counts !warn commands as automatic warnings.
 - Fixed some output bugs caused by the IrcMessagePrefix configuration command.
 - Added advanced detection of disallowed words, automatically substituting different symbols in to try and catch out those attempting to bypass the autowarnings system.

1.2
 - Fixed incorrect position of bold text on !getlogs logs. The date and username are now in bold, instead of the log itself.
 - Added error message to !rw command when you forget to specify a name.
 - Added the ability to check for disallowed words in a players name when they join, and a corresponding config value in the .xml file
 - !reset_warnings <name> is no longer case sensitive
 - Fixed messages when qkicking, kicking or banning players for having too many warnings to not say '.. for: for ..'
- No longer says warningS when there is only 1 warning
- When the server is paged a swearword the offender is dealt with harshly! (!kick if they are in the server, or added to auto !kb list for later)
- Added the !autoKB range of commands, for automatically banning players who need banning.
- Added a few extra settings to warnings.xml
- Players now recieve a pamsg when they are warned.

1.1
 - Fixed !getlogs <name> to only get the 5 most recent logs, instead of all of them.
 - !getlogs <name> can now accept a partial name, and can return records for more than one person if the partial name is shared by several players. ( EG !getlogs dan would get logs for danpaul88 and lmsbcdan )
 - !warnings <name> is no longer case sensitive.
 - Using the !autowarnings with a dutation will now display the time in minutes and seconds, not just minutes.
 - The !autowarnings command will now always display it's output in the server only, even if used from IRC, since it should let players in the server know when they are being turned on and off.
 - The command !warning_stats can also return the statistics for the whole month, or even all time, now. Just add month or total after the command ( EG !warning_stats month ).
 - Fixed a bug in the warning expiry system which could cause the next warning to be expired slightly late.
 - Fixed a typo in the message given when an !atm player gets !dtm because of recieving a warning.
 - Added the command !clearWarningStats (!cws), which can be used to delete all old statistics. Player logs will NOT be affected by this.
 - Changed the output of the !warning_stats command to be a lot shorter and more concise.
 - Added the command !mostWarnedWords (!mww) - shows which words the automatic warnings function has issued the most warnings for.
 - Fixed the IRC kick function.
 - Added the command !reload_autowarn_words (!raww) - attempts to reload the list of swearwords from autowarn_words.cfg

1.02
 - Fixed greeting message showing incorrect number of warnings
 - Added a fix to prevent incorrect detections due to certain symbols in words / phrases.

1.01
 - Fixed code typo which caused the plugin to incorrectly think players were not in the server.
 - Fixed text on !autowarnings when used in-game with a duration to correctly report the new status

1.0
 - First Release

###############
Commands
###############

!warn <name> <reason>
Gives a warning to the specified player in the server, for the reason given. If the player is not found in the server, or the name given could refer to multiple players, the plugin will tell you so. Does not require full playername, partial is enough as long as it is unique.


!rw <name> (or !rw)
Reset's the warning count for the specified player to 0. Also works on IRC users, but you must add @IRC on the end of their IRC name for it to work. Requires the full player name.


!getlogs <name>
Reports how many logs exist for the specified playername, and shows the 5 latest ones. It will not show anymore than 5, as this would lag the bot. Be aware that spamming this command will cause BRenBot to lag, which is why by default only IRC ops can use this command. Can use a partial playername, but may return results for more than one person this way.


!warnings [<name>]
Shows how many warnings the specified player has. If no name is specified it shows how many warnings the person using the command has. Requires full player name.


!show_warnings
Shows the warnings for players in the server.


!show_all_warnings (or !saw)
Shows all the currently issued warnings, for IRC users, ingame players and players who are no longer in the server.


!words
Shows a list of the words and/or phrases that BRenBot will automatically issue warnings for.


!warning_stats [month/total]
Shows statistics for the warnings plugin for the current day. Future versions will also allow you to get a summary for the month, and for all time. If you add month on the end, it will show total statistics for the current month. If you add total on the end, it will show total statistics for all the time it has been running.


!autowarnings [on/off] [<duration>]
This command serves three functions, depending on how many arguments you give it. If you type !autowarnings, it will simply tell you if BRenBot's automatic warnings are enabled for ingame messages. If you specify on or off, it will turn the automatic warnings on or off. Finally, if you also specify a duration (in seconds), it will turn it on or off for that length of time, and then automatically switch it back. NOTE that this does not change the setting in the .xml file, so it will return to the setting specified in there if BRenBot is restarted.


!clearwarningstats (or !cws)
Deletes all statistics for the warnings plugin from it's database.


!mostwarnedwords (or !mww)
Lists the 5 words which the autowarnings function has warned people for most often.


!reload_autowarn_words (or !raww)
Reloads the swearwords list from autowarn_words.cfg.