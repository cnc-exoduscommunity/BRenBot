# The recommendations plugin for BRenBot 1.54 and newer, this contains all the functionality of the
# recommendations system that existed in BRenBot prior to version 1.53.14
#
# \author Daniel Paul (danpaul88)
# \version 1.0

package recommendations;

use POE;
use plugin;

my $currentVersion = '1.0';

# Check bot compatibility
if ( !defined(plugin::getBrVersion) || plugin::getBrVersion() < 1.53
  || (plugin::getBrVersion() == 1.53 && plugin::getBrBuild() < 14 ) )
{
  print " == Recommendations Plugin Error ==\n"
      . "This version of the plugin is not compatible with BRenBot versions older than 1.53.14\n";
  return 0;
}

# --------------------------------------------------------------------------------------------------

# BRenBot supplies these on plugin startup
our $plugin_name;
our %config;

# Define additional events in the POE session
our %additional_events =
(
  'recommend'   => 'recommend',
  'n00b'        => 'recommend',     # Same code for both functions
  'recignore'   => 'recignore',
  'recallow'    => 'recallow',
);

my $loaded_ok = 0;




# --------------------------------------------------------------------------------------------------
##
#### Bot Events
##
# --------------------------------------------------------------------------------------------------

sub start()
{
  return ($loaded_ok = 0) if ( db_update() != 1 );

  # Set our current version in the globals table
  plugin::set_global ( "version_plugin_recommendations", $pluginVersion );
  return ($loaded_ok = 1);
}

sub stop
{
}




# --------------------------------------------------------------------------------------------------
##
#### Game Events
##
# --------------------------------------------------------------------------------------------------

sub playerjoin
{
  return if ($loaded_ok == 0);

  my %args = %{@_[ ARG0 ]};
  show_recommendations($args{'nick'});
}

sub command
{
  return if ($loaded_ok == 0);

  my %args = %{@_[ ARG0 ]};
  $_[KERNEL]->yield ( $args{'command'} => \%args );
}




# --------------------------------------------------------------------------------------------------
##
#### Commands
##
# --------------------------------------------------------------------------------------------------

# !recommend command, commonly aliased as !rec, this allows a player to recommend another player for
# good teamwork... or any other reason they like really.
sub recommend
{
  my %args = %{$_[ ARG0 ]};
  my $isNoob = ($args{'command'} eq "n00b") ? 1 : 0;

  # Only available for use ingame
  if ( $args{'nicktype'} == 1 )
  {
    plugin::ircmsg ( "This command can only be used by players in the server", $args{'ircChannelCode'} );
    return;
  }

  # Check for rec_ignore
  if ( is_rec_ignored($args{'nick'}) )
  {
    plugin::pagePlayer( $args{'nick'}, 'BRenBot', "Sorry, the server administrators have disabled recommendations for you" );
    return;
  }
  
  # Syntax check...
  if ( ($args{'arg'} =~ /^\!\S+\s(.+?)\s(.+)/i) )
  {
    my $target = $1;
    my $reason = $2;

    my ( $result, %player ) = playerData::getPlayerData ( $target );
    if ( $result == 1 )
    {
      if ( $player{'name'} eq $args{'nick'} and $isNoob == 0 )
      {
        plugin::pagePlayer( $args{'nick'}, 'BRenBot', "You are not allowed to recommend yourself.");
        return;
      }

      my $can_recommend = modules::can_recommend ( $args{'nick'}, $player{'name'}, $isNoob );
      if ( $can_recommend == 1 )
      {
        plugin::recommend_player( $player{'name'}, $args{'nick'}, $reason );
      }
      elsif ( $can_recommend == 2 )
      {
        plugin::pagePlayer( $args{'nick'}, 'BRenBot', "You have reached your daily limit for recommendations" );
      }
      else
      {
        plugin::pagePlayer( $args{'nick'}, 'BRenBot', 'You have already '.(($isNoob==0)?'recommended':'n00bed')." $player{'name'} today." );
      }
    }
    else
    {
      plugin::pagePlayer( $args{'nick'}, 'BRenBot', "Player $target was not found ingame, or is not unique." );
    }
  }
  
  else
    { report_syntax_error(\%args); }
}


# !recommendations command, commonly aliased as !recs, this allows an ingame player to check their
# recommendations score
sub recommendations
{
  my %args = %{$_[ ARG0 ]};

  # Only available for use ingame
  if ( $args{'nicktype'} == 1 )
  {
    plugin::ircmsg ( "This command can only be used by players in the server", $args{'ircChannelCode'} );
    return;
  }

  # Get recommendations and n00bs for $args{nick}
  my $recommendations = get_recommendation ( $args{'nick'} );
  my $n00bs = get_n00b ( $args{'nick'} );

  plugin::pagePlayer ( $args{'nick'}, "BRenBot", "You currently have ".($recommendations-$n00bs)." recommendations. ( $recommendations recs, $n00bs n00bs )" );
}


# !recignore command, used by moderators to ignore players for the recommendations system, which
# prevents them from giving or receiving recommendations
sub recignore
{
  my %args = %{$_[ ARG0 ]};

  if (!$args{'arg1'})
  {
    report_syntax_error(\%args);
    return;
  }

  my ( $result, %player ) = playerData::getPlayerData( $args{'arg1'} );
  if ( $result == 1 )
  {
    plugin::serverMsg( "Recommendations have been disabled for $player{name}.");
    rec_ignore( $player{'name'} );

    # Write the rec-ignore to the logs table
    plugin::write_to_log ( 12, "[Recommendations] $player{name} was rec ignored by $args{nick}." );
  }
  else
  {
    my $message = "$args{arg1} is not ingame, or the name is not unique.";
    if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
    else { plugin::pagePlayer($args{'nick'}, 'BRenBot', $message ); }
  }
}


# !recallow command, used by moderators to un-ignore players for the recommendations system
sub recallow
{
  my %args = %{$_[ ARG0 ]};

  if (!$args{'arg1'})
  {
    report_syntax_error(\%args);
    return;
  }

  my ( $result, %player ) = playerData::getPlayerData( $args{'arg1'} );
  if ( $result == 1 )
  {
    plugin::serverMsg( "Recommendations have been enabled for ".$player{'name'} );
    rec_allow( $player{'name'} );

    # Write the rec-allow to the logs table
    plugin::write_to_log ( 12, "[Recommendations] $player{name} was rec allowed by $args{nick}." );
  }
  else
  {
    my $message = "$args{arg1} is not ingame, or the name is not unique.";
    if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
    else { plugin::pagePlayer($args{'nick'}, 'BRenBot', $message ); }
  }
}


# Function for the !teamplayers / !shown00bs command
my $tpLastUsed = 0;   # Global variable used to track last used time
sub teamplayers
{
  my %args = %{$_[ ARG0 ]};
  my $showNoobs = ($args{'command'} eq "shown00bs") ? 1 : 0;
  
  # Check if there are any players in the server
  my $playerCount = (plugin::getGameStatus())[6];
  if ( $playerCount == 0 )
  {
    brIRC::ircmsg ( "There are no players in the server" $args{'ircChannelCode'} );
    return;
  }


  # Too recently used?
  if ( time() - $tpLastUsed < 120 )
  {
    if ( $args{'nicktype'} == 1 ) { brIRC::ircmsg ( "The !teamplayers/!shown00bs commands can only be used once every 2 minutes!" ); }
    else { plugin::servermsg ( "The !teamplayers/!shown00bs command can only be used once every 2 minutes! Use !recs to see your own recommendations." ); }
    return;
  }
  else { $tpLastUsed = time(); }
  
  
  # Print header line
  if ( $nPlayersWithRecs == 0 )
  {
    my $message = ($showNoobs==1)?'n00bs based on in-game complaints;':'Teamplayers based on recommendations;';
    if ( $args{'nicktype'} == 1 )
      { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
    else
      { plugin::servermsg($message); }
  }

  
  # Output data
  my $nPlayersWithRecs = teamplayers_processTeam(1, $showNoobs,(($args{'nicktype'}==1)?$args{'ircChannelCode'}:undef));
  $nPlayersWithRecs += teamplayers_processTeam(0, $showNoobs,(($args{'nicktype'}==1)?$args{'ircChannelCode'}:undef));
  
  
  # Check if nobody had any recs / noobs
  if ( $nPlayersWithRecs == 0 )
  {
    my $message = 'None of the players in the server have any '.(($showNoobs==1)?'n00bs':'recommendations');
    if ( $args{'nicktype'} == 1 )
      { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
    else
      { plugin::servermsg($message); }
  }
}

# Worker function for the !teamplayers command
sub teamplayers_processTeam
{
  my $teamid      = shift;
  my $showNoobs   = shift;
  my $ircChannel  = shift;
  my $string      = "";
  my $count       = 0;

  my %teamplayers = playerData::getPlayersByTeam($teamid);
  while ( my ( $id, $player ) = each ( %teamplayers ) )
  {
    my $recs = ( $showNoobs == 1 ) ? get_n00b($player->{'name'}) : get_recommendation($player->{'name'});
  
  
    $string .= " ".modules::padd_string(modules::parseModName($player->{'name'}, 1));

    if ( ++$count >= 5 )
    {
      players_outputTeam($teamid, $string);
      $count = 0;
      $string = "";
    }
  }
  
  players_outputTeam($teamid, $string) if ( $string ne "" );
}

# Worker function for the !teamplayers command
sub teamplayers_outputTeam
{
  my $teamid      = shift;
  my $string      = shift;
  my $showNoobs   = shift;
  my $ircChannel  = shift;
  
  
  $string = brTeams::colourise($teamid, brIRC::bold(brTeams::get_name($teamid).":").$string);
  brIRC::ircmsg($string, $ircChannel);
}




# --------------------------------------------------------------------------------------------------
##
#### Utility functions
##
# --------------------------------------------------------------------------------------------------

sub report_syntax_error
{
  my(%args) = @_;
  
  my $syntaxvalue = $args{'settings'}->{'syntax'}->{'value'};

  if ( $args{'nicktype'} == 1 ) { brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} ); }
  else { plugin::pagePlayer( $args{'nick'}, 'BRenBot', "Usage: $syntaxvalue" ); }
}




# --------------------------------------------------------------------------------------------------
##
#### Database configuration
##
# --------------------------------------------------------------------------------------------------

sub db_update
{
  # Note: BRenBot will update the database all the way up to the format that was used up to 1.54.13
  #       automatically for us, so we don't need to worry about it being any older than that

  $db_version = plugin::get_global ( "version_plugin_recommendations" );
  if ( defined($db_version) and $db_version > $currentVersion )
  {
    plugin::console_output("[Recommendations] The database has been modified by a newer version of"
        ." this plugin. To avoid potential data corruption the plugin will now stop");
    return 0;
  }

  # Current table definitions
  my %tables = {
    recommendations => "CREATE TABLE recommendations ( name TEXT PRIMARY KEY, recommendations INTEGER DEFAULT 0, n00bs INTEGER DEFAULT 0  )",
    recommendations_ignored_users => "CREATE TABLE recommendations_ignored_users ( name TEXT PRIMARY KEY )",
    recommendations_recent_history => "CREATE TABLE recommendations_recent_history ( timestamp INTEGER, recommender TEXT, recommendee TEXT, isN00b INTEGER, reason TEXT )"
  };

  # Check which tables already exist...
  my @db_tables = plugin::execute_query( "SELECT name FROM sqlite_master" );
  foreach ( @db_tables )
    { delete $tables{$_->{'name'}}; }

  # Create any missing tables
  while ( (my $table, my $definition) = each %tables )
  {
    plugin::console_output("[Recommendations] Creating missing table " . $table);
    plugin::execute_query( $definition, 1 );
    delete $tables{$table};
  }



  # Nothing to update at the moment...
  return 1;
}


# Plugin loaded OK
1;