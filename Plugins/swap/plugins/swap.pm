#**
# Allows two players on opposite teams to swap teams with mutual agreement
#
# \author Daniel Paul (danpaul88@yahoo.co.uk)
# \version 1.03
#*

package swap;

use POE;
use plugin;

my $currentVersion = '1.03';
my $loaded_ok = undef;

# Check bot compatibility
if ( !defined(plugin::getBrVersion) || plugin::getBrVersion() < 1.53
  || (plugin::getBrVersion() == 1.53 && plugin::getBrBuild() < 18 ) )
{
  print ' == Donate Plugin Error ==\n'
      . 'This version of the plugin is not compatible with BRenBot versions older than 1.53.18\n';
  return 0;
}

# --------------------------------------------------------------------------------------------------

# BRenBot supplies these on plugin startup
our $plugin_name;
our %config;

# Define additional events in the POE session
our %additional_events =
(
  'swap'        => 'swap',
  'swapcancel'  => 'swapcancel'
);

# Global variables
my $swapRequester = 0;




# --------------------------------------------------------------------------------------------------
##
#### Bot Events
##
# --------------------------------------------------------------------------------------------------

sub start
{
  plugin::set_global ("version_plugin_swap", $currentVersion);

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
  $_[KERNEL]->yield($args{'command'} => \%args);
}

sub playerleave
{
  my %args = %{@_[ ARG0 ]};

  # If leaver ID = swapRequester then shutdown swap
  if ($args{'id'} == $swapRequester)
  {
    $swapRequester = 0;
    plugin::serverMsg("$args{nick} has left the game, swap has been cancelled");
  }
}




# --------------------------------------------------------------------------------------------------
##
#### Commands
##
# --------------------------------------------------------------------------------------------------

# Function for !swap command, initiates a swap request or completes a swap if
# a request has been issued from a player on the other team
sub swap
{
  my %args = %{@_[ ARG0 ]};

  # Cannot be run from IRC
  return if ($args{'nicktype'} == 1);


  # Is there a swap in progress?
  if ( $swapRequester != 0 )
  {
    my ($result1, %player1) = plugin::getPlayerData($swapRequester);
    my ($result2, %player2) = plugin::getPlayerData($args{'nick'}, 1);

    if ($result1 != 1 or $result2 != 1)
    {
      plugin::serverMsg("Unable to complete swap, one or both players not found ingame!");
      return;
    }

    # Found both players, check they are not on the same team
    if ($player1{'teamid'} == $player2{'teamid'})
    {
      # Swapping with someone on your own team? Uh.... no!
      plugin::pagePlayer($player2{'id'}, "BRenBot", "You cannot swap teams with $player1{name}, they are on the same team as you!");
    }
    else
    {
      # Teams are different, so swap them
      plugin::RenRemCMD("team2 $player1{id} $player2{teamid}");
      plugin::RenRemCMD("team2 $player2{id} $player1{teamid}");
      plugin::serverMsg("$player1{name} and $player2{name} have swapped teams!");
      $swapRequester = 0;
    }
  }


  # Otherwise start a new swap
  else
  {
    my ($result, %player) = plugin::getPlayerData($args{'nick'}, 1);
    if ($result == 1)
    {
      $swapRequester = $player{'id'};
      plugin::serverMsg("$args{nick} would like to swap teams, type !swap to swap with them. 60 seconds remaining.");
      $args{'swapRequester'} = $swapRequester;
      @_[KERNEL]->alarm(swap_halftime => int(time()) + 30 => \%args);
    }
  }
}

# Function for !swapcancel - allows users or admins to cancel a swap
sub swapcancel
{
  my %args = %{@_[ ARG0 ]};

  if ($swapRequester == 0)
  {
    if ($args{'nicktype'} == 1)
      { plugin::ircmsg("There is no swap in progress", $args{'ircChannelCode'}); }
    else
      { plugin::pagePlayer($args{'nick'}, "There is no swap in progress"); }
    return;
  }


  # Cancel request from IRC... do they have permission?
  if ( $args{'nicktype'} == 1 )
  {
    my $ircPermissions = plugin::getIrcPermissions($args{'nick'}, $args{'ircChannelCode'});
    if ( $ircPermissions == 'irc_protected'
      || $ircPermissions == 'irc_founder'
      || ($ircPermissions == 'irc_op' && $config{'ircOpCanCancelSwaps'} == 1)
      || ($ircPermissions == 'irc_halfop' && $config{'ircHalfOpCanCancelSwaps'} == 1) )
    {
      # Cancel
      $swapRequester = 0;
      plugin::serverMsg("Swap was cancelled by $args{nick}");
    }
    else
    {
      # No permissions
      plugin::ircmsg("You do not have permission to cancel swap requests", $args{'ircChannelCode'});
    }
  }



  else
  {
    my ($result, %player) = plugin::getPlayerData($args{'nick'}, 1);
    if ($result == 1)
    {
      # Is the requester cancelling their own swap?
      if ($player{'id'} == $swapRequester)
      {
        $swapRequester = 0;
        plugin::serverMsg("$args{nick} cancelled their swap request");
      }

      else
      {
        # Otherwise do a permission check
        if ( plugin::isAdmin($args{'nick'} == 1)
          || (plugin::isFullMod($args{'nick'} == 1 && $config{'fullModCanCancelSwaps'} == 1))
          || (plugin::isHalfMod($args{'nick'} == 1 && $config{'halfModCanCancelSwaps'} == 1))
          || (plugin::isTempMod($args{'nick'} == 1 && $config{'tempModCanCancelSwaps'} == 1)) )
        {
          # Cancel
          $swapRequester = 0;
          plugin::serverMsg("Swap was cancelled by $args{nick}");
        }
        else
        {
          # No permissions
          plugin::pagePlayer($player{'id'}, "You do not have permission to cancel other players swap requests");
        }
      }
    }
  }
}




# --------------------------------------------------------------------------------------------------
##
#### Utility Functions
##
# --------------------------------------------------------------------------------------------------

# Triggers when 30 seconds are left on a !swap
sub swap_halftime
{
  my %args = %{@_[ ARG0 ]};

  # Show 30 seconds remaining message
  if ($args{'swapRequester'} == $swapRequester)
  {
    plugin::serverMsg("$args{nick} would like to swap teams, type !swap to swap with them. 30 seconds remaining.");
    @_[KERNEL]->alarm(swap_fulltime => int(time()) + 30 => \%args);
  }
}

# Triggers when 0 seconds are left on a !swap
sub swap_fulltime
{
  my %args = %{@_[ ARG0 ]};

  # Disable swap
  if ( $args{'swapRequester'} == $swapRequester )
  {
    plugin::serverMsg("60 seconds are up, swap request has timed out.");
    $swapRequester = 0;
  }
}


# Plugin loaded OK
1;