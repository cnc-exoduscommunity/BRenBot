# brAuth.pm
#
# Functionality relating to the auth system in BRenBot

package brAuth;
use strict;

# Use third party modules
use POE;
use Digest::MD5 qw(md5 md5_hex md5_base64);

# Use BRenBot modules
use modules;
use RenRem;
use playerData;
use brIRC;




# Sets the authentication state of the given player
#
# \param[in] $player
#   Name or ID of the player to set the authentication state of
# \param[in] $state
#   New authentication state
sub SetAuthState
{
	playerData::setKeyValue ( shift, "isAuthed", shift );
}


# Get the authentication state of the given player
#
# \param[in] $player
#   Name or ID of the player to set the authentication state of
#
# \return
#   Authentication state of the player, which is either 0 (not authenticated), 1 (authenticated) or
#   2 (not registered for authentication)
sub GetAuthState
{
	my ( $result, %player ) = playerData::getPlayerData ( shift );
	if ( $result != 1 ) { return 0; }

	if ( defined ( $player{"isAuthed"} ) )
	{
		if ( $player{"isAuthed"} == 1 ) { return 1; }
		return 0;
	}

	# If the isAuthed attribute does not exist then we need to create it
	elsif ( modules::user_exists( $player{'name'} ) )
	{
		# If the user exists but is not setup in protected nicks
		# add them and return 0 -> not authed.
		SetAuthState( $player{'id'}, 0 );
		warn_protected_nickname ( $player{'name'} );		# Start warning them to auth
		return 0;
	}

	return 2;
}


# Attempts to authenticate a player using the given password
#
# \param[in] $player
#   Name or ID of the player attempting to authenticate
# \param[in] $password
#   The password to try and authenticate against
#
# \return
#   Result of the authentication attempt, which is either 0 (failure, wrong password), 1 (success),
#   2 (already authenticated), 3 (not registered for authentication) or 4 (not found in playerlist)
sub AuthenticateByPassword
{
	my ( $result, %player ) = playerData::getPlayerData ( shift );
	if ( $result != 1 ) { return 4; }
		
	# Check password is correct
	if ( !CheckAuthPassword($player{'name'}, shift) )
		{ return 0; }
		
	return Authenticate($player{'id'});
}


# Checks the given nickname and password combination is valid - this can be used on players who are
# not currently ingame to allow aliases to be created etc
#
# \param[in] $player
#   Name of the player
# \param[in] $password
#   The password to try and authenticate against
#
# \return
#   1 if successful, 0 otherwise
sub CheckAuthPassword
{
	my $name = lc(shift);
	my $password = md5_hex(shift);
	
	# Make name safe for the database
	$name =~ s/'/''/g;
	
	# Attempt to authenticate
	my @array = brdatabase::execute_query( "SELECT * FROM auth_users WHERE LOWER(name) = '$name'" );
	return ( $array[0]->{'password'} eq $password ) ? 1 : 0;
}


# Authenticates the specified player
#
# \param[in]
#   Name or ID of the player to authenticate
#
# \return
#   Result of the authentication attempt, which is either 0 (not found in playerlist), 1 (success),
#   2 (already authenticated) or 3 (not registered for authentication)
sub Authenticate
{
	my ( $result, %player ) = playerData::getPlayerData ( shift );
	if ( $result != 1 ) { return 0; }

	# Already authenticated or not registered? Not much point in continuing then
	my $auth_state = GetAuthState($player{'id'});
	if ( $auth_state != 0 )
		{ return $auth_state+1; }
		
	# Process Authentication
	SetAuthState( $player{'id'}, 1 );
	main::ShowModJoinMessage( $player{'name'} );
	return 1;
}



# Starts the 60 second countdown in which a user must auth, or they will be kicked.
#
# This will NOT check the user's auth status, so should only be called when we are
# sure they are not already authed, although it will not kick them if they were
# already authed before it started.
#
# PARAM		String		Player Name
#
# RETURN NULL
sub warn_protected_nickname
{
	my $nickname = shift;

	# Now start the thread to check them
	POE::Session->create
	( inline_states =>
		{
			_start => sub
			{
				# Wait 10 seconds before sending the first message
				# This gives RG a chance to !auth them before it starts paging them
				$_[HEAP]->{next_alarm_time} = int( time() ) + 10;
				$_[KERNEL]->alarm( tick => $_[HEAP]->{next_alarm_time} );

				$_[HEAP]->{name} = $nickname;
				$_[HEAP]->{time} = 60;
			},
			tick => sub
			{
				my ( $kernel, $session, $heap ) = @_[ KERNEL, SESSION, HEAP ];

				my $name = $heap->{name};
				my $time = $heap->{time};

				# Check they are still in the game
				my ( $result, %player ) = playerData::getPlayerData( $name );
				if ( $result != 1 ) { return; }


				if ( $time > 0 && $player{"isAuthed"} != 1  )
				{
					# Send them a page to remind them they need to !auth
					modules::pagePlayer ( $player{'id'}, "BRenBot", "$name is a protected nickname. Please authenticate yourself within $time seconds, or you will be kicked." );
					brIRC::ircmsg ( "9Page sent to $name --> $name is a protected nickname. Please authenticate yourself within $time seconds, or you will be kicked.", "A" );

					$_[HEAP]->{time} = ( $time - 20 );
					$_[HEAP]->{next_alarm_time} = int( time() ) + 20;
					$_[KERNEL]->alarm( tick => $_[HEAP]->{next_alarm_time} );
				}
				elsif ( $time == 0 && $player{"isAuthed"} != 1 )
				{
					modules::kick_player ( $player{'id'}, 'BRenBot', 'Unauthorized use of a protected nickname' );
				}
			}
		}
	);
}


# Return true
1;