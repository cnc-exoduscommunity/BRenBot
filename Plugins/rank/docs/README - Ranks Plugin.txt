Ranks Plugin
Version 2.05
Daniel Paul (danpaul88)
danpaul88@yahoo.co.uk
Original plugin by PackHunter


The ranks plugin for BRenBot allows you to create a mini-ladder for your server, based on players
ingame actions and attributes.

If you want to ask any questions, request new features or report bugs please post on the
Renegade Public forums (www.renegadeforums.com) in the Technical Support -> Other area, or email me.


###############
Installation
###############

Extract the plugins folder to your BRenBot folder. It is advised that you make a backup of
your rankings.dat file if you are updating from an older version of the plugin.

If you want to show this information on your website it is recommended you use the PHP scripts
created by Hex for use with this plugin. They are included inside the Ranks_PHP_By_Hex.zip file,
which contains it's own readme for installing the PHP files.

NOTE: The PHP scripts do NOT currently support the SQL dump option for outputFormat, but could
be modified to work with them.

Also be aware that the SQL Dump capability relies upon the sqlite.exe file included with the
plugin. If you do not require this capability you can safely delete sqlite.exe. The executable
can also be obtained from http://www.sqlite.org/sqlite-2_8_17.zip if you have deleted it but
now decide to use the SQL Dump option.


###############
Additional Credits
###############
Hex - PHP files for server side support
gkl21 - SQL dump support for ranks.txt


###############
Changelog
###############

2.05
 - Updated for BRenBot 1.53.4 and higher (Perl 5.10)
 - Fixed check for outputFormat parameter, SQL dump mode should work properly now
 - Changed default state for FTP upload to disabled

2.041
 - Minor code optimisations

2.04
 - Added ability to create an SQL dump instead of the normal ranks.txt, which will still be uploadable
     via FTP. Set the outputFormat option to 2 for this output mode, or leave it as 1 for the default.
     Credit to gkl21 for the SQL dump capability.
 - Added outputFile setting to control the name of the output file. Default is ranks.txt.

2.03
 - Fixes to prevent syntax errors on players with ' in their name
 - ranks.txt is now updated in batches of 100 names to prevent the bot becoming locked up while processing
     all of the rank data.

2.02
 - Fixed another location where players with capital letters in their names lost some rank statistics

2.01
 - Fixed bug where players with capitals in their name didn't always get their stats recorded.

2.00
 - Rebuilt the plugin from scratch to remove old clunky code
 - Will no longer not record ranks if everyone leaves at the end of the game
 - Dropped support for older versions of BRenBot, will now only work on 1.51 or above
 - Added support for playernames with spaces in !rankignore / !rankallow
 - Gets results##.txt file contents from BRenBot's core instead of processing them itself
 - Added ability to record vehicle and building kills and repairs.
 - Added new rank points scoring system, and config options to control how the points are calculated
 - Changed limit on !top to 5 players both ingame and in IRC
 - Changed almost all ingame messages to be paged to the player using the command
 - !delRank supports names with spaces
 - Dropped support for old HTML output based on .tpl templates.

1.38
 - Support for updating through brLoader
 
1.37
 - Updated to be backwards compatible with 1.50

1.36
 - Updated to support BRenBot 1.51. Will NOT work on earlier versions

1.35
 - Fix to prevent players getting points when there is only one player ingame ( no-gameplay pending patch )

1.34
 - Fix linux compatibility

1.33
 - Fixed db query in !rankAllow
 - Fixed !top to show the correct ranking type, instead of always showing the players points
 - Replaced [PAC] with [BR]

1.32
 - Added rankMode config setting, to allow ranking by kills or k/d instead of score, for sniper servers
 - Updated rank.xml to be compatable with 1.43 build 20 and above

1.31
 - Fixed a bug in some commands where it would only return the first three names, instead of the first 5 as
     it should.
 - Fixed a bug where if the second name found was identical to the search string in !rank or !rankstats it
     would not recognise it.

1.3
 - Added the command !delRank, which allows you to delete all rank data for the specified player.

1.26
 - Fixed a bug where !rankMerge would not delete the data from the old name if it contained capital letters.
 - Corrected a slight error in the previous fix to similar player names being unable to return rank data.

1.25
 - Fixed a bug where if one players name is contained within another players name, and that name contains
     capital letters, it is impossible to get !rankstats for that player.
 - Fixed !rankstats to show the players actual name, instead of the name you searched for.
 - Fixed a bug where the wrong rank data was returned occasionally.
 - Updated !rankstats to work from ingame without a name specified, so you can get your own rankstats.

1.24
 - Fixed !top command not working from IRC properly following the changes in 1.23

1.23
 - Added support for !rankstats being used in-game
 - Added support for !top being used in-game, up to a maximum of 3 ranks shown
 - Removed the total ranked players message output from the !top command
 - Added the config value rankingMinScore so you can set how many points a player must have to be ranked
     for that game.

1.22
 - Fixed bug where player's after position 10 were not recognised by the Regex

1.21
 - Added some major debugging code to the plugin. It is disabled by default, but if you need to turn it
     on add the line <cvar namne="DEBUG" value="1"/> to rank.xml above the line </config>
 - Fixed a possible bug when updating player rank data which could cause the data to be lost.

1.2
 - Made some adjustments to how rank lookups work
 - Fixed a bug in !rankMerge which caused the rank's to not merge properly when there are capital letters
     in the player's name.
 - Fixed a bug where changing capital letters in your login would create two seperate rank records. This
     also fixes the error for playerjoin sirens.
 - Added the command !rankAllow
 - Modified !rankIgnore and !rankAllow to no longer be case sensitive

1.11
 - Fixed a bug where the bot tried to use FTP even when it is disabled in the config.

1.1a
 - Support for Allies / Soviet team names added

1.1
 - Removed a bit of unnessicary debugging output to the BRenBot window.
 - !top command can now be specified with no number, and will default to getting the top 3 players.
 - If the !top command is used with a number greater than 10, it will output the top 10.
 - Added config settings to the .xml file for enabling and disabling the rank message when joining.
 - Removed redundant event for playerleave.
 - Moved the sitePath variable to rank.xml, rankings.cfg is now redundant and can be deleted.
 - Removed several redundant functions to optimize code speed.
 - Made "" around variables on the <CDS-LOOP-TOTAL-PLAYERS> tag optional, instead of mandatory.
 - Removed redundant columns wScore, wKills and wDeaths from database, these are instead worked out when required.
 - Added the command !rankIgnore, which allows you to prevent specifc players from being ranked (EG rank whores).
 - Added the command !rankMerge, which allows ingame players to merge two sets of stats into one.
 - Made the top 3 player joined siren optional, and added a value in the ranks.xml file.
 - Added a new output type, ranks.txt, which can be used with the bundled PHP scripts to create a more useful
     ranks listing.
 - Added the ability to upload ranks.txt and/or index.htm via FTP automatically.

1.0
 - First Release

###############
Commands
###############

!rank [<name>/<rank>]
  Gets the name, rank and points for a user. If used ingame with no name or rank specified, it will show
  details for the player typing it, when used with a name it shows the details for that name, and when used
  with a rank it shows who is in that position. When specifiying it with a name you do not need to use the full name.


!rankIgnore <name>
  Adds the specified player to the rank ignore list. Players who are on this list will not get any ranking data
  updated when playing in the server, although any data that was there before they got ignored will not be deleted.


!rankMerge <name>
  An ingame command only, the player using it specifies another username to transfer their rank data to. If that
  username already has rank data, the two sets will be merged under the new name. After the merge the old name's
  rank data is deleted.


!rankstats <name>
Returns more details rank statistics for the specified player.


!top [<number>]
  Returns the top x ranked players, where x is the number specified. If no number is given it will return the top
  three. If <number> is greater than 10, it will just show the top 10.


!update
  Forces an update of the website files.


!delRank <playername>
  Deletes all rank data for the specified player.


###############
Config Settings
###############

showRankOnJoin
  Set this to 1 to have the plugin show a players rank in f2 chat when they join the game.

showRankOnJoinDelay
  Delay between player joining and showing the join message, if the above option is enabled.

sirenMinRank
  Minimum rank required for the high ranked player siren sound effect to be played. Set this
  to 0 to disable it.

rankingMinScore
  Minimum score ingame required for the players rank statistics to be updated for that game.
  Prevents average scores etc being lowered for games the player joined right at the end.

sitePath
  Path to the folder where the ranks.txt file will be created. If your webserver is on the
  same machine as BRenBot you can use this to place the ranks.txt straight into your website.

enableFTP
  Set this to 1 to enable uploading the ranks.txt file to an FTP server

ftpServer
  Set this to the address of your FTP server

ftpUsername
  Username for BRenBot to use when logging into the FTP server

ftpPassword
  Password for BRenBot to use when logging into the FTP server

ftpPath
  Path from the root folder of the FTP where BRenBot should upload the ranks.txt file.

rankMode
  Controls how players are ranked.
	1 = AOW, ranked by Score
	2 = Snipe, ranked by Kills
	3 = Snipe, ranked by K/D
	4 = Rank Points - See settings below

scorePerRankPoint
  Ingame score required to gain a single rank point.

killsPerRankPoint
  Kills required to gain a single rank point.

deathsPerMinusRankPoint
  Deaths required to lose a single rank point.

buildingKillsPerRankPoint
  Building kills required to gain a single rank point.

buildingRepairPerRankPoint
  Building repair points required to gain a single rank point.

vehicleKillsPerRankPoint
  Vehicle kills required to gain a single rank point.

vehicleRepairPerRankPoint
  Vehicle repair points required to gain a single rank point.