Jukebox Plugin
Version 1.00
Author: danpaul88


Randomly plays tracks from always.dat for players with scripts.dll 2.0 or higher.

Tracks can be enabled or disabled via the config option in jukebox.xml with the same
name as the track.

If you want to ask any questions, request new features or report bugs please post on the Renegade Public forums (www.renegadeforums.com) in the Technical Support -> Other area, or email me.


###############
Installation
###############

Extract the plugins folder to your BRenBot folder.


###############
Changelog
###############


1.0
 - First Release


###############
Commands
###############

!settrack <name>
Skips the currently playing track and plays the specified track, if found. Name can be a partial
namd, the first matching track will the played.

!nexttrack
Skips the current track and plays a new one at random.

!music <on/off>
Enables or disables music for the player using the command.