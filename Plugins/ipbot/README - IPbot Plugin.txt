IPbot Plugin
Version 1.142
Daniel Paul (danpaul88)
danpaul88@yahoo.co.uk


The IPbot sends the ip's of all players on your server to the main IPDB server, and
allows you to do searches on the database. Useful for banning users on all of their
nicknames / ips, and checking what other names players go by.

Please contact either danpaul88 or Nightma12 for a username and password to connect
to the IPDB server.

If you want to ask any questions, request new features or report bugs please post on
the Renegade Public forums (www.renegadeforums.com) in the Technical Support -> Other
area, or email me.


###############
Installation
###############

Extract the plugins folder to your BRenBot folder.


###############
Changelog
###############

1.142
 - Added missing protocol version submit command
 - Updated to comply with updated plugin system in BRenBot 1.54
 - Removed duplicate connect to server code, optimised connect process

1.141
 - Added missing code to subscribe to nick spoofer notifications

1.14
 - Updated protocol support to version 1.3
 - Added configuration option enableNickSpooferWarnings
 - Corrected DNS entry used when reconnecting after a connection loss

1.133
 - Fixed bug where client ID was not sent after a reconnection

1.132
 - Added support for pinging the IPDB server to prevent connections from being killed due
     to being idle
 - Replaced references to IPBot with IPDB
 - Changed DNS to ipdb.tsulutions.com
 - Added ability to split results of a common nick search over multiple lines, to cope with
     updates to the IPDB server that allow more results to be sent
 - Added support for 601 protocol message

1.131
 - Fixed logging in on reconnection (would only login on first connection previously)
 - Reduced reconnect delay to 5 minutes
 - Decreased scan players frequency from every 5 minutes to every 10 minutes

1.13
 - Added code to support new login requirement in IPDB 1.2

1.122
 - Fixed bug where queries would queue up indefinatly when the server is offline and then
     all be sent at once, resulting in a large network traffic surge.
 - Added !commonNickSearch command, which searches for any nicknames that have been used
     on the ip address(es) used by a particular player.

1.121
 - Fixed a bug where searches with no results would not show any message in IRC

1.12
 - Modified scan_players to correct a bug where player names were not being sent, and
     adjusted it to run every 5 minutes instead of every 2.
 - Results of searches will now be sent to the person making the request via a NOTICE
     instead of displayed in normal IRC chat

1.11
 - Removed some remaining references to the old IRC connection
 - Modified behaviour of scan_players to report entire playerlist at once instead of
     processing in groups of three, which was only in place due to IRC message queuing

1.1
 - Dropped support for versions of BRenBot older than 1.51
 - Updated to use new ipbot instruction set
 - Connection to the IPBot master server is now done through TCP instead of using IRC

1.02
 - Support for updating through brLoader

1.01
 - Updated to be backwards compatible with 1.50

1.0
 - First Release
 - Updated to be compatible with BRenBot 1.51

0.80
 - First Beta Release


###############
Commands
###############

!nicksearch <nick>
Searches the ipbot database for any nicknames matching or containing your search string.
If found it will show up to 10 results, along with their known ip addresses.

!ipsearch <ip>
Searches the ipbot databases for any matches on the specified ip address. If found it
will show up to 10 results, along with the nicknames that have been seen using them.

!ipbot_stats
Shows statistics about the ipbot.

!commonnicksearch <nick>
Searches for all other nicknames that have been used on the same IPs as nick has used.
Requires an exact (case insenstive) nickname.