#!/usr/bin/perl

package playerData;
use strict;

use POE;
use modules;
use brconfig;
use RenRem;


# Main player data hash
my %playerData;


# Updates player data ( or, if they are not found, adds it )
# Used by the parse_player_list function in renlog
sub updatePlayerData
{
  my $id    = shift;      my $name  = shift;
  my $score = shift;      my $side  = shift;
  my $ping  = shift;      my $ip    = shift;
  my $kbps  = shift;      my $time  = shift;

  if ( !exists ( $playerData{$id} ) or ( $playerData{$id}->{'name'} ne $name ) )
  {
    # A new player has joined the game, clear any existing stale data... (shouldn't ever trigger...)
    clearPlayerData ( $id ) if ( exists($playerData{$id}) );
    
    $playerData{$id} = {
      'id'          => $id,
      'name'        => $name,
      'joinTime'    => time()
    };

    renlog::check_banlist ( $name );
    modules::check_kicks ( $name );
    RenRem::RenRemCMD ( "version $id" );
  }
  else
  {
    # If they have changed sides process teamchange plugin events
    if ( $playerData{$id}->{'changedTeam'} && $playerData{$id}->{'changedTeam'} == 1 )
    {
      processTeamChangePlugins ( $name, $side, $playerData{$id}->{'side'} );
      $playerData{$id}->{'changedTeam'} = 0;
    }
  }
  
  # Update the player data array
  $playerData{$id}->{'score'}       = $score;
  $playerData{$id}->{'side'}        = $side;
  $playerData{$id}->{'teamid'}      = brTeams::get_id_from_name($side);
  $playerData{$id}->{'ping'}        = $ping;
  $playerData{$id}->{'ip'}          = $ip;
  $playerData{$id}->{'kbps'}        = $kbps;
  $playerData{$id}->{'time'}        = $time;
  $playerData{$id}->{'lastUpdated'} = time();
}



# Cleans up after a player leaves the game
sub clearPlayerData
{
	my $playerID = shift;

	if ( $playerID !~ m/^\d\d?$/ )
	{
		my $result;
		( $result, $playerID ) = playerNameToID ( $playerID );
		return if ( $result != 1 );
	}

	### TEMP VARIABLE - See below
	my $name = $playerData{$playerID}->{'name'};


	# Delete data
	foreach my $k ( keys %{$playerData{$playerID}} )
	{ delete $playerData{$playerID}->{$k}; }
	delete $playerData{$playerID};


	#### OLD CODE - REMOVE ONCE REDUNDANT

	# If they are a temp mod remove them from the list
	if ( $main::tempMods{lc($name)} )
	{
		delete $main::tempMods{lc($name)};
		RenRem::RenRemCMD( "msg [BR] $name is no longer a temporary game moderator." );
		return;
	}

	undef $name;
}


# If the FDS crashes this is called to clear all player data
sub clearAllData
{
  foreach my $playerID ( keys %playerData )
  {
    foreach my $k ( keys %{$playerData{$playerID}} )
    { delete $playerData{$playerID}->{$k}; }
    delete $playerData{$playerID};
  }
}


# Converts a player name to an ID
#
# Returns search success ( 0 = not found, 1 = unique found, 2 = non unique )
# Second return is matched id, if result == 1
#
sub playerNameToID
{
	my $name = quotemeta(shift);
	my $exactMatchOnly = shift;
	my $foundID = 0;

	# Reset hash to start before we begin looping
	keys %playerData;

	while ( my ( $id, $data ) = each %playerData )
	{
		if ( $data->{'name'} =~ m/^$name$/i )	# Exact match
			{ $foundID = $id; last; }
		elsif ( $data->{'name'} =~ m/$name/i && (!defined($exactMatchOnly) || $exactMatchOnly != 1) )
		{
			if ( $foundID == 0 )
				{ $foundID = $id; }			# Found non exact match
			else
				{ $foundID = -1; }			# Multiple non exact matches found
		}
	}

	# Reset hash again incase we finished early
	keys %playerData;

	if ( $foundID == 0 )
		{ return 0; }
	elsif ( $foundID == -1 )
		{ return 2; }
	else
		{ return ( 1, $foundID ); }

	return 0;
}



###################################################
####
## Functions for storing data about a player
####
###################################################

# Creates / updates a hash key and its value. No return value
sub setKeyValue
{
	my $playerID			= shift;
	my $keyName				= shift;
	my $keyValue			= shift;

	if ( $playerID !~ m/^\d\d?$/ )
	{
		my $result;
		($result, $playerID) = playerNameToID ( $playerID );
		return if ( $result != 1 );
	}

	if ( exists ( $playerData{$playerID} ) )
	{
		$playerData{$playerID}->{$keyName} = $keyValue;
	}
}


# Increments a hash keys value. Returns new value
sub incrementKeyValue
{
	my $playerID			= shift;
	my $keyName				= shift;
	my $incrementAmount		= shift;

	if ( $playerID !~ m/^\d\d?$/ )
	{
		my $result;
		($result, $playerID) = playerNameToID ( $playerID );
		return if ( $result != 1 );
	}

	if ( exists ( $playerData{$playerID} ) )
	{
		if ( $incrementAmount )
			{ $playerData{$playerID}->{$keyName} += $incrementAmount; }
		else
			{ $playerData{$playerID}->{$keyName}++; }
		return $playerData{$playerID}->{$keyName};
	}

	return undef;
}


# Deletes a hash key and its value. No return value
sub deleteKeyValue
{
	my $playerID			= shift;
	my $keyName				= shift;

	if ( $playerID !~ m/^\d\d?$/ )
	{
		my $result;
		($result, $playerID) = playerNameToID ( $playerID );
		return if ( $result != 1 );
	}

	if ( exists ( $playerData{$playerID} ) )
	{
		delete $playerData{$playerID}->{$keyName};
	}
}


###################################################
####
## Functions for getting data about a player
####
###################################################

# Returns a hash of all information for a specific player
sub getPlayerData
{
  my $playerID = shift;
  my $exactMatchOnly = shift;

  if ( $playerID !~ m/^\d\d?$/ )
  {
    my $result;
    ( $result, $playerID ) = playerNameToID ( $playerID, $exactMatchOnly );
    if ( $result != 1 )
      { return $result, (); }
  }

  if ( exists ( $playerData{$playerID} ) )
  {
    return 1, %{$playerData{$playerID}};
  }

  return 0, ();
}


# Returns the value of the specified key, or undef if it does not exist
sub getKeyValue
{
  my $playerID = shift;
  my $keyName = shift;

  if ( $playerID !~ m/^\d\d?$/ )
  {
    my $result;
    ($result, $playerID) = playerNameToID ( $playerID );
    return undef if ( $result != 1 );
  }

  if ( exists ( $playerData{$playerID} ) )
  {
    if ( defined ( $playerData{$playerID}->{$keyName} ) )
      { return $playerData{$playerID}->{$keyName}; }
  }
  return undef;
}


# Returns a hash of all player data
sub getPlayerList
{
  return %playerData;
}


# Returns a hash of all players on the specified team
#
# \param[in] $team
#   ID or abbreviation of a team
sub getPlayersByTeam
{
  my $teamid = brTeams::get_id_from_name(shift);

  my %teamplayers;
  while ( my ( $id, $player ) = each ( %playerData ) )
  {
    # Undef == 0, so we need to differentiate them properly by checking for !defined
    $teamplayers{$id} = $player if ( ($player->{'teamid'} == $teamid) and (defined($teamid) == defined($player->{'teamid'})) );
  }
  return %teamplayers;
}


# Processes changeteam events for plugins
sub processTeamChangePlugins
{
  my %args;
  $args{'nick'} = shift;
  $args{'newteam'} = shift;
  $args{'oldteam'} = shift;

  my @plugins = plugin::get_plugin_event( "changeteam" );
  foreach ( @plugins )
  {
    my $plugin = $_;
    my $alias = "plugin_" . $plugin;
    $poe_kernel->post( $alias => "changeteam" => \%args );
  }
}

1;
