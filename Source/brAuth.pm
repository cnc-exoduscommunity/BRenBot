# brAuth.pm
#
# Functionality relating to the auth system in BRenBot

package brAuth;
use strict;

# Use third party modules
use POE;

# Use BRenBot modules
use modules;
use playerData;
use brIRC;




# Sets the authentication state of the given user to true
#
# PARAM		String		Player Name
#
# RETURN NULL
sub change_protected_status
{
	playerData::setKeyValue ( shift, "isAuthed", 1 );
}


# Checks if a user has been authorised
#
# PARAM		String		Player Name
#
# RETURN $return_value
# 0 = Not Authed
# 1 = Authed
# 2 = Not a protected user
sub is_user_authed
{
	my $nickname = shift;

	#print "auth check on $nickname...\n";

	my ( $result, %player ) = playerData::getPlayerData ( $nickname );
	if ( $result != 1 ) { return 0; }

	if ( defined ( $player{"isAuthed"} ) )
	{
		if ( $player{"isAuthed"} == 1 ) { return 1; }
		return 0;
	}

	elsif ( modules::user_exists( $nickname ) )
	{
		# If the user exists but is not setup in protected nicks
		# add them and return 0 -> not authed.
		playerData::setKeyValue ( $nickname, "isAuthed", 0 );
		warn_protected_nickname ( $nickname );		# Start warning them to auth
		return 0;
	}

	return 2;
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
					modules::RenRemCMD( "ppage $player{id} $name is a protected nickname. Please authenticate yourself within $time seconds, or you will be kicked." );
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