####################################
Readme file for BRenBot 1.53
####################################

This file contains setup instructions, general troubleshooting
information and information on how to obtain support for BRenBot 1.53.

BRenBot is a Blackhand Studios product, visit the BHS website at
http://www.blackhand-studios.net

This readme is considered to be correct at the time of writing. If you
find any mistakes or would like to suggest changes, please contact an
active developer.

Readme file written by danpaul88, with several useful parts taken from
the pre-1.50 readme file.


####################################
Credits
####################################

BRenBot has been developed by;
Blazer
Mac
PackHunter
danpaul88

Thanks also go to the following for code contributions;
AmunRa
v00d00

BRenBot is Copyright 2003-2008 by Blackhand Studios. All Rights reserved.

Thanks to Gozy, Caveman, Hex, Fifaheld, cAmpa, trooprm02 and all the other
official 1.43 & 1.51 testers for helping find all the bugs during testing.

Thanks to Scorpio9a and Silent_Kane for deciphering RenRem/FDSTALK protocol,
and to Jeff T. Parsons aka bynari (Jeff.Parsons@Webgeeks.co.uk) for helping
convert the deciphered renrem to Perl.


####################################
Setup Instructions
####################################

Setting up BRenBot 1.53 is easy and quick to do, if you follow these
simple instructions. After installing both the RenegadeFDS and
BRenBot 1.53, you need to set up communication between them. This
is done via the RemoteAdmin* settings in the server.ini file.

Step 1.
Open your server.ini in RenegadeFDS/Server


Step 2.
Locate the following options and set them to the values given here

AllowRemoteAdmin = true
RemoteAdminPassword = yourpass
RemoteAdminIP = 127.0.0.1
RemoteAdminPort = 4949

Note: The lines with a ; on the front are NOT the actual options, and
not where you put these settings. It is recommended that you change the
pw option to an 8 digit password of your choice.


Step 3.
Open your brenbot.cfg file in RenegadeFDS/Server/BRenBot


Step 4.
Locate the following options and set them to appropriate values

BotName = brenbot
IrcServer = irc.n00bstories.com
IrcPort = 6667
ircAdminChannel = #brenbot

Set the BotName to something unique to your server (such as br_myclansrv), and
choose the IRC server and channel of your choice. The default server is
n00bstories, and the default admin channel #brenbot, but you should change this
to something unique to your server (such as #myclansrv ).


Step 6.
Finally locate the two settings below and check their paths are correct. If
you installed the FDS in the default location these paths should be correct.

FDSLogFilePath = C:/Westwood/RenegadeFDS/Server/
FDSConfigFile = C:/Westwood/RenegadeFDS/Server/Data/svrcfg_cnc.ini


Basic setup is now complete and BRenBot has enough information to connect
to your server, and perform all of it's functions.


####################################
IRC Dual Channel Mode
####################################

BRenBot has the ability to use two IRC channels simultaneously, an admin channel where
all commands can be used, and a public channel where a limited number of commands are
available. The public channel is disabled by default, to enable it simply type a channel
name into the ircPublicChannel option in brenbot.cfg.

Users in the public channel will see F2 chat and a limited amount of ingame information.
You can show more or less information to the public channel using the settings in
brenbot.cfg


####################################
Using the authorisation system
####################################

BRenBot 1.53 includes a secure authorisation system to prevent GSA or Direct Connect
users from stealing your mods names, and getting moderator access. The auth system
is always enabled, but only functions to its maximum potential when the
Moderators_Force_Auth option in brenbot.cfg is set to 1.

When a user joins the server with a registered name, BRenBot pages them asking for
their password to authorise them. If they are a moderator BRenBot will withold their
moderator powers until they have authorised themselves. If they do not do so within
60 seconds they will be kicked from the server.

If the Moderators_Force_Auth is enabled and a user joins the server with an unregistered
moderator name they will not get moderator powers. This means that unprotected names
cannot be abused, but it also means that all your moderators must protect their names
before they get their moderator powers.


How to register a name
Registering a username on BRenBot is very easy. All you need to do is login to IRC, and
open a private chat window with BRenBot ( double click on the bots name in mIRC). Then
type !register <playername> <password> to register a name. All of your moderators should
do this themselves, so they can use a password they will not forget. From now on anyone
using that name must authorise themselves when they join.


How to authorise
There are three ways to authorise yourself in this version of BRenBot. If you are on
XWIS/WOL you can page the bot from ingame by typing /page <serverlogin> !auth <password>,
replacing <serverlogin> with the login of the server you are on (EG: a00000001), and
<password> with the password you used.

If this does not work for you, you can join the IRC channel with the bot in, and
type !auth <name> to authorise yourself, but this requires you to have sufficient
status on the IRC channel. If you cannot use the !auth command open a PM window with
the bot and type !auth <name> <password> to authorise yourself.


####################################
Using the commands.xml file
####################################

The commands.xml file in BRenBot 1.53 gives you total control over who can
use which commands, and even lets you disable commands completely. The top part
of the file dealing with permissions is beyond the scope of this document, and
will not be dealt with here.

Let's look at an example command in the commands.xml file;

  <command name="shown00bs">
    <permission level="1"/>
    <syntax value="!shown00bs"/>
    <help value="Displays all n00bs"/>
    <enabled value="1"/>
    <group>irc_admin</group>
    <group>irc_public</group>
    <group>ingame</group>
    <alias>shownoobs</alias>
    <alias>n00bs</alias>
  </command>

At first this might look very confusing, so lets break it down a bit. The first line
identifies which command this setting is for, and should NEVER be changed.

The second line set's the permission level for this command. Default permissions are
between 1 (everyone) and 5 (admin only). This command is available to all users.

The next two lines are the syntax value and help value, which are used by the !help
command, and sometimes by the command itself.

The next line is the enabled line, which controls if the command is available or not.
Setting this to 0 will prevent the command being used at all.

The next three lines specify where the command can be used. In this case it can be used
from both irc channels and ingame. Deleting one of these lines will stop it being used
in that location.

The remaining lines define aliases for the command, so typing either of those will do
the same as if you typed the full name given on the top line.

The last line marks the end of the command settings, and should NEVER be changed.


####################################
Configuration Files
####################################

 - brenbot.cfg
Contains all of the main settings for BRenBot. The comments in the file explain what
each settings does.

 - autoannounce.cfg
Contains the autoannounce messages for BRenBot. Each message should be on a single line.

 - recs.txt
Part of the recommendations system, if the recommend module is enabled BRenBot sends
a message from this file when players join the game. Each message has an upper and
lower recommendations limit for when it is shown.

 - moderators.cfg
Replaces the masters.brf and admins.brf files in older versions of BRenBot. Contains
a list of all Administators, Moderators and Half Moderators on your server.

 - messages.cfg
Used by the !postmsg command and the !rules command. The first line of this file is
your server rules, and is shown when !rules is used. Each line after this can be
shown using !postmsg <linenumber>.

 - mapsettings.xml
Contains settings for vehicle and mine limits on each map, and time limits for the
!donate command. Only has an effect if the map_settings module is enabled.


####################################
Using the GameSpy broadcaster
####################################

BRenBot 1.53 includes a GSA protocol system which improves on that in the current
version of WOLSpy, and the original LFDS, by showing the names of players in the
game, as well as current game data. To use this you need to do the following;

Enable the gamespy_players module in BRenBot by typing !set gamespy_players on in
IRC. It's enabled by default, but if you turned it off then turn it back on. Now,
open brenbot.cfg and setup the following options;

Generate_Gamespy_Queries = 1
GameSpyQueryPort = 23500
Broadcast_Server_To_Gamespy = 1
GameSpy_IP = 123.123.123.123

Set the port and IP to those for your server. If you don't enable the
Broadcast_Server_To_Gamespy option, you can use this system to generate GSA style
queries on an un-announced query port, which can then be read by (example) PHP
scripts. You should now reboot BRenBot and it should be listed in GSA.

If you are using this on Linux to replace the outdated system in the LFDS it is a good
idea to block the original LFDS Gamespy Query Port. To do this, you need to block
incoming connections to your orginal Gamespy Query port (23500, for example). Then,
setup brenbot to listen on another query port, and configure it to broadcast it's open
port to Gamespy too.


####################################
Troubleshooting
####################################

Some common problems people have with BRenBot, if you can't find the answer here
please see the Technical Support section below this one.


Problem: The bot seems to work, but no messages showup ingame, and some commands
do not work

Resolution: Usually this is caused by incorrect remote admin settings. Ensure that
AllowRemoteAdmin in server.ini is set to true and that the RemoteAdminPassword is
set to an 8 character string. See the setup section for the exact names of these
settings. This can also occur when two or more FDS installations on the machine
are configured with the same RemoteAdminPort setting.


Problem: BRenBot closes as soon as it starts to load, or closes for no reason randomly

Resolution: It's probably closing due to a fatal error condition. To see the error
message before it closes run the bot in command prompt. To do this go to Start->Run
and enter the word cmd, and then hit enter.

Now type in cd C:\Westwood\RenegadeFDS\Server\BRenBot\, changing this to match the path
to your brenbot folder, and hit enter. Now type in brenbot.exe and hit enter, and the
bot should load up. When BRenBot closes you should see the reason why.


Problem: BRenBot opens a blank console window and hangs forever

Resolution: This is often caused by a corrupted PAR cache and can be fixed by deleting
the cache folder. This is located in the temporary files folder, to locate it type
%temp% into Windows Explorer and look for a folder in there named par-<yourusername>.
When you find this folder delete it and then try to run BRenBot again.


####################################
Technical Support
####################################

For technical support please visit www.renegadeforums.com and post
your query in the Technical Support -> Other subforum.


####################################
Getting plugins
####################################

Several plugins are available from the BRenBot website, http://new.brenbot.com/


####################################
Changelog
####################################

1.53.11 ( ?? ??? 12 )
 - Fix some quote replacement issues in logging related functionality
 - Fix problem with case sensitivity when verifying auth passwords
 - Removed redundant RG related function is_serial_banned from modules.pm
 - Fixed autoannounce command calling an old, removed function
 - Fixed IsHalfMod(), IsMod() and IsAdmin() functions in modules.pm
 - Modified map settings announcement to not include the donation limit when it is set to zero or
     the donations module is disabled

1.53.10 ( 08 Jan 12 )
 - Fix missing MD5 library which prevented auth passwords being verified
 - Changed default presets.cfg entry for mp_GDI_War_Factory to "Weapons Factory" from "War Factory"
 - Removed some redundant duplicated RenRem functions

1.53.9 ( 25 Aug 11 )
 - Fixed !auth command not working correctly
 - Fixed FindInstalledMap expecting the search string to not include the last character in the name
 - Fixed output of date on midnight rollover
 - Tweaked default help value for !allow command
 - Tweaked kick / ban mechanisms to not send a pamsg when using SSGM 4.0s ban system, which sends an
     additional message of its own, resulting in a double message
 - Replace a reference to NOD in the default presets.cfg with Nod

1.53.8 ( 07 Aug 11 )
 - Improved handling of the midnight alarm trigger
 - Added a new function to handle console output and add timestamps to each message
 - Improved wording & formatting of some console messages
 - Fix GSA flood protection so that it cleans up old records instead of simply
     gobbling up more and more memory over time
 - Added support for SSGM 4.0 resource manager
 - Reworked parts of the authentication system to be more centralised, rather than having duplicate
     code spread out across several modules

1.53.7 ( 13 Aug 10 )
 - Added getBrVersion() and getBrBuild() to plugin interface
 - Fixed crash bug when autorec settings in brenbot.cfg were set to 0
 - Replaced Seperate_Donate_From_Gamelog option with a Enable_Gamelog_Loaded_Checks option
     which applies to a wider range of functions
 - Added isPlayerLoaded() to the plugin interface
 - Added ability to parse paths.ini file to locate logfiles
 - Improved 'Primary IP not found' error message to indicate it is related to Gamespy and
     to suggest adding the Gamespy_IP line to the config file to resolve the problem
 - Fixed bug where !killme command would not correctly use the kill console command when
     brenbot.dll is installed on the server
 - AutoAnnounce can now be disabled by setting the interval to 0 in brenbot.cfg and it's
     session is created later in the startup procedure
 - Plugins events are now executed using eval to prevent them from crashing the bot
 - Added support for SSGM 4.0 TCP logging of SSGMLog, Gamelog and Renlog
 - Added support for SSGM 4.0 banning and kicking system
 - Overhauled the banning and kicking system and merged the kickban and ban commands into
     a single command with the functionality of the kickban command

1.53.6 ( 05 Jul 09 )
 - Fixed crash bug relating to how plugin configuration is loaded
 - Modified database query function to print failed SQL statements to the console without
     crashing for easier debugging

1.53.5 ( 22 Jun 09 )
 - Fixed crash bug in recommendations announcement
 - Moved authentication code into seperate module
 - Added recommendations_recent_history table to database
 - Recommendations and n00bs are now stored in the recommendations_recent_history table for
     one week
 - Recommendation and n00b limits reworked to use new recent history table
 - Reworked some parts of the command processor based on Perl 5.10 warnings
 - Fixed plugin loader

1.53.4 ( 21 Jun 09 )
 - Fixed issue where setting some values in mapsettings.xml to 0 would result in them not being
     applied
 - Added IsNumeric($input) utility function to plugin interface
 - Fixed an issue where the gamespy gameport setting would not be loaded properly
 - Updated codebase to ActivePerl 5.10 from 5.6, updates all modules to latest versions
 - Updated database from SQLite2 to SQLite3
 - Replaced recommend and n00b tables in database with recommendations table, which contains the
     number of recommendations and n00bs each player has recieved
 - Fix to loading plugins to workaround issues with PAR-Packer
 - Changed handling of IRC 433 message code (nick in use) so that the bot will not keep adding _1
     after a connection timeout, and will instead try it's original nick again
 - Fixed bug where ban check queries were not using the database safe string prepared for them, and
     therefore failing to return results
 - Fixed spelling of library (from libary) in several places
 - Replaced Force_bhs_dll option with Minimum_scripts_version option in brenbot.cfg
 - Reworked scripts version enforcement to trigger much more quickly
 - Stripped out some redundant code relating to bhs.dll existance
 - Improved recommendations code to make it more efficient
 - GSA code optimizations
 - Made !set command case-insensitive
 - Added ability to enable / disable gamespy_players module without restarting BRenBot
 - Module gamespy_players module now shows error state in !modules command
 - Bugfix for !donate to show correct error when player not found

1.53.3 ( 14 Nov 08 )
 - Fixed grammatical fail in no results found message for logsearch command
 - Added ability to detect tt.dll and enable support
 - Modified config loading to allow spaces in FDSConfigFile and FDSLogFilePath
 - Removed RenRemLinux* configuration settings from brenbot.cfg, these are now loaded from
     server.ini
 - Removed long redundant LadderLookup option from default brenbot.cfg file

1.53.2 ( 14 Oct 08 )
 - Fixed issue where BRenBot would print a message about needing parserDetails.ini on loading
 - Replaced 2007 with 2008 in copyright notices
 - Added serverMsg, isTempMod, isHalfMod, isFullMod, isAdmin and getIrcPermissions functions to
     plugin interface.
 - Replace !cp function with !scripts function. The !scripts function lists all ingame players along
     with their scripts (bhs.dll/tt.dll) version.
 - Fixed !ids command to actually show ids

1.53.1 ( 30 Sep 08 )
 - Removed all RenGuard related functionality
 - Disabled some non-functional commands
 - Disabled STDIN and STDOUT buffering so error messages are displayed properly

1.52.1 ( 10 Sep 07 )
 - Major restructuring of player and game data within the bot
 - IRC messages are no longer prefixed with [BR] (unless prefixIRCMessages is set to 1)
 - End of game recommendations now correctly show map name instead of just 'last round'
 - All references to 'BlazeRegulator' have been replaced with 'BRenBot'
 - Added $args{id} and $args{side} parameters to playerjoin event in plugin interface
 - Modules now appear in orange when in an error state
 - Support for SSGM 2.0 added
 - Default file extensions are now .cfg and .log, which are more standard extensions
 - New config option, Moderators_Show_Join_Message, which controls if the join message for
     moderators is shown ( XYZ is a full moderator etc )
 - Replaced POE IRC code with custom IRC code
 - Added option for second IRC channel
 - New commands.xml tag 'hideInHelp', which prevents the command from being shown in !help
 - Gamelog_* settings can now be set to 0, 1 or 2. 1 Shows in admin channel only, 2 in both channels
 - New config file mapsettings.xml, allows you to setup custom minelimits, vehicle limits and rules
     for any map.
 - New module map_settings controls whether custom map settings are used.
 - Removed module minelimit
 - Renamed module usermessages to join_messages
 - Added MD5 encryption to auth passwords
 - Bugfix to plugin interface to allow plugins with only one gamelog or renlog hook to load properly
 - Added new paging system which supports using CMSGP in place of ppage if both server and client
     have an updated bhs.dll. Controlled using the new Enable_CMSG_Paging option
 - Added !vehiclelimit command to show / set vehicle limit
 - Added !recommendtaions (!recs) command to page a player their current recs and n00bs
 - Updated !minelimit to be able to also set the minelimit when used by a moderator
 - Added support for IRC Oper auth
 - Fixed bug in plugin interface for plugins with no commands
 - Kicked players are now automatically kicked if they rejoin again within 24 hours. This means
     !qkick and !kick are no longer the same thing for GSA / Direct Connect users
 - Fixed bug where gameresults plugin event was not triggered properly
 - Modified !teamplayers and !shown00bs so they can only be used once every 2 minutes
 - Fix to prevent the bot hanging when a player has more recs than there are entries in recs.txt
 - Added plugin::pagePlayer( $player, $sender, $message ) to the plugin interface
 - Added plugin::RenRemCMDtimed ( $command, $delay ) to the plugin interface
 - Adjustment to socket handling to improve memory usage
 - Updated ban system to use one central table instead of three seperate ones
 - Added !banip command to ban an ip or ip range. Range format is 123.123.123
 - Modified !ban command to allow banning usernames which are not ingame

1.50.2 ( 05 Jun 07 )
 - Updated RenGuard protocol to allow disconnected users time to reconnect to RenGuard before
     kicking them ( Full RG or Half-RG + forced user ).

1.50.1 ( 24 Jan 07 )
 - Fixed excessive CPU usage
 - Updated !auth system to be more secure
 - Added option to withhold moderator rights from users who have not registered on the !auth system
 - Can now auth by paging the bot an auth command from ingame
 - Added a plugin system to allow extra features to be added easily
 - Updated !buildings and !vehicles commands to work more effectivly
 - Revamped voting system, including cyclemap vote type
 - Added commands.xml config file, so all commands can be customised and restricted to specific user
     groups. help.txt is now redundant.
 - Uses gamelog2.txt instead of gamelog.txt, which is more CPU efficient
 - Support for reading gamelog from ssaow log, as per the Write_Gamelog_to_SSAOWlog setting in
     ssaow.ini
 - !getbw and !setbw commands added
 - !page now pages users on the server GSA style, !wpage pages WOL-style
 - !modules has been revamped to be easier to see at a glance which modules are enabled. Added
     !about command for more info about specific modules.
 - No more automatic recommendations for killing turrets / wreakages
 - Rebuilt logging system to be more effective and useable than before
 - Improved SSAOW support
 - !kill and !killme commands added
 - New file presets.brf allows you to setup your own preset translations
 - New command !rgbans to view users who have been forced to use RenGuard
 - Fix to allow 'bye' and 'connect' in !msg commands
 - Added !fds command to send text directly to the FDS console
 - Made ssc_ignore non-case sensitive
 - Serial banning of RG users fixed
 - End of game K/D recommendation now works for players with 0 deaths
 - Added options to renguard.cfg to disable the messages about users without renguard in half
     renguard mode
 - Rebuilt !setnextmap system to not accidentally rewrite the rotation permanently
 - Removed the HTML_Output module and all database tables associated with it. See the new plugin if
     you still want this.
 - Modules !teams and !seen are removed, as this can be controlled via commands.xml
 - !pi can now search by IP address
 - Added limited support for APB servers
 - Added settings to brenbot.cfg to specific minimum score, kills, k/d to get the respective end of
     game recommendations
 - Added autobalance module to automatically balance the teams at the start of a new map ( EG:
     Fanmaps where players leave after team remix)
 - Added !shun and !unshun commands
 - Added half moderators to the moderator system
 - Replaced masters.brf and admins.brf with one new file, moderators.brf
 - Removed the !seen command. See the new plugin if you still want this.
 - Added hostmessage for vehicles being stolen
 - Added check to remove old data from the rg_stats table
 - Added default options for most settings in brenbot.cfg, so deleting them no longer causes the bot
     to fail to load
 - Added settings to renguard.cfg to prevent non renguard users from being able to vote, start votes
     or recieve recommendations
 - Added the !ping command
 - Added options to enable / disable gamelog messages to brenbot.cfg
 - Added options to enable / disable specific types of votes to brenbot.cfg
 - Added moderator symbols options to brenbot.cfg
 - Added moderator symbols to their messages in IRC, and in several other places
 - Added !reboot command and reboot.exe, Win32 only
 - Added option to prevent moderators bypassing renguard requirements on commands to commands.xml
 - Added !cmsg, !cmsgt and !cmsgp commands


1.41 (01/17/2005)

1. Fixed various half renguard issues (spamming, not properly detecting etc)
2. Fixed cpu lockup/cpu performance issues
3. Added !rgplayers and !nonrgplayers
4. Added support for configurable minelimit via scripts.dll 2.0
5. Added support for donation limitations
6. Added support for crate messages in gamelog in SSAOW
7. Added modules !kickmessage and cratemsg, to filter specific gamelog messages

1.40 (11/29/2004)

1. Added detailed fds logging (gamelog) to display various ingame live statistics.
2. Added BHS.dll support. (pamsg, ppage, forcetc etc)
3. Added auto recommendations for various gameplay actions
4. Added !amsg command to enable people on IRC to send an Admin Message into the game.
5. Added !restart, !shutdown command for restarting the FDS.
6. Added !gi command for a new one-line Game Info status command. It will display playercount / 
     teamscore on one line.
7. Added IRC Channel keys are now supported, you can set this in the brenbot.cfg file.
8. Added !vote stop command to stop any votes in progress when voting is enabled.
9. Resolved various minor problems and optimized code.
10. When people type !help the response will now be paged to them instead of being displayed
      publically and cause some 'flooding' in some cases.
11. General code optimizations.
12. LOTS OF BUGFIXES
13. Added !donate command to give players the ability to donate money to their teammates (gamelog
      and bhs.dll required)
14. Revamped RenGuard Support, much more stable now
15. Added bhs.dll enforcement via a server config cvar. (set Force_bhs_dll = 1 in brenbot.cfg)
16. Added IP Banning feature (!ban automatically bans by IP too)
17. Added WOLSpy Clone for WOL Based servers (see section for install guide)
18. Added "Half-RenGuard" mode, that allows non-RG players into the server

1.36 (11/01/2004)

Public Testing release, which turned into BRenBot 1.40

1.35 (04/14/2004)

1. WOL related RenGuard bugfix

1.34 (04/14/2004)

1. Various RenGuard Fixes
2. Added ability to ban by serial hash (RenGuard only)
3. Added !rglocate (RenGuard only)

1.33 (04/07/2004)

1. RenGuard Support (see RenGuard section)
2. Added !rehash command which reloads all configs (so you dont have to
restart the bot after adding moderators etc.)
3. BRenbot now rejoins channel if kicked.
4. Reconnects to IRC if disconnected.
5. Proper spacing of name column in !playerinfo
6. Removed bogus !status command.
7. Removed dependency on perlglob.exe. Now using internal directory scanning
code to get mapnames.
8. The above also fixes the "!shownextmap doesn't work" issue, as well as
the "!setnextmap or !vote map blah" sets to an invalid map issue.
9. Removed BAN powers from TEMP mods.
10. Added code to make brenbot rejoin its home channel if kicked.
11. Minor code cleanup (removing debug code, cosmetic indention, etc)
12. Fixed bug where config file was not parsed correctly depending on spaces
around the equal signs.
13. Removed hard coded autoresponses for "refill", "base to base", and
"spawn kill".
14. Fixed issue with not getting a rec for most kills if you have zero
deaths.
15. Removed !ban powers from TempMods.
16. Added highlighting of mods/tempmods names in !playerinfo
17. Added bounds checking for all msg commands to prevent buffer
overflow/FDS crash exploit (including !setjoin/!viewjoin).
18. General code optimizations.


1.31 (04/01/2004)
Fixed problem with auto-recommendations not working for LFDS or Win32+GSA.
Fixed problem with LFDS not detecting the host IP.

1.30 (03/01/2003)
lots of bugfixes
migration of win32 code into one code base
added native win32 renrem support
added filter to !playerinfo (!pi <keyword>)
made !playerinfo formatted nicely
added !ids
added !version
added !uptime
added !kickban (!kb)
added !kick, !ban, !kickban by id
added vehicle purchases
added automatic recommendations after a round has ended
added bold/underline nicknames for mods/tempmods
added nickserv authentification
added INVITE function (WOL mode only)

1.29 (10/09/2003)
bugfixes
added !shown00bs
added !n00b
changed gamespy broadcasting to every 5 mins
Automatic IRC disconnect when disconnected from server

1.28 (10/05/2003)
runtime Error Detection
module support
new gamespy query handler for extended information on ASE/Gamespy
!teams
!deltempmod bugfix
!auth bugfix
playing of random (nasty) recommendation messages when a player joins

1.24 (08/04/2003)
irc channel bugfix

1.23 (07/24/2003)
!auth
playerlist being exported to htmlpages

1.22 (07/10/2003)
bugfixes
detection of Fakenicknames (extension)

1.21 (07/07/2003)
!delban
CTCP Version Reply
detection of Fakenicknames

1.19 (07/06/2003)
html export

1.18 (07/07/2003)
distrinction of normal and oppped/voiced users on IRC

1.14 (07/05/2003)
new banlist

1.13 (07/03/2003)
added !teamplayers
added !seen
added !setjoin
added !viewjoin

1.11 (06/16/2003)
added "!vote map cyclemap" to change to the next map in rotation

1.10 (06/13/2003)
added Mapvoting

1.9 (06/12/2003)
first public release to selected testers
added Q auth
added !setnextmap
added !maplist
added !help