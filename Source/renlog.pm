#!/usr/bin/perl -w

package renlog;
use strict;

use POE;
use POE qw/Wheel::FollowTail/;

use modules;
use brconfig;
use commands;
use brdatabase;
use brAuth;

our @invitelist;		# List of players waiting for an invite
my %joiners;			# List of players who have joined since the last player info
our $used_slots			= 0;
our $renew_ssgm			= 0;

my $logPlayerInfo 		= 0;	# Used to parse player_info commands
my $readGameDefs		= 0;	# Used to indicate when we are recieving a list of SSGM4.0 gamedefs


# Subroutine to initialize renlog file tail session, if appropriate (EG: Not using SSGM 4.0 or higher)
sub init
{
	# If we are using SSGM 4.0 or higher then we do not need to tail renlog as the data is available
	# through the SSGM Log Server
	if ( $brconfig::ssgm_version >= 4 )
	{
		return;
	}


	# Create renlog file tail session
	POE::Session->create
	(	inline_states =>
		{
			_start => sub
			{
				# Call renew wheel, which does everything we need to do
				$_[KERNEL]->yield( 'renew_wheel' );

				# Set alias
				$_[KERNEL]->alias_set( 'renlog_tail' );
			},

			renew_wheel => sub					# Resets the wheel
			{
				# Get name of logfile (Either Wind0ze or Linux mode)
				my $name;
				if ( $brconfig::config_botmode eq "LFDS" )
					{ $name = $brconfig::config_fdslogpath . modules::get_linux_date_time( "renlog_MM-DD-YYYY.txt" ); }
				else
					{ $name = $brconfig::config_fdslogpath . modules::get_date_time( "renlog_MM-DD-YYYY.txt" ); }


				# Check if the file exists, if it does then tail it
				modules::console_output ( "Looking for RenLog at $name...", 1 );
				if ( -e $name )
				{
					modules::console_output ( 'Found', 3 );

					$_[HEAP]->{'wheel'} = POE::Wheel::FollowTail->new (
						Filename	=> $name,
						InputEvent => 'got_line',
						ErrorEvent => 'got_error',
						SeekBack	=> 1 );

					$_[HEAP]->{'first'} = 0;
				}
				else
				{
					modules::console_output ( 'Not found! Will try again in 2 minutes', 3 );
					$_[KERNEL]->alarm( 'renew_wheel' => (int( time() ) + 120) );
				}
			},

			got_line    => sub { parse_line($_[ARG0]) },	# InputEvent
			got_error	=> sub { warn "$_[ARG0]\n" }		# ErrorEvent
		}
	);
}





# Parses a single line of input from player_info
#
#	Id  Name			Score Side	Ping	Address				Kbits/s Time
#	[00:00:10]	1 ezkills15	  674	NOD	133	68.228.199.23;3735	56	  000.19.44
#
sub parsePlayerInfoInput
{
	my $playerDataLine = shift;
	if ( $playerDataLine =~ m/(\d+)\s(.+?)\s+(-{0,1}\d+)\s+(GDI|NOD|Sov|All)\s+(\d+)\s+(\d+\.\d+\.\d+\.\d+)[\;\d]*\s+(\d+)\s+(\d+\.\d+\.\d+)/i )
	{
		playerData::updatePlayerData ( $1, $2, $3, $4, $5, $6, $7, $8 );
		check_playername ( $1, $2, $6 );

		my $lower_case_name = lc( $2 );

		# If they have just joined the game run their joinstuff, which does ban
		# checking, auth checking etc
		if ( exists $joiners{$lower_case_name} )
		{
			delete $joiners{$lower_case_name};
			main::joinstuff( $2 );
		}
	}
}


# Checks all players in the playerlist to see if its been more than 40 seconds
# since we saw them. If it is they must have left the game, so delete their
# data
sub checkPlayerlist
{
	my %playerlist = playerData::getPlayerList();
	while ( my ( $id, $player ) = each ( %playerlist ) )
	{
		if ( $player->{'lastUpdated'} < (time() - 40) )
		{
			modules::console_output ( "Deleting data for player $player->{name} (id $player->{id})..." );
			playerData::clearPlayerData ( $player->{'id'} );
		}

		if ( $player->{'banned'} )
		{
			modules::kick_player ( $player->{'id'}, 'BRenBot', 'Player has been banned from the server' );
		}
	}
}


sub check_playername
{
	# Checks every name in the playerlist that has less than 1 char.
	# The LFDS can't process any name with non-ascii chars in it (accents, umlauts) and displays
	# an empty list. We're kicking them by id.
#		RenRem::RenRemCMD ("kick $player{id}") if ($player{'name'} =~ m/[\001\002\037]/);
#		RenRem::RenRemCMD ("kick $player{id}") if (length ($player{'name'}) > 30);
	my $id		= shift;
	my $name	= shift;
	my $ip		= shift;

	# Check for attempted nickname exploits
	if ( $name =~ /(:|\!|\&|%s)/i )
	{
		# NB: DO NOT USE modules::kick_player as it may fail to remove players with illegal nicknames
		RenRem::RenRemCMD ( "kick $id" );
		RenRem::RenRemCMD ( "msg [BR] $name has been kicked by BRenBot for having disallowed characters in their name" );
		brIRC::ircmsg( "Removed a player with disallowed characters in their name. (ip: $ip)", "A" );
	}
	elsif ( length($name) <= 1 || $name =~ /[\001\002\037]/ )
	{
		# NB: DO NOT USE modules::kick_player as it may fail to remove players with illegal nicknames
		RenRem::RenRemCMD( "kick $id" );
		RenRem::RenRemCMD( "msg [BR] Playername with non-ascii characters detected. Do not use umlauts or accents. Kicking Player!" );
		brIRC::ircmsg( "Removed a player with non-ascii characters in their name. (ip: $ip)", "A" );
	}
	elsif (length($name) >= 30)
	{
		# NB: DO NOT USE modules::kick_player as it may fail to remove players with illegal nicknames
		RenRem::RenRemCMD( "kick $id" );
		brIRC::ircmsg( "Removed a player with excessively long name. (ip: $ip)", "A" );
	}
	elsif ( $name =~ /\\/ )
	{
		# NB: DO NOT USE modules::kick_player as it may fail to remove players with illegal nicknames
		RenRem::RenRemCMD( "msg [BR] $name, you have backslashes in your name. Please remove them, and reconnect." );
		RenRem::RenRemCMDtimed( "kick $id", 1 );
		brIRC::ircmsg( "Removed a player with backslashes in their name. (ip: $ip)", "A" );
	}
}


# Moved this to a seperate sub on it's own to keep things better organised
sub fakeUser
{
	my $fake = shift;				# Fake's username
	my $fakedUserID = shift;		# This is the ID of the player whose name was stolen!

	if ( !$fakedUserID )
	{
		# This processes players with bad usernames
		my ( $result, %player ) = playerData::getPlayerData ( $fake );
		if ( $result == 1 )
		{
			# NB: DO NOT USE modules::kick_player as it may remove the incorrect player
			RenRem::RenRemCMD( "msg [BR] $player{name} is being kicked by BRenBot for: FAKE NICK" );
			RenRem::RenRemCMD( "kick $player{id}" );
		}
	}

	else
	{
		# This processes fakes using an existing players username
		my %playerlist = playerData::getPlayerList();
		while ( my ( $id, $player ) = each ( %playerlist ) )
		{
			if ( $player->{'name'} eq $fake && $player->{'id'} != $fakedUserID )
			{
				# NB: DO NOT USE modules::kick_player as it may fail to remove players with illegal nicknames
				RenRem::RenRemCMD( "msg [BR] $player->{name} is being kicked by BRenBot for: Impersonating someone else" );
				RenRem::RenRemCMD( "kick $player->{id}");
			}
		}
	}
}


# Checks the banlist to see if the specified player is banned
sub check_banlist
{
#	print "DEBUG: Checkbanlist\n";
	my $name = shift;

	my ( $result, $reason, $banner, $timestamp ) = modules::is_banned( $name );
	if ( $result && playerData::getKeyValue ( $name, "banned" ) != 1 )
	{
		my ( $result2, %player ) = playerData::getPlayerData ( $name );
		if ( $result2 == 1 )
		{
			RenRem::RenRemCMD( "msg [BR] $player{name} has been BANNED on $timestamp by $banner for: $reason" );

			modules::console_output ( "player_id $player{id} is BANNED" );

			if ( modules::get_module("bhs") )
				{ RenRem::RenRemCMD( "pamsg $player{id} You have been BANNED on $timestamp by $banner for: $reason" ); }

			# If we are using SSGM 4.0 then we need to add this ban to it's bans list
			if ( $brconfig::ssgm_version >= 4 )
			{
				RenRem::RenRemCMD ( 'ban '.$player{'id'}." Banned on $timestamp by $banner for $reason" );
			}

			# Otherwise remove them from the server the old fashioned way
			else
			{
				RenRem::RenRemCMD ( 'kick '.$player{'id'} );
			}
			playerData::setKeyValue ( $player{'id'}, "banned", 1 );
			return 1;
		}
	}

	return 0;
}



# Processes chat messages, and outputs them to IRC
#
# Chat Messages Look like this: [23:58:36] flawliss9: BAD LAG
# Team Messages Look like this: [23:58:36] [Team]: flawliss9: BAD LAG
#
sub ChatMSG
{
	my $line = shift;
	my $teamMessage = 0;

	# Extract chat name and message text, colorize it.
  # 10 Sept 2012: Added extra protection by explicitly disallowing : in the username of the player
  # sending the chat message to help prevent abuse of the ambiguous logging format. Also ignoring
  # any names with spaces in since we are banning those now (see check_playername)
	#if ( $line =~ m~\[(..):(..):(..)\]\s+(.+?):\s(.+)~ )
	if ( $line =~ m/^\[(..):(..):(..)\]\s(\[Team\]\s)?([^%s:]+?):\s(.+)/i )
	{
		# Prevent bugs/command abuse caused by players with : in their name
		if ( "$5$6" =~ m/^Player\s.+\s(joined|left)\sthe\sgame$/
		 || "$5$6" =~ m/^.+:\s!\s.+\swas\skicked$/ )
		{ return; }

		#print "1 is $1\n	2 is $2\n	3 is $3\n	4 is $4\n	5 is $5\n	6 is $6\n	7 is $7\n";
		my $playername = $5;
		my $playermsg  = $6;

    # \todo
    #   What is the purpose of this? The regex should parse it properly in the first place? Might
    #   be suitable for removing at some point...
		if ($playermsg =~ m~\[(..):(..):(..)\]\s+(.+?):\s(.+)~)
		{
			$playermsg  = $5;
			$playername = $4;
		}

		# Check if the message is coming from linux bhs_tail. If not, drop it, because we dont want duplicate chat messages
		next if ( (modules::get_module("bhs") ) && ($brconfig::config_botmode eq "LFDS") );


		# Check if this is a team message
		if ( $4 and $4 eq "[Team] " )
      { $teamMessage = 1; }

		if ( $5 ne "Host" && $5 !~ m/^\[Page\]/i )
		{
			# Get data for person who chatted
			my ( $result, %player ) = playerData::getPlayerData ( $playername );
			if ( $result == 1 )
			{
				# Format mod and admin names
				my $pname = modules::parseModName ( $playername, 1 );

				# Work out the colour for the message
				my $colour = ( $player{'side'} eq "GDI" || $player{'side'} eq "All" )
					? ( $main::currentMod eq "APB" ) ? "12" : "08"
					: "04";


				# F2 chat
				if ( $teamMessage == 0 )
				{
					brIRC::ircmsg( "$colour$pname: $playermsg" );
				}

				# F3 chat, if teammessages is enabled
				elsif ( $teamMessage && modules::get_module( "teammessages" ) )
				{
					brIRC::ircmsg( "06\[Team\] $colour$pname: $playermsg", "A" );
					if ( $brconfig::irc_showTeamMessages_PublicChan == 1 )
						{ brIRC::ircmsg( "06\[Team\] $colour$pname: $playermsg", "P" ); }
				}


				# Run plugins for public chat messages
				my @plugins = plugin::get_plugin_event("text");
				my %args;

				$args{id}			= $player{'id'};
				$args{nick}			= $playername;
				$args{nicktype}		= 0;
				$args{message}		= $playermsg;
				$args{messagetype}	= ( $teamMessage ) ? "team" : "public";
				$args{team}			= $player{'side'};

				foreach (@plugins)
				{
					my $plugin = $_;
					my $alias  = "plugin_" . $plugin;

					$main::poe_kernel->post($alias => "text" => \%args);
				}
			}
		}
	}
} # End of ChatMSG sub



sub add_invite
{
	my $name = shift;
	my $timestamp = time();
	my %invhash = (
					name => $name,
					timestamp => $timestamp,
				  );

	push (@invitelist, \%invhash);
	brIRC::ircmsg( "$name added to invite list." );
	RenRem::RenRemCMD( "page $name You will be auto-invited when a slot opens (moderators first)" );
}

sub del_invite
{
	my $name = shift;
	my $counter=0;
	foreach (@invitelist)
	{
 		my %hash=%$_;
 		if ( $hash{'name'} eq $name )
 		{
			splice(@invitelist,$counter,1); #remove them from array and shrink the array
			brIRC::ircmsg( "$name removed from the invite list." );
			return; # We found them, no need to iterate through the rest of the array.
		}
	$counter++;
	}
}

sub do_invite
{
	my $name=shift;
#	print "DEBUG: DO-INVITE: $name\n";
	RenRem::RenRemCMD("page $name <WWINVITE>");
	brIRC::ircmsg( "Sent $name an invite page." );
}

sub clean_invite
{
	foreach (@invitelist)
	{
		my %hash=%$_;
 		my $timestamp=$hash{'timestamp'};
 		my $name=$hash{'name'};
 		if (time() >= ($timestamp+900))
 		{ #see if their invitation (15 minutes) has expired
 			#brIRC::ircmsg( "Found old invitation for $name" );
			del_invite($name); # Delete them
			return;
		}
	}
}

sub check_invite
{
	my $name = shift;
#	print "DEBUG-checkinvite...\n";
	foreach (@invitelist) {
 	my %hash=%$_;
		if ( $hash{'name'} eq $name ) { # See if they are on invite list
#			print "DEBUG-Checkinvite: found $name on the list\n";
			return($name); # Return the name found
		}
	}

	return '';
}

sub mass_invite
{
	if ( serverStatus::getCurrentPlayers() < serverStatus::getMaxPlayers() )
	{
#		brIRC::ircmsg( "[BR] There are playing positions available, inviting anyone queued...");
		foreach ( @invitelist )
		{
 			my %hash=%$_;
# 			print "DEBUG: MASS-INVITE: $hash{'name'}\n";
 			do_invite($hash{'name'});
		}
	}
}

sub ParseLogInput
{
	my $rawline = shift;	# Keep this in a seperate variable for plugins etc
	my $line = $rawline;
	my $time = "";
	
	# Strip timestamp from input
	if ( $line =~ m/^\[(\d\d:\d\d:\d\d)\]\s?(.+)\r?\n?/i )
	{
		$time = $1;
		$line = $2;
	}
	
	#modules::console_output ( "[Renlog] DEBUG: Parsing input ==>$line<==\n" );

	# Start of game defs?
	if ( $line =~ m/Available game definitions:/ )
	{
		#modules::console_output ( "[Renlog] DEBUG: Start of map defs.\n )";
		$readGameDefs = 1;
		@brconfig::installedMaps = ();
	}
	elsif ( $readGameDefs == 1 )
	{
		if ($line eq " ")
		{
			#modules::console_output ( "[Renlog] DEBUG: End of map defs.\n )";
			$readGameDefs = 0;
		}
		else
		{
			#modules::console_output ( "[Renlog] DEBUG: Got map $line\n )";
			push (@brconfig::installed_maps, $line);
		}
	}

	# Skip level loading messages ([00:52:01] Load 0% complete[00:52:01] Load 0% complete....)
	elsif ( $line =~ m/Load \d+\% Complete/i )
	{}


	else
	{
		# Reply from mapnum command
		if ( $line =~ m/The Current Map Number is (\d+)/i )
		{
			serverStatus::updateMapNum ( $1 );
		}

		# Start of the reply from the game_info command
		if ($line =~ m/(.+?) mode active/g)
		{
			serverStatus::updateMode ( $1 );
		}

		if ( $line =~ /Map : (.+)/ )
		{
			serverStatus::updateMap ( $1 );
		}

		if ($line =~ /Time : (.+)/)
		{
			serverStatus::updateTimeRemaining ( $1 );
		}

		if ($line =~ /Fps : (.+)/)
		{
			serverStatus::updateSFPS ( $1 );
		}

		if ($line =~ /(GDI|All) : (.+?)\/(.+?) players\s+ (.+?) points/)
		{
			if ( $1 eq "All" ) { $main::currentMod = 'APB'; }
			serverStatus::updateStatus_GDI ( $2, $4, $3 );
		}

		if ($line =~ /(NOD|Sov) : (.+?)\/(.+?) players\s+ (.+?) points/)
		{
			serverStatus::updateStatus_Nod ( $2, $4, $3 );
		}

		$line =~ s/^\[\d\d:\d\d:\d\d\]//g; # do away with timestamps

		# First line of output from player_info command
		if ( $line =~ /Id\s+Name/ )
			{ $logPlayerInfo = 1; }

		if ( $line =~ "No players" )
			{ $logPlayerInfo = 0; }

		# Last line of output from player_info command
		if ($line =~ "Total current bandwidth")
		{
			$logPlayerInfo = 0;
			checkPlayerlist();
		}

		# Player data line from a player_info command
		if ( $logPlayerInfo )
			{ parsePlayerInfoInput($line); }



		$line =~ s/	/ /g;	# repace TABS with a space
		$line =~ s/^ //;	#eat leading spaces

		## BRINVITE
		#[21:32:34] [Page] n00bsvr01: (Blazer@IRC): test
		if ($brconfig::config_botmode eq "WIN32" and $line =~ /\[Page\] (.*): (letmein|WWDECLINE)/i)
		{
			handleInvite($1,$2);
		}

		if ($line =~ m/\[Page\]\s(.+?):\s\!auth\s(.*)/g)
		{
			my $pager = $1;
			my $pass  = $2;
			
			if ( !$pass )
				{ RenRem::RenRemCMD( "page $pager [BR] Usage: !auth <pass>" ); }
			
			else
			{
				my $authResult = brAuth::AuthenticateByPassword($pager,$pass);
				if ( $authResult == 1 )
				{
					RenRem::RenRemCMD("page $pager [BR] Authentication was successful!");
					brIRC::ircmsg( "[BR] Authentication for $pager was successful.", "A" );
				}
				elsif ( $authResult == 0 )
				{
					RenRem::RenRemCMD( "page $pager [BR] Wrong password!" );
					brIRC::ircmsg( "[BR] $pager gave an invalid password.", "A" );
				}
				elsif ( $authResult == 2 )
				{
					RenRem::RenRemCMD( "page $pager [BR] You are already authenticated." );
				}
				elsif ( $authResult == 3 )
				{
					RenRem::RenRemCMD( "page $pager [BR] Your nickname is not registered. Register it first." );
				}
				elsif ( $authResult == 4 )
				{
					brIRC::ircmsg( "9[Page] $pager tried to !auth from outside the game!", "A" );
					RenRem::RenRemCMD( "page $pager [BR] $pager your auth-exploit has been logged and will be reviewed." );
				}
			}

			$line = "";
		}

		if ( $line =~ s/\[Page\]/9\[Page\]/g )
		{
			if ( $line !~ /WWDECLINE/ )		# Skip WWDECLINE messages, these are processed elsewhere
			{
				# Highlight Pages
				brIRC::ircmsg( "$line", "A" );
			}
		}


		if ( $line =~ /^(\[Team\]\s|)(.+):\s(\!.+)$/i )
		{
			my $playername	= $2;
			my $playermsg	= $3;

			if ( $playername =~ /^9\[Page\]\s(.+)/i )
			{
				RenRem::RenRemCMD( "page $1 [BR] Paging commands is NOT allowed!" );
				brIRC::ircmsg ( "9Page Sent to $1 --> [BR] Paging commands is NOT allowed!", "A" );
			}
			else
			{
				# Saw a !command
				# if bhs module is enabled, and its tailing the bhs_renlog logfile
				# ignore this! (linux only)
				if ( (modules::get_module("bhs") ) && ($brconfig::config_botmode eq "LFDS") )
				{
					next;
				}

				# print "DEBUG:Detected a command by $playername.  Command is $1 and args are $2\n";
				# if (ValidCMD($playername,$1,$2)) { #See if they are allowed to execute said command }
				# print "DEBUG:ValidCMD passed...calling ParseArg($playermsg)\n";
				if ( ($playermsg !~ m/^\!set (.+?) (.+)/i) && ($playermsg !~ m/^!msg/) )
				{
					if ( $playername ne 'Host' )
					{
						# do not allow !set module on/off inside the game
						# Also ignore commands from host
						eval { commands::parsearg($playermsg, $playername, "N") };
						modules::display_error($@) if $@;
					}
				}
			}
		}

		if ($line =~ m/Now Playing (.+)/i)
		{# Soundtrack player
			my $song = $1;
			my $game = $2;
			brIRC::ircmsg( "9[Soundtrack Player] Now Playing $1" );
		}


		if ($line =~ m/Player (.+?) left the game/)
		{
			# Player left, need to update Player Array...
			brIRC::ircmsg( "11$line" );

			my ( $result, %player ) = playerData::getPlayerData ( $1 );
			if ( $result != 1 )
			{
				$player{'name'} = $1;
			}

			my @plugins = plugin::get_plugin_event( "playerleave" );
			my %args;

			$args{'id'} = $player{'id'};
			$args{'nick'} = $player{'name'};
			$args{'name'} = $player{'name'};
			$args{'ip'} = $player{'ip'};

			foreach (@plugins)
			{
				my $plugin = $_;
				my $alias = "plugin_" . $plugin;
				$main::poe_kernel->post($alias => "playerleave" => \%args);
			}

			$#plugins = -1;

			$player{'name'} =~ s/'/''/g;

			clean_invite; # BRINVITE
			mass_invite;
			RenRem::RenRemCMD( "game_info" );
			RenRem::RenRemCMD( "player_info" );

			# Remove all the data we are storing about them
			playerData::clearPlayerData ( $player{'id'} );
		}

		# A player joined the game
		if ( $line =~ m/^Player (.*?) joined the game$/ )
		{
			my $joiner = $1;

			$joiners{lc($joiner)} = 1;
			brIRC::ircmsg( "11$line" );

			# Check if a player with that name is already ingame
			my $tmp_nick = $joiner;
			$tmp_nick =~ s/\s+$//g; # remove all trailing spaces

			my ( $result, %player ) = playerData::getPlayerData( $tmp_nick, 1 );
			if ( $result == 1 )
			{
				# If !pi picked them up before we did let them off (2 seconds max)
				if ( ( time() - $player{'joinTime'} ) >= 3 )		# Ingame for 3 seconds or more
				{
					# Schedule the player to be kicked in 2 seconds (needs player_info to be updated FIRST)
					POE::Session->create
					( inline_states =>
						{
							_start => sub
							{
								$_[HEAP]->{next_alarm_time} = int( time() ) + 2;
								$_[HEAP]->{name} = $tmp_nick;
								$_[HEAP]->{id} = $player{id};
								$_[KERNEL]->alarm( fakeUser => $_[HEAP]->{next_alarm_time} );
							},
							fakeUser => sub
								{ fakeUser ( $_[HEAP]->{name}, $_[HEAP]->{id} ); }
						}
					);
				}
			}

			$joiner =~ s/'/''/g;

			# Check if they had an invitation, if they did remove it
			if ($brconfig::config_botmode eq "WIN32")
			{
				if ( check_invite($joiner) eq $joiner )
				{
					brIRC::ircmsg( "[BR] $joiner had an invitation, tearing it up." );
					del_invite( $joiner );
				}

				clean_invite; #check for old invitations
			}

			# Check if their name is all spaces
			elsif ( $joiner =~ m/[\s+]$/ )
			{
				# Schedule the player to be kicked in 2 seconds (needs player_info to be updated FIRST)
				POE::Session->create
				( inline_states =>
					{
						_start => sub
						{
							$_[HEAP]->{next_alarm_time} = int( time() ) + 2;
							$_[HEAP]->{name} = $joiner;
							$_[KERNEL]->alarm( fakeUser => $_[HEAP]->{next_alarm_time} );
						},
						fakeUser => sub
							{ fakeUser ( $_[HEAP]->{name} ); }
					}
				);
			}

			# Update game status
			RenRem::RenRemCMD( "player_info" );
			RenRem::RenRemCMD( "game_info" );
      
		} # end of joined the game



		# A player has switched teams
		if ( $line =~ m/^Host: (.+?) changed teams.$/ )
		{
			# When bhs and linux mode, skip this
			if ( (modules::get_module("bhs") ) && ($brconfig::config_botmode eq "LFDS") )
			{
				next;
			}

			$line="11$line";
			brIRC::ircmsg( "$line" );

			# Mark the player as having changed teams
			playerData::setKeyValue ( $1, "changedTeam", 1 );

			# Update game data
			RenRem::RenRemCMD( "game_info" );
			RenRem::RenRemCMD( "player_info" );
		}

		if ( $line =~ "/^Level loaded OK$/" )
		{
			# New Level has reloaded, need to update Player Array...

			brIRC::ircmsg( "9$line", "A" );
			brconfig::readServerSettings();		# Re-read the server settings

			# Apply map settings
			modules::applyMapSettings ( serverStatus::getMap(), 1 );

			my @plugins = plugin::get_plugin_event( "mapload" );

			my %args;
			$args{'map'} = serverStatus::getMap();

			foreach ( @plugins )
			{
				my $plugin = $_;
				my $alias = "plugin_" . $plugin;
				$main::poe_kernel->post($alias => "mapload" => \%args);
			}

			# Process autobalance (if it is enabled)
			modules::do_autobalance();

			# Update game information
			RenRem::RenRemCMD( "game_info" );
			RenRem::RenRemCMD( "player_info" );
		}

		# Handle any lines which just get thrown out to the IRC
		if ( $line =~ /^\w+ not found$/
			|| $line =~ /^Logging on....$/
			|| $line =~ /^Logging onto .+ Server$/
			|| $line =~ /^Failed to log in$/
			|| $line =~ /^Creating game channel$/
			|| $line =~ /^Channel created OK$/
			|| $line =~ /^Terminating game$/ )
		{
			brIRC::ircmsg( "9$line", "A" );	# Admin channel only
		}

		# If server crashed clear all player data, or people rejoining quickly
		# might be mistaken for nick stealers!
		if ( $line =~ /^Initializing .+ Mode$/ )
		{
			brIRC::ircmsg( "9$line" );	# Show in both channels
			playerData::clearAllData();
			RenRem::RenRemCMD ( "sversion" );
			brconfig::GetAvailableMaps();
		}


		# Record player scripts version
		if ( $line =~ /^The version of player (.+?) is (\d+\.\d+)( r%d+)?/i )
		{
			playerData::setKeyValue ( $1, "scriptsVersion", $2 );
			playerData::setKeyValue ( $1, "scriptsRevision", $3 );
		}

		# Record the version of the server
		if ( $line =~ /^The Version of the server is (.+)/ || $line =~ /^The version of (?:bhs|tt).dll on this machine is (\d+\.\d+)( r%d+)?/i )
		{
			$brconfig::serverScriptsVersion = $1;
			$brconfig::serverScriptsRevision = $2;
		}


		# Record player bandwidth
		if ($line =~ /Current Bandwidth for player (.*?) is (.+)/)
			{ playerData::setKeyValue ( $1, "bandwidth", $2 ); }


		if ($line =~ /is required for this map/)
		{
			$brconfig::config_force_bhs_dll_map = 1;

			# Check players already ingame
			my %playerData = playerData::getPlayerList();
			while ( my ( $id, $player ) = each ( %playerData ) )
			{
				# Only check them if they have been ingame longer than 4 seconds
				# Players who have just joined might not have had chance to respond
				if ( length ( $player->{'scriptsVersion'} ) == 0 && ( ( time() - $player->{'joinTime'} ) > 4 ) )
				{
					modules::kick_player ( $player->{'id'}, 'BRenBot', 'Scripts version 1.3 or higher is required to play on this map (pre 1.3 installed)' );
				}
			}
		}

		if ($line =~ /Loading level (.+)/)
		{
			brIRC::ircmsg( "9$line" );
			serverStatus::updateMap ( $1 );

			if ( $renew_ssgm == 1 )
			{
				$ssgm::midnight = 1;
				$poe_kernel->post("ssgm_tail", "renew_wheel");
				$renew_ssgm = 0;
			}

			$brconfig::config_force_bhs_dll_map = 0;

			# Schedule game results to run in 1 second
			if ( modules::get_module( "gameresults" ) )
			{
				POE::Session->create
				( inline_states =>
					{
						_start => sub
						{
							$_[HEAP]->{next_alarm_time} = int( time() ) + 1;
							$_[KERNEL]->alarm( do_results => $_[HEAP]->{next_alarm_time} );
						},
						do_results => \&results::DisplayGameResults
					}
				);
			}

			# Issue a mapnum command to ensure the map number is updated
			RenRem::RenRemCMD ( "mapnum" );

			# Restore original map rotation if someone used !setnextmap during the last game
			my $nextmapChanged = brdatabase::get_global('nextmap_changed');
			if ( $nextmapChanged )
			{
				modules::console_output ( "Restoring original map rotation..." );
				
				if ( $nextmapChanged == 1 )
				{
					my $backup;

					open (FDSfile, "svrcfg_cnc.ini.old") or modules::console_output ( "Error reading backup map rotation file!" );
					while (<FDSfile>) { $backup .= $_; }
					close (FDSfile);

					open (FDSfile, ">$brconfig::config_fdsconfigfile") or modules::console_output ( "Error writing map configuration file!" );
					print FDSfile $backup;
					close (FDSfile);

					undef $backup;
				}
				elsif ( $nextmapChanged == 4 )
				{
					# Read the ID and mapname that were changed
					my $mapid = brdatabase::get_global('nextmap_changed_id');
					my $mapname = brdatabase::get_global('nextmap_changed_mapname');
					
					modules::console_output ( "Restoring map at index $mapid to $mapname." );
					RenRem::RenRemCMD ( "mlistc $mapid $mapname" );

					# Update the rotation
					foreach (@brconfig::maplist)
					{
						if ( $_->{'id'} == $mapid )
						{
							$_->{'mapname'} = $mapname;
							last;
						}
					}
				}
				brdatabase::set_global('nextmap_changed', '0')
			}
		}

		#Highlight Host msgs
		if ( $line =~ m/^Host:/ )
		{
			my $ircLine = $line;
			$ircLine =~ s/^Host:/14Host:/gi;
			brIRC::ircmsg( "$ircLine" );
		}

		$_ = $line; # Matches below only work on $_ variable.
		#  if (/committed suicide./g) {$line="$line";brIRC::ircmsg(  "$line");}

		# Vehicle purchase
		if ( m/(.+) purchased a vehicle/i )
		{
			my ( $result, %player ) = playerData::getPlayerData( $1 );
			if ( $result == 1 )
			{
				if ( $brconfig::gamelog_show_vehicle_purchase == 1 )
				{
					my $color = "04";

					if ( $player{'side'} eq "GDI" || $player{'side'} eq "All" )
					{
						$color = ( $main::currentMod eq "APB" ) ? "12" : "08";
					}

					if ( !modules::get_module( "gamelog" ) )
						{ brIRC::ircmsg( "3[Vehicle Purchase]: $color$player{name}", "A" ); }
					else
						{ gamelog::vehicle_purchase_renlog( $player{'name'} ); }
				}

				if ( $brconfig::config_vehiclekick == 1 )
				{
					modules::kick_player ( $player{'id'}, 'BRenBot', 'Purchasing a vehicle in an infantry only server' );
				}
			}
		}

		if ( /Connection broken to client./g ) { brIRC::ircmsg( "$line" ); }

		if ( /was kicked/g ) { brIRC::ircmsg( "$line" ); }
	}


	# Look for any plugins whose regex hooks match this line
	my @plugins = plugin::get_plugin_renlog_regexes();

	my %args;
	$args{'rawline'}		= $rawline;
	$args{'line'}			= $line;
	$args{'time'}			= $time;

	foreach (@plugins)
	{
		my $plugin = $_;
		my %regexes = %{$plugin::plugin_renlog_regexes{$plugin}};
		my $alias  = "plugin_" . $plugin;

		while (my ($regex, $event) = each %regexes)
		{
			if ( $rawline =~ m/$regex/i )
			{ $main::poe_kernel->post($alias => $event => \%args); }
 		}
	}
}


# Got a line from the renlog
sub parse_line
{
	my $line = shift;
	ChatMSG( $line );
	ParseLogInput( $line."\n" );
}








###############################################
## MESSAGE HANDLERS
###############################################

sub handleInvite
{
	my $pager	= shift;
	my $pagemsg	= shift;

	if ( lc($pagemsg) eq "letmein" )
	{
		if (check_invite($pager) eq $pager)
		{
			RenRem::RenRemCMD( "page $pager [BR] You are ALREADY invited. Stop SPAMMING." );
			brIRC::ircmsg( "9Page Sent to $pager --> [BR] You are ALREADY invited. Stop SPAMMING." );
		}
		else
		{
			add_invite($pager);
			mass_invite;
		}
	}

	if ($pagemsg =~ /WWDECLINE/)
	{
		brIRC::ircmsg(  "[BR] $pager declined invite...tearing up invitation" );
		RenRem::RenRemCMD( "page $pager [BR] Removed your invitation." );
		del_invite($pager);
	}
}




1;
