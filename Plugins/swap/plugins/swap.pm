#
# Swap plugin for BRenBot by Daniel Paul
# Allows two players on opposite teams to swap teams with mutual agreement
#
# Version 1.02
#
package swap;

use POE;
use plugin;

# Define additional events in the POE session
our %additional_events =
(
  # !command functions
  "swap" => "swap",
  "swapcancel" => "swapcancel"
);


# Setup variables
our $plugin_name;   # BRenBot automatically sets the plugin name
our %config;        # BRenBot automatically imports the plugin's config (from the xml file) into %config
our $currentVersion = 1.02;

# Functional variables
my $swapRequester = 0;



################################
# Event Functions
#
# Functions for events
################################

# Start event - Triggered on bot startup
sub start()
{
	plugin::set_global ( "version_plugin_swap", $currentVersion );
}

# Stop event - Triggered on bot shutdown
sub stop(){}

# Command event - Triggers on any !command which is in this plugins XML file
sub command
{
	my %args = %{@_[ ARG0 ]};
	
	# Trigger the event with the same name as the command
	@_[KERNEL]->yield ( $args{'command'} => \%args );
}

# Playerleave event - Triggers when a player leaves the game
sub playerleave
{
	my %args = %{@_[ ARG0 ]};
	
	# If leaver ID = swapRequester then shutdown swap
	if ( $args{'id'} == $swapRequester )
	{
		$swapRequester = 0;
		plugin::serverMsg( "$args{nick} has left the game, swap has been cancelled" );
	}
}






################################
# Command Functions
#
# Functions for each !command
################################

# Function for !swap command, initiates a swap request or completes a swap if
# a request has been issued from a player on the other team
sub swap
{
	my %args = %{@_[ ARG0 ]};
	
	# Cannot be run from IRC
	if ( $args{nicktype} == 1 )
		{ return; }
	
	
	# Is there a swap in progress?
	if ( $swapRequester != 0 )
	{
		my ( $result1, %player1 ) = plugin::getPlayerData( $swapRequester );
		my ( $result2, %player2 ) = plugin::getPlayerData( $args{'nick'}, 1 );
		
		if ( $result1 == 1 and $result2 == 1 )
		{
			# Found both players, check they are not on the same team
			my $team1 = ($player1{'side'} eq "GDI" || $player1{'side'} eq "All") ? 1 : 0;
			my $team2 = ($player2{'side'} eq "GDI" || $player2{'side'} eq "All") ? 1 : 0;
			
			# Are they on the same team?
			if ( $team1 == $team2 )
			{
				# Swapping with someone on your own team? Uh.... no!
				plugin::pagePlayer ( $player2{'id'}, "BRenBot", "You cannot swap teams with $player1{name}, they are on the same team as you!" );
			}
			else
			{
				# Teams are different, so swap them
				plugin::RenRemCMD ( "team2 $player1{id} $team2" );
				plugin::RenRemCMD ( "team2 $player2{id} $team1" );
				plugin::serverMsg( "$player1{name} and $player2{name} have swapped teams!" );
				$swapRequester = 0;
			}
		}
		else
		{
			plugin::serverMsg( "Unable to complete swap, one or both players not found ingame!" );
		}
	}
	
	
	
	# Otherwise start a new swap
	else
	{
		my ( $result, %player ) = plugin::getPlayerData( $args{'nick'}, 1 );
		if ( $result == 1 )
		{
			$swapRequester = $player{'id'};
			plugin::serverMsg( "$args{nick} would like to swap teams, type !swap to swap with them. 60 seconds remaining." );
			$args{'swapRequester'} = $swapRequester;
			@_[KERNEL]->alarm( swap_halftime => int(time()) + 30 => \%args );
		}
	}
}

# Function for !swapcancel - allows users or admins to cancel a swap
sub swapcancel
{
	my %args = %{@_[ ARG0 ]};
	
	if ( $swapRequester == 0 )
	{
		if ( $args{nicktype} == 1 ) { plugin::ircmsg ( "There is no swap in progress", $args{'ircChannelCode'} ); }
		else { plugin::pagePlayer ( $args{'nick'}, "There is no swap in progress" ); }
		return;
	}
	
		
	# Cancel request from IRC... do they have permission?
	if ( $args{nicktype} == 1 )
	{
		my $ircPermissions = plugin::getIrcPermissions ( $args{'nick'}, $args{'ircChannelCode'} );
		if ( $ircPermissions == 'irc_protected'
			|| $ircPermissions == 'irc_founder'
			|| ($ircPermissions == 'irc_op' && $config{'ircOpCanCancelSwaps'} == 1)
			|| ($ircPermissions == 'irc_halfop' && $config{'ircHalfOpCanCancelSwaps'} == 1) )
		{
			# Cancel
			$swapRequester = 0;
			plugin::serverMsg ( "Swap was cancelled by $args{nick}" );
		}
		else
		{
			# No permissions
			plugin::ircmsg ( "You do not have permission to cancel swap requests", $args{'ircChannelCode'} );
		}
	}
	
	
	else
	{
		my ( $result, %player ) = plugin::getPlayerData( $args{'nick'}, 1 );
		if ( $result == 1 )
		{
			# Is the requester cancelling their own swap?
			if ( $player{'id'} == $swapRequester )
			{
				$swapRequester = 0;
				plugin::serverMsg ( "$args{nick} cancelled their swap request" );
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
					plugin::serverMsg ( "Swap was cancelled by $args{nick}" );
				}
				else
				{
					# No permissions
					plugin::pagePlayer ( $player{'id'}, "You do not have permission to cancel other players swap requests" );
				}
			}
		}
	}
}




########### Other Functions

# Triggers when 30 seconds are left on a !swap
sub swap_halftime
{
	my %args = %{@_[ ARG0 ]};
	
	# Show 30 seconds remaining message
	if ( $args{'swapRequester'} == $swapRequester )
	{
		plugin::serverMsg( "$args{nick} would like to swap teams, type !swap to swap with them. 30 seconds remaining." );
		@_[KERNEL]->alarm( swap_fulltime => int(time()) + 30 => \%args );
	}
}

# Triggers when 0 seconds are left on a !swap
sub swap_fulltime
{
	my %args = %{@_[ ARG0 ]};
	
	# Disable swap
	if ( $args{'swapRequester'} == $swapRequester )
	{
		plugin::serverMsg( "60 seconds are up, swap request has timed out." );
		$swapRequester = 0;
	}
}


# Return true or the bot will not work properly...
1;