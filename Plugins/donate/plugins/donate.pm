#**
# This plugin contains the donate functionality that used to exist in BRenBot prior to version
# 1.53.15. It allows players to donate some of their credits to a specific team member or to all
# players on their team in equal portions.
#
# \author Daniel Paul (danpaul88@yahoo.co.uk)
# \version 1.02
#*

package donate;

use POE;
use plugin;

my $currentVersion = '1.02';
my $loaded_ok = undef;

# Check bot compatibility
if ( !defined(plugin::getBrVersion) || plugin::getBrVersion() < 1.53
  || (plugin::getBrVersion() == 1.53 && plugin::getBrBuild() < 15 ) )
{
  print ' == Donate Plugin Error ==\n'
      . 'This version of the plugin is not compatible with BRenBot versions older than 1.53.15\n';
  return 0;
}

# --------------------------------------------------------------------------------------------------

# BRenBot supplies these on plugin startup
our $plugin_name;
our %config;

# Define additional events in the POE session
our %additional_events =
(
  'donate'      => 'donate',
  'teamdonate'  => 'teamdonate'
);

# Forward declarations
sub check_donate_limit($);




# --------------------------------------------------------------------------------------------------
##
#### Bot Events
##
# --------------------------------------------------------------------------------------------------

sub start
{
  # Set our current version in the globals table
  plugin::set_global ( 'version_plugin_donate', $currentVersion );

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

sub command
{
  return if ($loaded_ok == 0);

  my %args = %{$_[ARG0]};
  $_[KERNEL]->yield ( $args{'command'} => \%args );
}




# --------------------------------------------------------------------------------------------------
##
#### Commands
##
# --------------------------------------------------------------------------------------------------

# !donate command - Gives x amount of a players money to a specified teammate
sub donate
{
  my %args = %{$_[ ARG0 ]};

  # Can only be used by a player in the game, not from a plugin or by IRC users
  if ( $args{'nicktype'} != 0 )
  {
    if ( $args{'nicktype'} == 2 )
      { brIRC::ircmsg( 'You need to be ingame to use this command.', $args{'ircChannelCode'} ); }
    return;
  }

  if ( plugin::get_server_ssgm_version() < 2 )
  {
    plugin::pagePlayer( $args{'nick'}, 'BRenBot', 'Donations are not supported on this server' );
    return;
  }

  # Check syntax, get arguments
  my ($teammate,$credits);
  if ( $args{'arg'} =~ m/^\!\S+\s(.+)\s(\d+)$/i )
  {
    $teammate = $1;
    $credits  = $2;
  }
  else
  {
    show_syntax_error(@_);
    return;
  }

  # Check donation requirements...
  my ($result1, %donator) = playerData::getPlayerData($args{'nick'}, 1);
  return if ($result1 != 1);

  my ($result2, %donatee) = playerData::getPlayerData($teammate);
  if ($result2 != 1)
  {
    modules::pagePlayer( $donator{'id'}, 'BRenBot', $teammate.' was not found in the server or is not unique' );
    return;
  }

  if ( $donator{'id'} == $donatee{'id'} )
  {
    modules::pagePlayer( $donator{'id'}, 'BRenBot', 'You cannot donate money to yourself' );
    return;
  }

  if ( $donator{'teamid'} != $donatee{'teamid'} )
  {
    modules::pagePlayer( $donator{'id'}, 'BRenBot', 'You can only donate money to players on your own team' );
    return;
  }

  if ( $credits < 1 )
  {
    modules::pagePlayer( $donator{'id'}, 'BRenBot', 'You cannot donate negative money' );
    return;
  }

  # Do we care about this one anymore? It caused nothing but problems in the past...
  #if ( !gamelog::isPlayerLoaded( $donatee{'name'} ) )
  #{
  #  modules::pagePlayer( $donatee{'id'}, "BRenBot", "$donatee{name} has not done with loading this map yet.");
  #}

  # Check for a donation limit on the current map
  return if !check_donate_limit($donator{'id'});


  # OK, passed all the checks, go ahead and do the donation!
  plugin::pagePlayer( $donator{'id'}, 'BRenBot', "You have donated $credits credits to $donatee{name}!" );
  plugin::pagePlayer( $donatee{'id'}, 'BRenBot', "$donator{name} has donated $credits to you!" );
  plugin::RenRemCMD( "donate $donator{id} $donatee{id} $credits" );
}


# !teamdonate command - Gives x amount of a players money to their teammates in equal portions
sub teamdonate
{
  my %args = %{$_[ ARG0 ]};

  # Can only be used by a player in the game, not from a plugin or by IRC users
  if ( $args{'nicktype'} != 0 )
  {
    if ( $args{'nicktype'} == 2 )
      { brIRC::ircmsg( 'You need to be ingame to use this command.', $args{'ircChannelCode'} ); }
    return;
  }

  if ( plugin::get_server_ssgm_version() < 2 )
  {
    plugin::pagePlayer( $args{'nick'}, 'BRenBot', 'Donations are not supported on this server' );
    return;
  }

  # Check syntax, get arguments
  if ( !$args{'arg1'} || $args{'arg1'} !~ m/^\d+$/ )
  {
    show_syntax_error(@_);
    return;
  }

  my $credits = $args{'arg1'};

  # Check donation requirements...
  my ($result1, %donator) = playerData::getPlayerData( $args{'nick'}, 1 );
  return if ( $result1 != 1 );

  if ( $credits < 1 )
  {
    modules::pagePlayer( $donator{'id'}, 'BRenBot', 'You cannot donate negative money' );
    return;
  }

  # Check for a donation limit on the current map
  return if !check_donate_limit($donator{'id'});

  # OK, passed all the checks, go ahead and do the donations!
  my %teammates = plugin::team_get_players($donator{'teamid'});
  my $creditsPerTeammate = int($credits / ((scalar keys %teammates) -1));
  while ( my ($id, $donatee) = each(%teammates) )
  {
    next if ( $donator{'id'} == $donatee->{'id'} );
    plugin::pagePlayer( $donatee->{'id'}, 'BRenBot', "$donator{name} has donated $creditsPerTeammate to you!" );
    plugin::RenRemCMD( "donate $donator{id} $donatee->{id} $creditsPerTeammate" );
  }

  # Actual total donations might be lower if the figure didn't divide nicely between players...
  $credits = $creditsPerTeammate * ((scalar keys %teammates) -1);
  plugin::pagePlayer( $donator{'id'}, 'BRenBot', "You have donated $credits credits to your team!" );
}




# --------------------------------------------------------------------------------------------------
##
#### Utility Functions
##
# --------------------------------------------------------------------------------------------------

sub check_donate_limit($)
{
  my $donator_id = shift;

  my $donatelimit = plugin::get_map_setting('donatelimit');
  my $maptime = time()-plugin::get_map_start_time();
  if ( $donatelimit != 0 && $maptime < $donatelimit*60)
  {
    my $remaining = $donatelimit - int($maptime/60);
    modules::pagePlayer( $donator_id, 'BRenBot', 'Donations are not allowed on '.plugin::get_map()." in the first $donatelimit minutes. You have to wait $remaining more minutes" );
    return 0;
  }

  return 1;
}

sub show_syntax_error()
{
  my %args = %{$_[ ARG0 ]};
  my $syntax = 'Usage: '.$args{'settings'}->{'syntax'}->{'value'};

  if ( $args{'nicktype'} == 0 )
    { plugin::pagePlayer( $args{'nick'}, 'BRenBot', $syntax ); }
  elsif ( $args{'nicktype'} == 1 )
    { plugin::ircmsg( $syntax, $args{'ircChannelCode'} ); }
  else
    { plugin::console_output('A plugin used incorrect command syntax for '.$args{'command'}); }
}


# Plugin loaded OK
1;