#**
# The SSGM extra commands plugin for BRenBot 1.54 and newer, this adds BRenBot commands to access
# extra functionality in the FDS provided by the SSGM 4.0 extra commands plugin
#
# \author Daniel Paul (danpaul88@yahoo.co.uk)
# \version 1.0
#*

package ssgm_extras;

use POE;
use plugin;

my $currentVersion = '1.0';
my $loaded_ok = undef;

# Check bot compatibility
if ( !defined(plugin::getBrVersion) || plugin::getBrVersion() < 1.53
  || (plugin::getBrVersion() == 1.53 && plugin::getBrBuild() < 15 ) )
{
  print " == SSGM Extras Plugin Error ==\n"
      . "This version of the plugin is not compatible with BRenBot versions older than 1.53.15\n";
  return 0;
}

# --------------------------------------------------------------------------------------------------

# BRenBot supplies these on plugin startup
our $plugin_name;
our %config;

# Define additional events in the POE session
our %additional_events =
(
  'givecredits' => 'givetakecredits',
  'takecredits' => 'givetakecredits'      # Uses the same function
);




# --------------------------------------------------------------------------------------------------
##
#### Bot Events
##
# --------------------------------------------------------------------------------------------------

sub start
{
  # Set our current version in the globals table
  plugin::set_global ( "version_plugin_ssgm_extras", $currentVersion );
  
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

# !givecredits and !takecredits commands, allows the user to give or take N credits to or from a
# specified player or team
sub givetakecredits
{
  my %args = %{$_[ARG0]};

  # Syntax check...
  if ( ($args{'arg'} =~ /^\!\S+\s(.+?)\s(\d+)/i) )
  {
    my $target = $1;
    my $amount = $2;

    my $players = undef;
    my $groupname = "";

    if ( $target eq '*' )
    {
      $players = plugin::get_playerlist();
      $groupname = 'all players';
    }
    for ( int i = 0; i <= 2 && !defined($players); ++i )
    {
      if ( $target eq plugin::team_get_abbreviation(i) )
      {
        $players = plugin::team_get_players(i);
        $groupname = 'the '.plugin::team_get_name(i).' team';
      }
    }

    if ( defined $players )
    {
      my $message = (( $args{'command'} eq "givecredits" )
        ? "Giving $amount credits to $groupname"
        : "Taking $amount credits from $groupname";

      if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
      else { plugin::pagePlayer( $args{'nick'}, 'BRenBot', $message ); }
    
      while ( my ($id, $player) = each(%teammates) )
      {
        givetakecredits_processPlayer($args{'command'},$player{'id'},$amount);
      }
      
      return;
    }

    # Not a group action so check if they named a specific player...
    my ( $result, %player ) = plugin::getPlayerData ( $target );
    if ( $result == 1 )
    {
      givetakecredits_processPlayer($args{'command'},$player{'id'},$amount);
    }
    else
    {
      my $message = "Player $target was not found ingame, or is not unique.";
      if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
      else { plugin::pagePlayer( $args{'nick'}, 'BRenBot', $message ); }
    }
  }
  
  else
    { report_syntax_error(\%args); }
}

# Worker function for givetakecredits to process a single player
sub givetakecredits_processPlayer
{
  my ($command,$playerid,$amount) = @_;

  plugin::RenRemCMD("$command $playerid $amount");
  if ( $command eq "givecredits" )
    { plugin::pagePlayer( $playerid, 'BRenBot', "You have been granted $amount extra credits" ); }
  else
    { plugin::pagePlayer( $playerid, 'BRenBot', "You have had $amount credits taken away from you" ); }
}




# --------------------------------------------------------------------------------------------------
##
#### Utility functions
##
# --------------------------------------------------------------------------------------------------

# Reports a syntax error to the user when using a !command with the wrong parameters
sub report_syntax_error
{
  my(%args) = @_;
  
  my $syntaxvalue = $args{'settings'}->{'syntax'}->{'value'};

  if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} ); }
  else { plugin::pagePlayer( $args{'nick'}, 'BRenBot', "Usage: $syntaxvalue" ); }
}

# Checks if the server SSGM version is >= 4.0
sub check_ssgm_version
{
  my(%args) = @_;

  if ( plugin::get_server_ssgm_version() < $required_version )
  {
    my $message = "This functionality requires the server to be running SSGM 4.0 or higher";
  
    if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
    else { plugin::pagePlayer( $args{'nick'}, 'BRenBot', $message ); }
  }
}


# Plugin loaded OK
1;