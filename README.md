# Readme file for BRenBot 1.55

This file contains setup instructions, general troubleshooting information and information on how to
obtain support for BRenBot

This readme is considered to be correct at the time of writing. If you find any mistakes or would
like to suggest changes, please contact an active developer.

Readme file written by danpaul88, with several useful parts taken from the pre-1.50 readme file.


## Credits

BRenBot has been developed by;
Blazer
Mac
PackHunter
danpaul88

Thanks also go to the following for code contributions;
AmunRa
v00d00

BRenBot is Copyright 2003-2015 by Tiberian Technologies. All rights reserved.

Thanks to Gozy, Caveman, Hex, Fifaheld, cAmpa, trooprm02 and all the other official 1.43 & 1.51
testers for helping find all the bugs during testing.

Thanks to Scorpio9a and Silent_Kane for deciphering RenRem/FDSTALK protocol, and to Jeff T. Parsons
aka bynari (Jeff.Parsons@Webgeeks.co.uk) for helping convert the deciphered renrem to Perl.


## Setup Instructions

Setting up BRenBot is easy and quick to do if you follow these simple instructions. After installing
both the RenegadeFDS and BRenBot, you need to set up communication between them. This is done via
the RemoteAdmin* settings in the server.ini file.

Step 1.
Open your server.ini in RenegadeFDS/Server


Step 2.
Locate the following options and set them to the values given here

```
AllowRemoteAdmin = true
RemoteAdminPassword = yourpass
RemoteAdminIP = 127.0.0.1
RemoteAdminPort = 4949
```

Note: The lines with a ; on the front are NOT the actual options, and not where you put these
settings. It is recommended that you change the pw option to an 8 digit password of your choice.


Step 3.
Open your brenbot.cfg file in RenegadeFDS/Server/BRenBot


Step 4.
Locate the following options and set them to appropriate values

```
BotName = brenbot
IrcServer = irc.n00bstories.com
IrcPort = 6667
IrcAdminChannel = #brenbot
```

Set the BotName to something unique to your server (such as br_myclansrv), and choose the IRC server
and channel of your choice. The default channel is #brenbot on the n00bstories IRC server, but you
should change this to something unique to your server (such as #myclansrv).


Step 6.
Finally locate the two settings below and check their paths are correct. If you installed the FDS in
the default location these paths should be correct.

```
FDSLogFilePath = C:/Westwood/RenegadeFDS/Server/
FDSConfigFile = C:/Westwood/RenegadeFDS/Server/Data/svrcfg_cnc.ini
```


Basic setup is now complete and BRenBot has enough information to connect to your server and perform
all of its functions.


### IRC Dual Channel Mode

BRenBot has the ability to use two IRC channels simultaneously, an admin channel where all commands
can be used, and a public channel where a limited number of commands are available. The public
channel is disabled by default, to enable it simply type a channel name into the ircPublicChannel
option in brenbot.cfg.

Users in the public channel will see F2 chat and a limited amount of ingame information. You can
display more or less information to the public channel using the settings in brenbot.cfg


## Using the authorisation system

BRenBot includes a secure authorisation system to prevent GSA or Direct Connect users from stealing
your mods names, and getting moderator access. The auth system is always enabled, but only functions
to its maximum potential when the Moderators_Force_Auth option in brenbot.cfg is set to 1.

When a user joins the server with a registered name, BRenBot pages them asking for their password to
authorise them. If they are a moderator BRenBot will withold their moderator powers until they have
authorised themselves. If they do not do so within 60 seconds they will be kicked from the server.

If the Moderators_Force_Auth is enabled and a user joins the server with an unregistered moderator
name they will not get moderator powers. This means that unprotected names cannot be abused, but it
also means that all your moderators must protect their names before they get their moderator powers.


#### How to register a name
Registering a username on BRenBot is very easy. All you need to do is login to IRC, and
open a private chat window with BRenBot ( double click on the bots name in mIRC). Then
type !register <playername> <password> to register a name. All of your moderators should
do this themselves, so they can use a password they will not forget. From now on anyone
using that name must authorise themselves when they join.


#### How to authorise
There are several ways to authorise yourself in this version of BRenBot. If you are connected to the
FDS via XWIS/WOL you can page the bot from ingame by typing /page <serverlogin> !auth <password>,
replacing <serverlogin> with the login of the server you are on (EG: a00000001), and <password> with
the password you chose.

If this does not work for you, you can join the IRC channel with the bot in, and type !auth <name>
to authorise yourself, but this requires you to have sufficient status on the IRC channel. If you
cannot use the !auth command open a PM window with the bot and type !auth <name> <password> to
authorise yourself.


## Using the commands.xml file

The commands.xml file in BRenBot gives you total control over who can use which commands, and even
lets you disable commands completely. The top part of the file dealing with permissions is beyond
the scope of this document, and will not be dealt with here.

Plugins will also include similar settings for their own commands in their plugin.xml file, these
work in the same way as those in commands.xml. Note that plugin commands can override built in
commands. If multiple plugins define the same command and both are enabled it is indeterminate which
plugin will actually be activated when using the command.

Let's look at an example command in the commands.xml file;

```
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
```

At first this might look very confusing, so lets break it down a bit. The first line identifies
which command this setting is for, and should NEVER be changed.

The second line set's the permission level for this command. Default permissions are between 1
(everyone) and 5 (admin only). This command is available to all users.

The next two lines are the syntax value and help value, which are used by the !help command, and
sometimes by the command itself.

The next line is the enabled line, which controls if the command is available or not. Setting this
to 0 will prevent the command being used at all.

The next three lines specify where the command can be used. In this case it can be used from both
irc channels and ingame. Deleting one of these lines will stop it being used in that location.

The remaining lines define aliases for the command, so typing either of those will do the same as if
you typed the full name given on the top line.

The last line marks the end of the command settings and should NEVER be changed.


## Configuration Files

 - brenbot.cfg
Contains the core settings for BRenBot. The comments in the file explain what each settings does.

 - autoannounce.cfg
Contains the autoannounce messages for BRenBot. Each message should be on a single line.

 - recs.txt
Part of the recommendations system, if the recommend module is enabled BRenBot sends a message from
this file when players join the game. Each message has an upper and lower recommendations limit for
when it is shown.

 - moderators.cfg
Replaces the masters.brf and admins.brf files in older versions of BRenBot. Contains a list of all
Administators, Moderators and Half Moderators on your server.

 - messages.cfg
Used by the !postmsg command and the !rules command. The first line of this file is your server
rules, and is shown when !rules is used. Each line can be shown using !postmsg <linenumber>.

 - mapsettings.xml
Contains map specific settings for various things like vehicle and mine limits. Plugins can also use
settings from this file to configure map specific behaviour - an example is the donate plugin which
allows the time limit before donations are permitted to be set via this file.

The `<default>` section contains the settings that are used when no map-specific settings are defined
for the current map.

Some functions of this file only work when the map_settings module is enabled.


## Using the GameSpy broadcaster

Note: As of BRenBot 1.54 the GSA broadcasting system has been moved into the gamespy plugin, which
is included by default with BRenBot.

The plugin features an updated implementation of GSA protocol system to that which is included in
the current version of WOLSpy and the original (L)FDS.

Before enabling GSA broadcasting you should configure the plugin by editing the plugins/gamespy.pm
file and setting appropriate options - at minimum you need to configure the query_port setting to
the port number you want GSA to listen on. Ensure this port is open in your firewall.

Once the plugin is configured simply load the plugin with !plugin_load gamespy.

Note: If you want to configure the bot to reply to GSA queries without broadcasting to any master
servers you can remove all the entries from the master_servers setting.


# Troubleshooting

Some common problems people have with BRenBot, if you can't find the answer here please see the
Technical Support section below this one.


Problem: The bot seems to work, but no messages showup ingame and some commands do not work

Resolution: Usually this is caused by incorrect remote admin settings. Ensure that AllowRemoteAdmin
in server.ini is set to true and that the RemoteAdminPassword is set to an 8 character string. See
the setup section for the more information about configuring remote admin settings. BRenBot will
usually display a warning in its console window if it detects invalid remote admin settings.

This can also occur when two or more FDS installations on the machine are configured to use the same
RemoteAdminPort setting.


Problem: BRenBot closes as soon as it starts to load, or closes for no reason randomly

Resolution: It's probably closing due to a fatal error condition. To see the error message before it
closes run the bot in command prompt. To do this go to Start->Run and enter the word cmd, and then
hit enter.

Now type in cd C:\Westwood\RenegadeFDS\Server\BRenBot\, changing this to match the path to your
brenbot folder, and hit enter. Now type in brenbot.exe and hit enter, and the bot should load up.
When BRenBot closes you should see the reason why.


Problem: BRenBot opens a blank console window and hangs forever

Resolution: This is often caused by a corrupted PAR cache and can be fixed by deleting the cache
folder. This is located in the temporary files folder, to locate it type %temp% into Windows
Explorer and look for a folder in there named par-<yourusername>. When you find this folder delete
it and then try to run BRenBot again.


# Technical Support

For technical support please visit www.renegadeforums.com and post your query in the Technical
Support -> Other subforum.

To report a bug or request a new feature please create a new issue in the BRenBot git repository at
https://gitlab.com/danpaul88/brenbot/issues or create a new card on our Trello board at
https://trello.com/b/dlqadUmV/brenbot


# Source

BRenBot is an open source product and you are free to customise the bot to meet your own needs. If
you would like to contribute bug fixes or new features to the main repository please submit a merge
request and it will be reviewed at the earliest opportunity.

The official BRenBot git repository is available at https://gitlab.com/danpaul88/brenbot


# Getting plugins

The latest TT supplied plugins are available directly from the BRenBot git repository, which you can
find at https://gitlab.com/danpaul88/brenbot/tree/master/Plugins

Additionally several plugins are available from the BRenBot website, http://new.brenbot.com, however
in many cases these are outdated and may not function correctly on the latest version of BRenBot