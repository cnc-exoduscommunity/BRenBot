#!/usr/bin/perl -w

package renlog;
use strict;

use POE;
use POE::Wheel::FollowTail;

use modules;
use brconfig;
use commands;
use brdatabase;
use brAuth;

my %joiners;                # List of players who have joined since the last player info
our $renew_ssgm     = 0;

my $logPlayerInfo   = 0;    # Used to parse player_info commands
my $readGameDefs    = 0;    # Used to indicate when we are recieving a list of SSGM4.0 gamedefs

# Forward declarations
sub handle_page($$);
sub handle_chat($$$);
sub handle_hostmsg($);
sub handle_input($);


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
				# Get name of logfile
				my $name = $brconfig::config_fdslogpath . modules::get_date_time( "renlog_MM-DD-YYYY.txt" );

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
	if ( $playerDataLine =~ m/(\d+)\s(.+?)\s+(-{0,1}\d+)\s+([a-zA-Z]{1,3})\s+(\d+)\s+(\d+\.\d+\.\d+\.\d+)[\;\d]*\s+(\d+)\s+(\d+\.\d+\.\d+)/i )
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

      my $command = 'kick '.$player{'id'};
      $command .= ' Fake Nickname' if ($brconfig::ssgm_version >= 4);
      RenRem::RenRemCMD ( $command, 1 );
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

        my $command = 'kick '.$player->{'id'};
        $command .= ' Impersonating someone else' if ($brconfig::ssgm_version >= 4);
        RenRem::RenRemCMD ( $command, 1 );
			}
		}
	}
}


# Checks the banlist to see if the specified player is banned
sub check_banlist
{
  my ($result, %player) = playerData::getPlayerData(shift, 1);
  if (1 == $result)
  {
    return 1 if 1 == $player{'banned'};
  
    my ($banresult, $reason, $banner, $date) = modules::is_banned($player{'name'});
    if ($banresult)
    {
      modules::console_output("player_id $player{id} is BANNED");
      RenRem::RenRemCMD("msg [BR] $player{name} has been BANNED on $date by $banner for: $reason");

      if ($brconfig::serverScriptsVersion >= 2.0)
        { RenRem::RenRemCMD( "pamsg $player{id} You have been BANNED on $date by $banner for: $reason" ); }

      # If we are using SSGM 4.0 then we need to add this ban to it's bans list
      if ($brconfig::ssgm_version >= 4)
      {
        RenRem::RenRemCMD('ban '.$player{'id'}." Banned on $date by $banner for $reason");
      }

      # Otherwise remove them from the server the old fashioned way
      else
      {
        RenRem::RenRemCMD ('kick '.$player{'id'});
      }
      playerData::setKeyValue($player{'id'}, "banned", 1);
      return 1;
    }
  }

  return 0;
}

# --------------------------------------------------------------------------------------------------

# Got a line from the renlog
sub parse_line
{
  my $rawline = shift;          # Keep this in a seperate variable for plugins etc
  my $line = $rawline;
  my $time = "";

  # Strip timestamp from input
  if ($line =~ m/^\[(\d{2}:\d{2}:\d{2})\]\s?(.+)\r?\n?/i)
  {
    $time = $1;
    $line = $2;
  }

  $line =~ s/	/ /g;   # replace any TABS with a space
  $line =~ s/^ //;    #eat leading spaces

  #modules::console_output("[Renlog] DEBUG: Parsing input ==>$line<==");

  # Skip level loading messages ([00:52:01] Load 0% complete[00:52:01] Load 0% complete....)
  return if ($line =~ m/^Load \d+\% Complete/i);

  # 10 Sept 2012: Added extra protection by explicitly disallowing : in the username of the player
  # sending the chat message to help prevent abuse of the ambiguous logging format. Also ignoring
  # any names with spaces in since we are banning those now (see check_playername)
  if ($line =~ m/^(\[Team\]\s)?([^\s:]+):\s(.+)/i)
  {
    #modules::console_output("[Renlog] DEBUG: Chat message");
    handle_chat($2, $3, (defined($1) and $1 eq "[Team] ") ? 1 : 0);
  }

  elsif ($line =~ m/^\[Page\]\s([^:]+):\s(.+)$/)
  {
    #modules::console_output("[Renlog] DEBUG: Page");
    handle_page($1, $2);
  }

  else
  {
    #modules::console_output("[Renlog] DEBUG: Other input");
    handle_input($line);
  }

  # Look for any plugins whose regex hooks match this line
  my %args = (
    'rawline' => $rawline,
    'line'    => $line,
    'time'    => $time
  );

  my %plugins = plugin::get_plugin_regex_hooks('renlog');
  while ( my($plugin, $regexes) = each(%plugins) )
  {
    while (my ($regex, $event) = each %{$regexes})
    {
      if ( $rawline =~ m/$regex/i )
      {
        eval { $main::poe_kernel->post("plugin_".$plugin => $event => \%args); }
          or modules::display_error($@);
      }
    }
  }
}

# --------------------------------------------------------------------------------------------------

sub handle_page($$)
{
  my ($pager, $message) = @_;

  # !auth commands contain passwords so we handle them first without printing to IRC or console
  if ($message =~ m/^!auth\s+(.*)$/i)
  {
    my $pass = $1;

    if (!$pass)
    {
      RenRem::RenRemCMD("page $pager [BR] Usage: !auth <pass>");
      return;
    }

    my $authResult = brAuth::AuthenticateByPassword($pager, $pass);
    if (1 == $authResult)
    {
      RenRem::RenRemCMD("page $pager [BR] Authentication was successful!");
      brIRC::ircmsg( "[BR] Authentication for $pager was successful.", "A" );
    }
    elsif (0 == $authResult)
    {
      RenRem::RenRemCMD( "page $pager [BR] Wrong password!" );
      brIRC::ircmsg( "[BR] $pager gave an invalid password.", "A" );
    }
    elsif (2 == $authResult)
    {
      RenRem::RenRemCMD( "page $pager [BR] You are already authenticated." );
    }
    elsif (3 == $authResult)
    {
      RenRem::RenRemCMD( "page $pager [BR] Your nickname is not registered. Register it first." );
    }
    elsif (4 ==  $authResult)
    {
      brIRC::ircmsg( "9[Page] $pager tried to !auth from outside the game!", "A" );
      RenRem::RenRemCMD( "page $pager [BR] $pager your auth-exploit has been logged and will be reviewed." );
    }

    # Don't allow any further processing since this string contains a password
    return;
  }

  # Log the page to the console and IRC
  my $logmessage = "[Page] $pager: $message";
  modules::console_output($logmessage);
  brIRC::ircmsg(brIRC::colourise(9, $logmessage), "A");
}

# --------------------------------------------------------------------------------------------------

# Processes chat messages, and outputs them to IRC
#
# Chat Messages Look like this: [23:58:36] flawliss9: BAD LAG
# Team Messages Look like this: [23:58:36] [Team]: flawliss9: BAD LAG
sub handle_chat($$$)
{
  my ($sender, $message, $isTeamMessage) = @_;

  # Prevent bugs/command abuse caused by players with : in their name
  return if ("$5$6" =~ m/^Player\s.+\s(joined|left)\sthe\sgame$/
          || "$5$6" =~ m/^.+:\s!\s.+\swas\skicked$/);

  # Handle host messages and drop out without additional processing
  if ($sender eq "Host")
  {
    handle_hostmsg($message);
    return;
  }

  # Get data for person who chatted
  my ($result, %player) = playerData::getPlayerData($sender);
  if (1 == $result)
  {
    # Format mod and admin names
    my $ircPlayername = modules::parseModName($player{'name'}, 1);

    # F2 chat
    if (!$isTeamMessage)
    {
      brIRC::ircmsg(brTeams::colourise($player{'teamid'}, $ircPlayername).": $message", "B");
    }

    # F3 chat, if teammessages is enabled
    elsif (modules::get_module("teammessages"))
    {
      brIRC::ircmsg(
        brIRC::colourise(6, "[Team] ").brTeams::colourise($player{'teamid'},"$ircPlayername: $message"),
        (1 == $brconfig::irc_showTeamMessages_PublicChan) ? "B" : "A"
      );
    }


    # Handle !commands
    if ( $message =~ m/^\!/i)
    {
      eval { commands::parsearg($message, $player{'name'}, "N"); }
        or modules::display_error($@);
    }


    # Run plugins for public chat messages
    my @plugins = plugin::get_plugin_event("text");
    my %args;

    $args{id}           = $player{'id'};
    $args{nick}         = $player{'name'};
    $args{nicktype}     = 0;
    $args{message}      = $message;
    $args{messagetype}  = ($isTeamMessage) ? "team" : "public";
    $args{team}         = $player{'side'};

    foreach (@plugins)
    {
      eval { $main::poe_kernel->post("plugin_".$_ => "text" => \%args); }
        or modules::display_error($@);
    }
  }
}

# --------------------------------------------------------------------------------------------------

sub handle_hostmsg($)
{
  my $message = shift;

  # Check for team change events
  if ( $message =~ m/^(.+?) changed teams.$/ )
  {
    brIRC::ircmsg(brIRC::colourise(11, "Host: ".$message), "B");

    # Mark the player as having changed teams
    playerData::setKeyValue($1, "changedTeam", 1);

    # Update game data
    RenRem::RenRemCMD("game_info");
    RenRem::RenRemCMD("player_info");
  }
  else
  {
    brIRC::ircmsg(brIRC::colourise(14, "Host: ").brIRC::bold($message), "B");
  }
}

# --------------------------------------------------------------------------------------------------

sub handle_input($)
{
  my $line = shift;

  # If we're currently reading game definitions then add the line to the list of maps without parsing
  if (1 == $readGameDefs)
  {
    if ($line eq "")
    {
      #modules::console_output("[Renlog] DEBUG: End of map defs.");
      $readGameDefs = 0;
    }
    else
    {
      #modules::console_output("[Renlog] DEBUG: Got map $line");
      push (@brconfig::installed_maps, $line);
    }

    return;
  }


  # Start of game defs?
  if ( $line =~ m/Available game definitions:/ )
  {
    #modules::console_output("[Renlog] DEBUG: Start of map defs");
    $readGameDefs = 1;
    @brconfig::installed_maps = ();
    return;
  }

  # Reply from mapnum command
  if ( $line =~ m/The Current Map Number is (\d+)/i )
  {
    serverStatus::updateMapNum($1);
    return;
  }

  # Start of the reply from the game_info command
  if ($line =~ m/(.+?) mode active/g)
  {
    serverStatus::updateMode($1);
    return;
  }

  if ( $line =~ /Map : (.+)/ )
  {
    serverStatus::updateMap($1);
    return;
  }

  if ($line =~ /Time : (.+)/)
  {
    serverStatus::updateTimeRemaining($1);
    return;
  }

  if ($line =~ /Fps : (.+)/)
  {
    serverStatus::updateSFPS($1);
    return;;
  }

  my $team0abbrv = brTeams::get_abbreviation(0);
  if ($line =~ /$team0abbrv : (.+?)\/(.+?) players\s+ (.+?) points/i)
  {
    serverStatus::updateStatus_Nod($1, $3, $2);
    return;
  }

  my $team1abbrv = brTeams::get_abbreviation(1);
  if ($line =~ /$team1abbrv : (.+?)\/(.+?) players\s+ (.+?) points/)
  {
    serverStatus::updateStatus_GDI($1, $3, $2);
    return;
  }




  # First line of output from player_info command
  if ( $line =~ /Id\s+Name/ )
  {
    $logPlayerInfo = 1;
    return;
  }

  if ( $line =~ "No players" )
  {
    $logPlayerInfo = 0;
    return;
  }

  # Last line of output from player_info command
  if ($line =~ "Total current bandwidth")
  {
    $logPlayerInfo = 0;
    checkPlayerlist();
    return;
  }

  # Player data line from a player_info command
  if ($logPlayerInfo)
  {
    parsePlayerInfoInput($line);
    return;
  }




  if ($line =~ m/^Player (.+?) left the game$/)
  {
    # Player left, need to update Player Array...
    my ( $result, %player ) = playerData::getPlayerData ( $1 );
    if ( $result != 1 )
    {
      $player{'name'} = $1;
    }

    if ( !plugin::call_core_override('playerleave_msg', $1) )
      { brIRC::ircmsg( brIRC::colourise(11,"$1 left the game from team ").brTeams::get_colourised_name($player{'side'}) ); }

    my @plugins = plugin::get_plugin_event( "playerleave" );
    my %args;

    $args{'id'} = $player{'id'};
    $args{'nick'} = $player{'name'};
    $args{'name'} = $player{'name'};
    $args{'teamid'} = $player{'teamid'};
    $args{'ip'} = $player{'ip'};

    foreach (@plugins)
    {
      eval { $main::poe_kernel->post("plugin_".$_ => "playerleave" => \%args); }
        or modules::display_error($@);
    }

    $#plugins = -1;

    $player{'name'} =~ s/'/''/g;

    RenRem::RenRemCMD( "game_info" );
    RenRem::RenRemCMD( "player_info" );

    # Remove all the data we are storing about them
    playerData::clearPlayerData ( $player{'id'} );
    return;
  }

  # A player joined the game
  if ( $line =~ m/^Player (.*?) joined the game$/ )
  {
    my $joiner = $1;

    $joiners{lc($joiner)} = 1;
    #brIRC::ircmsg( "11$line" );   // Now done in joinstuff

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

    # Check if their name is all spaces
    if ( $joiner =~ m/[\s+]$/ )
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
    return;
  } # end of joined the game


  if ( $line =~ m/^Level loaded OK$/ )
  {
    # New Level has reloaded, need to update Player Array...

    brIRC::ircmsg( "9$line", "A" );
    brconfig::readServerSettings(); # Re-read the server settings

    # Apply map settings
    modules::applyMapSettings(1);

    my @plugins = plugin::get_plugin_event( "mapload" );

    my %args;
    $args{'map'} = serverStatus::getMap();

    foreach ( @plugins )
    {
      eval { $main::poe_kernel->post("plugin_".$_ => "mapload" => \%args); }
        or modules::display_error($@);
    }

    # Process autobalance (if it is enabled)
    modules::do_autobalance();

    # Update game information
    RenRem::RenRemCMD( "game_info" );
    RenRem::RenRemCMD( "player_info" );
    return;
  }

  # Handle any lines which just get thrown out to the IRC
  if ( $line =~ m/^\w+ not found$/
    || $line =~ m/^Logging on....$/
    || $line =~ m/^Logging onto .+ Server$/
    || $line =~ m/^Failed to log in$/
    || $line =~ m/^Creating game channel$/
    || $line =~ m/^Channel created OK$/
    || $line =~ m/^Terminating game$/ )
  {
    brIRC::ircmsg( "9$line", "A" );	# Admin channel only
    return;
  }

  # If server crashed clear all player data, or people rejoining quickly
  # might be mistaken for nick stealers!
  if ( $line =~ m/^Initializing .+ Mode$/ )
  {
    brIRC::ircmsg( "9$line" );	# Show in both channels
    playerData::clearAllData();
    RenRem::RenRemCMD ( "sversion" );
    brconfig::GetAvailableMaps();
    return;
  }


  # Record player scripts version
  if ( $line =~ m/^The version of player (.+?) is (\d+\.\d+)( r%d+)?/i )
  {
    playerData::setKeyValue ( $1, "scriptsVersion", $2 );
    playerData::setKeyValue ( $1, "scriptsRevision", $3 );
    return;
  }

  # Record the version of the server
  if ( $line =~ m/^The Version of the server is (.+)/ || $line =~ m/^The version of (?:(?:bhs|tt|bandtest).dll|(?:game|server).exe) on this machine is (\d+\.\d+)( r%d+)?/i )
  {
    $brconfig::serverScriptsVersion = $1;
    $brconfig::serverScriptsRevision = $2;
    return;
  }


  # Record player bandwidth
  if ($line =~ /Current Bandwidth for player (.*?) is (.+)/)
  {
    playerData::setKeyValue ( $1, "bandwidth", $2 );
    return;
  }


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

    return;
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
    POE::Session->create
    ( inline_states =>
      {
        _start => sub
        {
          $_[HEAP]->{next_alarm_time} = int( time() ) + 1;
          $_[KERNEL]->alarm( do_results => $_[HEAP]->{next_alarm_time} );
        },
        do_results => \&results::ProcessGameResults
      }
    );

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

    return;
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
        if ( !modules::get_module( "gamelog" ) )
          { brIRC::ircmsg( "3[Vehicle Purchase]: ".brTeams::colourise($player{'teamid'},$player{'name'}), "A" ); }
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

1;
