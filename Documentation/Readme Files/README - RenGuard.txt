RenGuard Server Side Client 1.03 Readme

Table of Contents

1.  Installing
2.  Configuration Files
3.  Usage
4.  Notes
5.  Changelog
6.  Credits

1. Installing

If you are using BRenBot, the RenGuard Server Side Client is already included.
You do not need to install it.

If you have downloaded the standalone SSC, you need to install it.

1. Extract the archive
2. Edit renguard.cfg
3. Win32: Make sure the renrem settings work. Without renrem, the SSC will not
work!  
   Linux: Make sure you have the wrapper installed
(http://www.brenbot.com/wrapper) and that the port is correct
4. Start renguard_ssc.exe (win32) or renguard_ssc (linux)

2. Configuration Files

There are two RenGuard specific configuration files. renguard.cfg and
ssc_ignore.txt.

renguard.cfg - see included renguard.cfg file for details
ssc_ignore.txt - Put users in there you wish to ignore.

To be able to be authenticated by RenGuard, you need to connect to your server
though the Internet. If you connect via your local network, RenGuard will not
be able to authenticate you (ie you need an external ip in player_info). If
this is the case, put your username(s) into ssc_ignore.txt. The SSC will
ignore these users, and let you join.

Note: This does only work when PureMode is disabled.

Set the cfg option notify to "page" if you want WOL pages instead of public
hostmessages.

Lots of additional configuration options have been added in RenGuard
SSC 1.03/BRenBot 1.36. 

See renguard.txt :-)
NOTE: If you do not like to RenGuard to kick all players that use no 
RenGuard, you can turn on "Half-RenGuard". To do that, turn on
halfrenguard = 1 in renguard.cfg

Using Half-RenGuard, non RG Users will be publically announced that they
are not using RenGuard, and they get an pamsg, explaining why they
should install RenGuard. This message is configurable.

Non-RG users may not use any !commands (except !help and !showmods), to encourage them
to install RenGuard.

Admins can use !forcetc to force a user to use RenGuard. Regular RenGuard
users have access to !forcetc too. If 3 RenGuard users decided to !forcetc
a suspected cheater, he or she will be forced to use RenGuard.

You can use !rgstats to view your local RenGuard acceptance rate 
(rg users vs non-rg users). If it is over >85%, you should consider
to upgrade too full-renguard mode, preventing any cheats on your server.

If you ban a user using !ban and RenGuard is enabled, it will automatically
ban by serial hash that was transmitted by RenGuard.



4. Notes

* RenGuard SSC automatically kicks user not connected to the Network.
* Setting pure mode will disallow any skin files and model files on your server.
This is meant for leagues. 
* It is recommended that you register for a Server MOTD - visit
http://www.renguard.com for more information.

5. Changelog

1.03 (20/10/2004)
Improved stability and added more cvars

1.02 (04/21/2004)
Fixed a crash issue


1.01 (04/14/2004)
Fixed problem that people get kicked by renguard when having renguard
Added notify option to cfg file


6. Credits

RenGuard SSC - mac and Blazer

Thanks to Scorpio9a and Silent_Kane for deciphering RenRem/FDSTALK protocol, and to Jeff T. Parsons aka bynari (Jeff.Parsons@Webgeeks.co.uk) for helping convert the deciphered renrem to Perl.


