# serverStatus.pm
#
# Holds information about the current game status, such as player counts, map name
# etc, instead of having it spread all over the place.

package serverStatus;
use strict;

use POE;
use RenRem;

# Variables for holding the server status
my $serverMode        = "WOL";
my $currentMap        = "last round";
my $currentMapNum     = -1;
my $mapStartTime      = 0;
my $lastMap           = "last round";
my $maxPlayers        = 0;
my $gdiPlayers        = 0;
my $gdiPoints         = 0;
my $nodPlayers        = 0;
my $nodPoints         = 0;
my $timeRemaining     = 0;
my $sfps              = 0;
my $radarmode         = -1; # radarmode

# Variables for the status refresh loop
my $lastRequestTime   = 0;
my $lastResponseTime  = 0;
my $fdsResponding     = 0;

# Other misc data about the server
my $defaultMaxPlayers = 0;
my $isPassworded      = 0;
my $startMap          = "N/A";


###################################################
####
## PI and GI update thread
## Requests updated player_info and game_info every 30 seconds
####
###################################################

sub init
{
	POE::Session->create
	( inline_states =>
		{
			_start => sub
			{
				modules::console_output ( "Starting game status refresh thread..." );
				$_[HEAP]->{next_alarm_time} = int( time() ) + 10;
				$_[KERNEL]->alarm( tick => $_[HEAP]->{next_alarm_time} );

				$lastResponseTime = (time() -1);
				$lastRequestTime = time();
			},
			tick => sub
			{
				if ( $lastResponseTime < ($lastRequestTime -30) && $fdsResponding == 1 )
				{
					brIRC::ircmsg ( "04Warning: The FDS has not responded to the last two status requests, it may have gone offline.", "A" );
					$fdsResponding = 0;
				}
        elsif ( $lastResponseTime > $lastRequestTime && $fdsResponding == 0 )
        {
          brIRC::ircmsg ( "03 The FDS is now responding to status requests.", "A" );
          $fdsResponding = 1;

          # Check for changes in configuration of the server
          RenRem::RenRemCMD ( "mapnum" );
          RenRem::RenRemCMD ( "sversion" );
          brconfig::GetAvailableMaps();
        }

				# Get updated player info and game info
				$lastRequestTime = time();

				# Request map number if we don't already know it
				if ( $currentMapNum == -1 ) { RenRem::RenRemCMD ( "mapnum" ); }

				# Request server scripts version if we dont have it already
				if ( $brconfig::serverScriptsVersion eq '0.0' ) { RenRem::RenRemCMD ( "sversion" ); }

				RenRem::RenRemCMD( "player_info" );
				RenRem::RenRemCMD( "game_info" );
				$_[HEAP]->{next_alarm_time}= int( time() ) + 30;
				$_[KERNEL]->alarm( tick => $_[HEAP]->{next_alarm_time} );
			}
		} # end of inline states
	);
}


###################################################
####
## Status update functions
####
###################################################

# Updates the game mode
sub updateMode
{
	my $mode = shift;
	if ( $mode =~ m/Westwood/i )
	{
		$serverMode = "WOL";
	}
	elsif ( $mode =~ m/GameSpy/i )
	{
		$serverMode = "GSA";
	}
	$lastResponseTime = time();
}

# get radarmode
sub updateRadarMode()
{
	$radarmode = shift;
}


# Updates the map name
sub updateMap
{
	my $mapName = shift;
	$lastResponseTime = time();

	if ( $mapName ne $currentMap )
	{
		$lastMap = $currentMap;
		$currentMap = $mapName;
		$mapStartTime = time();

		# Only apply map settings if we just loaded, otherwise let the
		# Level Loaded OK event process it.
		if ( $lastMap eq "last round" )
			{ modules::applyMapSettings(0); }	# Do NOT apply time limit

		# Process any actions that need taking for a new map
		# Nothing at the moment...
	}

	undef $mapName;
}

# Updates the map number
sub updateMapNum
{
	$currentMapNum = shift;
	$lastResponseTime = time();
}

# Updates the time remaining
sub updateTimeRemaining
{
	$timeRemaining = shift;
	$lastResponseTime = time();
}

# Updates the sfps
sub updateSFPS
{
	$sfps = shift;
	$lastResponseTime = time();
}

# Updates the gdi player count and points, and max players
sub updateStatus_GDI
{
	$gdiPlayers = shift;
	$gdiPoints = shift;
	$maxPlayers = shift;
	$lastResponseTime = time();
}

# Updates the nod player count and points, and max players
sub updateStatus_Nod
{
	$nodPlayers = shift;
	$nodPoints = shift;
	$maxPlayers = shift;
	$lastResponseTime = time();
}

# Update default max players
sub updateDefaultMaxPlayers
{
	$defaultMaxPlayers = shift;
}

# Update passworded status
sub updateIsPassworded
{
	$isPassworded = shift;
}

# Update start map
sub updateStartMap
{
	$startMap = shift;
}


###################################################
####
## Functions for retrieving data
####
###################################################

# Returns array of all data
sub getGameStatus
{
  return ( $serverMode, $currentMap, $gdiPlayers, $gdiPoints, $nodPlayers, $nodPoints, ($nodPlayers+$gdiPlayers), $maxPlayers, $timeRemaining, $sfps );
}

# Returns current server mode
sub getMode
{
	return $serverMode;
}

# Returns current time remaining
sub getTime
{
	return $timeRemaining;
}

# Returns current map
sub getMap
{
	return $currentMap;
}

# Returns current map number
sub getMapNum
{
	return $currentMapNum;
}

# Returns the timestamp for when this map started
sub getMapStartTime
{
	return $mapStartTime;
}

# Returns previous map
sub getLastMap
{
	return $lastMap;
}

# Returns gdi players
sub getPlayers_GDI
{
	return ( $gdiPlayers );
}

# Returns nod players
sub getPlayers_Nod
{
	return ( $nodPlayers );
}

# Returns gdi points
sub getPoints_GDI
{
	return ( $gdiPoints );
}

# Returns nod points
sub getPoints_Nod
{
	return ( $nodPoints );
}

# Returns total player count
sub getCurrentPlayers
{
	return ( $nodPlayers + $gdiPlayers );
}

# Returns max player count
sub getMaxPlayers
{
	return $maxPlayers;
}

# Returns default max players
sub getDefaultMaxPlayers
{
	return $defaultMaxPlayers;
}

# Returns passworded status
sub getIsPassworded
{
	return $isPassworded;
}

# Update start map
sub getStartMap
{
	return $startMap;
}

# get radarmode
sub getRadarMode
{
	return $radarmode;
}



1;
