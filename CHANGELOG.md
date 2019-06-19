# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.55.1] - 2017-10-17
### Changed
- Updated the last batch of commands with hard coded GDI/NOD team names
- Modified game_info and player_info parsing to improve custom team name support
- Slight tweaks to how join messages are suppressed when a player is banned or kicked
- Updated the !forcetc command to use team IDs rather than names
- Fix typo making !cmsgt not work properly
- Fix double sender name on ppages from the bot or IRC dwellers when cmsg paging is enabled
### Removed
- Remove hard coded team names in gamelog processing
- Removed hard coded team names from the autobalance module
- Removed the !teams command

1.54.x
 - Missing information - to be added later.

## 1.53.11 - 2012-02-29
### Added
### Changed
- Fix some quote replacement issues in logging related functionality
- Fix problem with case sensitivity when verifying auth passwords
- Fixed autoannounce command calling an old, removed function
- Fixed `IsHalfMod()`, `IsMod()` and `IsAdmin()` functions in modules.pm
- Modified map settings announcement to not include the donation limit when it is set to zero or the donations module is disabled
- Fixed a crash when kicking a banned player who joins the server
### Removed
- Removed redundant RG related function `is_serial_banned` from modules.pm

## 1.53.10 - 2012-01-08
### Changed
- Fix missing MD5 library which prevented auth passwords being verified
- Changed default presets.cfg entry for mp_GDI_War_Factory to "Weapons Factory" from "War Factory"
- Removed some redundant duplicated RenRem functions

## [1.53.9] - 2011-08-25
### Changed
- Fixed !auth command not working correctly
- Fixed FindInstalledMap expecting the search string to not include the last character in the name
- Fixed output of date on midnight rollover
- Tweaked default help value for !allow command
- Tweaked kick / ban mechanisms to not send a pamsg when using SSGM 4.0s ban system, which sends an additional message of its own, resulting in a double message
- Replace a reference to NOD in the default presets.cfg with Nod

## [1.53.8] - 2011-08-07
### Added
- Added a new function to handle console output and add timestamps to each message
- Added support for SSGM 4.0 resource manager
### Changed
- Improved handling of the midnight alarm trigger
- Improved wording & formatting of some console messages
- Fix GSA flood protection so that it cleans up old records instead of simply gobbling up more and more memory over time
- Reworked parts of the authentication system to be more centralised, rather than having duplicate code spread out across several modules

## [1.53.7] - 2010-08-13
### Added
- Replaced `Seperate_Donate_From_Gamelog` option with a `Enable_Gamelog_Loaded_Checks` option which applies to a wider range of functions
- Added `getBrVersion()` and `getBrBuild()` to plugin interface
- Added `isPlayerLoaded()` to the plugin interface
- Added ability to parse paths.ini file to locate logfiles
- Added support for SSGM 4.0 TCP logging of SSGMLog, Gamelog and Renlog
- Added support for SSGM 4.0 banning and kicking system
### Changed
- Fixed crash bug when autorec settings in brenbot.cfg were set to 0
- Improved _Primary IP not found_ error message to indicate it is related to Gamespy and to suggest setting the `Gamespy_IP` setting in the config file to resolve the problem
- Fixed bug where !killme command would not correctly use the kill console command when brenbot.dll is installed on the server
- AutoAnnounce can now be disabled by setting the interval to 0 in brenbot.cfg and it's session is created later in the startup procedure
- Plugins events are now executed using eval to prevent them from crashing the bot
- Overhauled the banning and kicking system and merged the kickban and ban commands into a single command with the functionality of the kickban command

## [1.53.6] - 2009-07-05
### Changed
- Fixed crash bug relating to how plugin configuration is loaded
- Modified database query function to print failed SQL statements to the console without crashing for easier debugging
### Removed

## [1.53.5] - 2009-06-22
### Added
- Added `recommendations_recent_history` table to database
-- Recommendations and n00bs are now stored in the `recommendations_recent_history` table for one week
### Changed
- Fixed crash bug in recommendations announcement
- Moved authentication code into seperate module
- Recommendation and n00b limits reworked to use new recent history table
- Reworked some parts of the command processor based on Perl 5.10 warnings
- Fixed plugin loader

## [1.53.4] - 2009-06-21
### Added
- Added `IsNumeric($input)` utility function to plugin interface
- Replaced `Force_bhs_dll` option with `Minimum_scripts_version` option in brenbot.cfg
- Added ability to enable / disable gamespy_players module without restarting BRenBot
### Changed
- Fixed issue where setting some values in mapsettings.xml to 0 would result in them not being applied
- Fixed an issue where the gamespy gameport setting would not be loaded properly
- Updated codebase to ActivePerl 5.10 from 5.6, updates all modules to latest versions
- Updated database from SQLite2 to SQLite3
- Replaced recommend and n00b tables in database with recommendations table, which contains the number of recommendations and n00bs each player has recieved
- Fix to loading plugins to workaround issues with PAR-Packer
- Changed handling of IRC 433 message code (nick in use) so that the bot will not keep adding _1 after a connection timeout, and will instead try it's original nick again
- Fixed bug where ban check queries were not using the database safe string prepared for them, and therefore failing to return results
- Fixed spelling of library (from libary) in several places
- Reworked scripts version enforcement to trigger much more quickly
- Improved recommendations code to make it more efficient
- GSA code optimizations
- Made !set command case-insensitive
- Bugfix for !donate to show correct error when player not found
- Module gamespy_players module now shows error state in !modules command
### Removed
- Stripped out some redundant code relating to bhs.dll existance

## [1.53.3] - 2008-11-14
### Added
- Added ability to detect tt.dll and enable support
### Changed
- Fixed grammatical fail in no results found message for logsearch command
- Modified config loading to allow spaces in `FDSConfigFile` and `FDSLogFilePath`
### Removed
- Removed `RenRemLinux*` configuration settings from brenbot.cfg, these are now loaded from server.ini
- Removed long redundant LadderLookup option from default brenbot.cfg file

## [1.53.2] - 2008-10-14
### Added
- Added serverMsg, isTempMod, isHalfMod, isFullMod, isAdmin and getIrcPermissions functions to plugin interface.
- Replaced !cp function with !scripts function. The !scripts function lists all ingame players along with their scripts (bhs.dll/tt.dll) version.
### Changed
- Fixed issue where BRenBot would print a message about needing parserDetails.ini on loading
- Replaced 2007 with 2008 in copyright notices
- Fixed !ids command to actually show ids

## [1.53.1] - 2008-09-30
### Changed
- Disabled some non-functional commands
- Disabled STDIN and STDOUT buffering so error messages are displayed properly
### Removed
- Removed all RenGuard related functionality

## [1.52.1] - 2007-09-10
### Added
- Support for SSGM 2.0 added
- New config option, `Moderators_Show_Join_Message`, which controls if the join message for moderators is shown ( XYZ is a full moderator etc)
- Added option for second IRC channel
- New commands.xml tag `hideInHelp`, which prevents the command from being shown in !help
- New config file `mapsettings.xml`, allows you to setup custom minelimits, vehicle limits and rules for any map.
- New module map_settings controls whether custom map settings are used.
- Added MD5 encryption to auth passwords
- Added new paging system which supports using CMSGP in place of ppage if both server and client have an updated bhs.dll. Controlled using the new `Enable_CMSG_Paging` option
- Added !vehiclelimit command to show / set vehicle limit
- Added !recommendations (!recs) command to page a player their current recs and n00bs
- Added support for IRC Oper auth
- Added `plugin::pagePlayer($player, $sender, $message)` to the plugin interface
- Added `plugin::RenRemCMDtimed ($command, $delay)` to the plugin interface
- Added !banip command to ban an ip or ip range. Range format is 123.123.123
- Modified !ban command to allow banning usernames which are not ingame
### Changed
- Major restructuring of player and game data within the bot
- IRC messages are no longer prefixed with [BR] (unless `prefixIRCMessages` is set to 1)
- End of game recommendations now correctly show map name instead of just 'last round'
- All references to 'BlazeRegulator' have been replaced with 'BRenBot'
- Added `$args{id}` and `$args{side}` parameters to playerjoin event in plugin interface
- Modules now appear in orange when in an error state
- Default file extensions are now .cfg and .log, which are more standard extensions
- Replaced POE IRC code with custom IRC code
- `Gamelog_*` settings can now be set to 0, 1 or 2. 1 Shows in admin channel only, 2 in both channels
- Renamed module usermessages to join_messages
- Bugfix to plugin interface to allow plugins with only one gamelog or renlog hook to load properly
- Updated !minelimit to be able to also set the minelimit when used by a moderator
- Fixed bug in plugin interface for plugins with no commands
- Kicked players are now automatically kicked if they rejoin again within 24 hours. This means !qkick and !kick are no longer the same thing for GSA / Direct Connect users
- Fixed bug where gameresults plugin event was not triggered properly
- Modified !teamplayers and !shown00bs so they can only be used once every 2 minutes
- Fix to prevent the bot hanging when a player has more recs than there are entries in recs.txt
- Adjustment to socket handling to improve memory usage
- Updated ban system to use one central table instead of three seperate ones
### Removed
- Removed module minelimit

## [1.50.2] - 2007-06-05
### Changed
- Updated RenGuard protocol to allow disconnected users time to reconnect to RenGuard before kicking them ( Full RG or Half-RG + forced user ).

## [1.50.1] - 2007-01-24
### Added
- Added option to withhold moderator rights from users who have not registered on the !auth system
- Added a plugin system to allow extra features to be added easily
- Added commands.xml config file, so all commands can be customised and restricted to specific user groups. help.txt is now redundant.
- Support for reading gamelog from ssaow log, as per the Write_Gamelog_to_SSAOWlog setting in ssaow.ini
- !getbw and !setbw commands added
- !kill and !killme commands added
- New file presets.brf allows you to setup your own preset translations
- New command !rgbans to view users who have been forced to use RenGuard
- Added !fds command to send text directly to the FDS console
- Added options to renguard.cfg to disable the messages about users without renguard in half renguard mode
- Added limited support for APB servers
- Added settings to brenbot.cfg to specific minimum score, kills, k/d to get the respective end of game recommendations
- Added autobalance module to automatically balance the teams at the start of a new map ( EG: Fanmaps where players leave after team remix)
- Added !shun and !unshun commands
- Added half moderators to the moderator system
- Added hostmessage for vehicles being stolen
- Added settings to renguard.cfg to prevent non renguard users from being able to vote, start votes or recieve recommendations
- Added the !ping command
- Added options to enable / disable gamelog messages to brenbot.cfg
- Added options to enable / disable specific types of votes to brenbot.cfg
- Added moderator symbols options to brenbot.cfg
- Added moderator symbols to their messages in IRC, and in several other places
- Added !reboot command and reboot.exe, Win32 only
- Added !cmsg, !cmsgt and !cmsgp commands
### Changed
- Fixed excessive CPU usage
- Updated !auth system to be more secure
- Can now auth by paging the bot an auth command from ingame
- Updated !buildings and !vehicles commands to work more effectivly
- Revamped voting system, including cyclemap vote type
- Uses gamelog2.txt instead of gamelog.txt, which is more CPU efficient
- !page now pages users on the server GSA style, !wpage pages WOL-style
- !modules has been revamped to be easier to see at a glance which modules are enabled. Added !about command for more info about specific modules.
- Rebuilt logging system to be more effective and useable than before
- Improved SSAOW support
- Fix to allow 'bye' and 'connect' in !msg commands
- Made ssc_ignore non-case sensitive
- Serial banning of RG users fixed
- End of game K/D recommendation now works for players with 0 deaths
- Rebuilt !setnextmap system to not accidentally rewrite the rotation permanently
- !pi can now search by IP address
- Replaced masters.brf and admins.brf with one new file, moderators.brf
- Added check to remove old data from the rg_stats table
- Added default options for most settings in brenbot.cfg, so deleting them no longer causes the bot to fail to load
- Added option to prevent moderators bypassing renguard requirements on commands to commands.xml
### Removed
- No more automatic recommendations for killing turrets / wreakages
- Removed the HTML_Output module and all database tables associated with it. See the new plugin if you still want this.
- Modules !teams and !seen are removed, as this can be controlled via commands.xml
- Removed the !seen command. See the new plugin if you still want this.

## [1.41] - 2005-01-17
### Added
- Added !rgplayers and !nonrgplayers
- Added support for configurable minelimit via scripts.dll 2.0
- Added support for donation limitations
- Added support for crate messages in gamelog in SSAOW
- Added modules !kickmessage and cratemsg, to filter specific gamelog messages
### Changed
- Fixed various half renguard issues (spamming, not properly detecting etc)
- Fixed cpu lockup/cpu performance issues

## [1.40] - 2004-11-29
### Added
- Added detailed fds logging (gamelog) to display various ingame live statistics.
- Added BHS.dll support. (pamsg, ppage, forcetc etc)
- Added auto recommendations for various gameplay actions
- Added !amsg command to enable people on IRC to send an Admin Message into the game.
- Added !restart, !shutdown command for restarting the FDS.
- Added !gi command for a new one-line Game Info status command. It will display playercount / teamscore on one line.
- Added IRC Channel keys are now supported, you can set this in the brenbot.cfg file.
- Added !vote stop command to stop any votes in progress when voting is enabled.
- Added !donate command to give players the ability to donate money to their teammates (gamelog and bhs.dll required)
- Added bhs.dll enforcement via a server config cvar. (set Force_bhs_dll = 1 in brenbot.cfg)
- Added IP Banning feature (!ban automatically bans by IP too)
- Added WOLSpy Clone for WOL Based servers (see section for install guide)
- Added "Half-RenGuard" mode, that allows non-RG players into the server
### Changed
- Resolved various minor problems and optimized code.
- When people type !help the response will now be paged to them instead of being displayed publically and cause some 'flooding' in some cases.
- General code optimizations.
- LOTS OF BUGFIXES
- Revamped RenGuard Support, much more stable now

## [1.36] - 2004-11-01
_Public Testing release, which turned into BRenBot 1.40_

## [1.35] - 2004-04-14
### Changed
- WOL related RenGuard bugfix

## [1.34] - 2004-04-14
### Added
- Added ability to ban by serial hash (RenGuard only)
- Added !rglocate (RenGuard only)
### Changed
- Various RenGuard Fixes

## [1.33] - 2004-04-07
### Added
- RenGuard Support (see RenGuard section)
- Added !rehash command which reloads all configs (so you dont have to restart the bot after adding moderators etc.)
- Added code to make brenbot rejoin its home channel if kicked.
- Added highlighting of mods/tempmods names in !playerinfo
- Added bounds checking for all msg commands to prevent buffer overflow/FDS crash exploit (including !setjoin/!viewjoin).
### Changed
- BRenbot now rejoins channel if kicked
- Reconnects to IRC if disconnected
- Proper spacing of name column in !playerinfo
- Fixed the "!shownextmap doesn't work" issue, as well as the "!setnextmap or !vote map blah" sets to an invalid map issue.
- Minor code cleanup (removing debug code, cosmetic indention, etc)
- Fixed bug where config file was not parsed correctly depending on spaces around the equal signs.
- Fixed issue with not getting a rec for most kills if you have zero deaths.
- Removed !ban powers from TempMods.
- General code optimizations.
### Removed
- Removed bogus !status command.
- Removed dependency on perlglob.exe. Now using internal directory scanning code to get mapnames.
- Removed hard coded autoresponses for "refill", "base to base", and "spawn kill".

## [1.31] - 2001-04-01
### Changed
- Fixed problem with auto-recommendations not working for LFDS or Win32+GSA.
- Fixed problem with LFDS not detecting the host IP.

## [1.30] - 2004-03-01
### Added
- added native win32 renrem support
- added filter to !playerinfo (!pi <keyword>)
- added !ids
- added !version
- added !uptime
- added !kickban (!kb)
- added !kick, !ban, !kickban by id
- added vehicle purchases
- added automatic recommendations after a round has ended
- added bold/underline nicknames for mods/tempmods
- added nickserv authentification
- added INVITE function (WOL mode only)
### Changed
- lots of bugfixes
- migration of win32 code into one code base
- made !playerinfo formatted nicely

## [1.29] - 2003-10-09
### Added
- added !shown00bs
- added !n00b
### Changed
- bugfixes
- changed gamespy broadcasting to every 5 mins
- Automatic IRC disconnect when disconnected from server

## [1.28] - 2003-10-05
### Added
- module support
- new gamespy query handler for extended information on ASE/Gamespy
- !teams
- playing of random (nasty) recommendation messages when a player joins
### Changed
- runtime Error Detection
- !deltempmod bugfix
- !auth bugfix

## [1.24] - 2003-08-04
### Changed
- irc channel bugfix

## [1.23] - 2003-07-24
### Added
- !auth
- playerlist being exported to htmlpages

## [1.22] - 2003-07-10
### Changed
- bugfixes
- detection of Fakenicknames (extension)

## [1.21] - 2003-07-07
### Added
- !delban
- CTCP Version Reply
- detection of Fakenicknames

## [1.19] - 2003-07-06
### Added
- html export

## [1.18] - 2003-07-07
### Changed
- distinction of normal and oppped/voiced users on IRC

## [1.14] - 2003-07-05
### Added
- new banlist

## [1.13] - 2003-07-03
### Added
- added !teamplayers
- added !seen
- added !setjoin
- added !viewjoin

## [1.11] - 2003-06-16
### Added
- added "!vote map cyclemap" to change to the next map in rotation

## [1.10] - 2003-06-13
### Added
- added Mapvoting

## [1.9] - 2003-06-12
_First public release to selected testers_
### Added
- added Q auth
- added !setnextmap
- added !maplist
- added !help