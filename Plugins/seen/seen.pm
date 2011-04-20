#
# Seen plugin for BRenBot 1.51 by Daniel Paul
# Based on the !seen command in BR 1.41 and earlier
#
# Version 1.04
#
package seen;

use POE;
use plugin;

sub CHANNEL () { plugin::get_irc_channel()  };

# define additional events in the POE session

our %additional_events =
(
	# !command functions
	"seen" => "seen",
	"clearSeen" => "clearSeen"
);

# BRenBot automatically sets the plugin name
our $plugin_name;

# BRenBot automatically imports the plugin's config (from the xml file) into %config
our %config;

our $dbh;						# Database connection
our $dbVersion;
our $currentVersion = 1.04;


########### Functions for !commands

# Function for displaying all current warnings for players in the server
sub seen
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};
	
	my $message;
	
	# Check they supplied a name to search for
	if ( !$args{arg1} )
	{
		my $syntaxvalue = $args{settings}->{syntax}->{value};
		$message = "Usage: $syntaxvalue";
	}
	else
	{
		my $playerInGame = 0;
		# Check if the player is in the game
		if ( $main::version >= 1.51 )
		{
			my ( $result, %player ) = plugin::getPlayerData( $args{arg1} );
			if ( $result == 1 )
			{
				$playerInGame = 0;
				if ( $player{'name'} eq $args{nick} )
					{ $message = "Go look in the mirror, $args{nick}."; }
				else
					{ $message = "$player{'name'} is right with you on this server!"; }
			}
		}
		else
		{
			my ( $result, $error, $player ) = plugin::PlayerInGame( $args{arg1} );
			if ( $result == 1 )
			{
				$playerInGame = 0;
				if ( $player->{'name'} eq $args{nick} )
					{ $message = "Go look in the mirror, $args{nick}."; }
				else
					{ $message = "$player->{'name'} is right with you on this server!"; }
			}
		}
		
		if ( !$playerInGame )
		{
			my ( $seen_result, $timestamp, $name ) = get_seen ( $args{arg1} );
			
			if ( $seen_result == 1 )
			{
				$message = "$name was last seen on this server ";
				my $difference = ( time() - $timestamp );
				
				# All calculations will assume a month = 30 days, and a year = 365 days
				my( $years, $months, $weeks, $days, $hours, $minutes ) = ( 0, 0, 0, 0, 0, 0 );
				
				while ( $difference > 30758400 )
				{ $difference -= 30758400; $years++; }
				if ( $years ) { $message .= "$years years "; }
				
				while ( $difference > 2592000 )
				{ $difference -= 2592000; $months++; }
				if ( $months ) { $message .= "$months months "; }
				
				while ( $difference > 604800 )
				{ $difference -= 604800; $weeks++; }
				if ( $weeks ) { $message .= "$weeks weeks "; }
				
				while ( $difference > 86400 )
				{ $difference -= 86400; $days++; }
				if ( $days ) { $message .= "$days days "; }
				
				while ( $difference > 3600 )
				{ $difference -= 3600; $hours++; }
				if ( $hours ) { $message .= "$hours hours "; }
				
				while ( $difference > 60 )
				{ $difference -= 60; $minutes++; }
				if ( $minutes ) { $message .= "$minutes minutes "; }
				
				if ( $message ne "$name was last seen on this server " )
				{
					$message .= "and $difference seconds ago";
				}
				else
				{
					$message .= "$difference seconds ago";
				}
			}
			
			elsif ( $seen_result == 2 )
			{
				$message = "More than one match found for \"$args{arg1}\". Please be more precise in your query!";
			}
			
			else
			{
				$message = "I do not recall seeing $args{arg1} here...";
			}
		}
	}
	
	# Output whatever message we now have
	if ( $args{nicktype} == 1 ) 
	{
		$kernel->post( IRC => privmsg => CHANNEL, "[BR] " . $message );
	}
	else
	{
		plugin::RenRemCMD( "msg [BR] " . $message );
	}
}


########### Event handlers

sub start
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};
	
	# Set our current version in the globals table
	plugin::set_global ( "version_plugin_seen", $currentVersion );
	
	# Connect to, and if necessary create, the database
	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$dbTime,$ctime,$blksize,$blocks) = stat( 'seen_plugin.dat' );
	
	if ( $^O eq "MSWin32" )
	{
		$dbh = DBI->connect("dbi:SQLite2:dbname=seen_plugin.dat","","");
	}
	else	# Use alternative SQLite driver for linux
	{
		$dbh = DBI->connect("dbi:SQLite:dbname=seen_plugin.dat","","");
	}
	
	if( !$dbTime )
	{
		print "SEEN PLUGIN :: Database does not exist, creating fresh database\n";
		
		$dbh->do(
			"CREATE TABLE seen
			(id				INT			PRIMARY KEY
			, name			CHAR(128)
			, timestamp		INT)"
		);
		
		
		$dbh->do(
			"CREATE TABLE globals
			(id				INT			PRIMARY KEY
			, name			TEXT
			, value			TEXT)"
		);
		
		
		$dbh->do( "INSERT INTO globals ( name, value ) VALUES ( 'version', '1' )" );
	}
	else
	{
		# No version checking needed, this is version 1.0 after all...
	}
}


sub stop
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	
	# Comamnds to run when BRenBot quits
	$dbh->disconnect;
	
}


sub command
{
	# trigger on !commands
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};
	
	# Any commands from IRC or ingame come here
	# From here we should trigger the appropriate subroutine
	if ( $args{command} eq "seen" )
	{
		$kernel->yield("seen" => \%args);
	}
}


sub playerjoin
{
	# Triggered when a player joins the game
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};
	
	# Record their nickname in the database
	updateTime ( $args{nick} );
}


sub playerleave
{
	# Triggered when a player leaves the game
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};
	
	# Record their nickname in the database
	updateTime ( $args{nick} );
}




########### Other Functions

# Function for greeting players when they join the server, if enabled
sub updateTime
{
	# Convert to lowercase and strip out any ""
	my $name = lc(shift);
	$name =~ s/"/\'/g;
	
	# Check if the record exists in the database
	my ($exists) = $dbh->selectrow_array ( "SELECT timestamp FROM seen WHERE name = \"$name\"" );
	
	if( $exists >= 1 )
	{
		# Update timestamp
		$dbh->do( "UPDATE seen SET timestamp = " . time() . " WHERE name = \"$name\"" );
	}
	else
	{
		# Create new record
		$dbh->do( "INSERT INTO seen ( timestamp, name ) VALUES ( " . time() . ", \"$name\" )" );
	}
}


# Function for getting the last time a specified player was seen
#
# PARAM		name		Full or partial name of player to find
#
# RETURN $result, $timestamp, $name
# 0 = Not found
# 1 = Found unique match
# 2 = Found multiple matches
sub get_seen
{
	# Convert to lowercase and strip out any ""
	my $name = lc(shift);
	$name =~ s/"/\'/g;

	
	my $results = $dbh->selectrow_array ( "SELECT COUNT(*) FROM seen WHERE lower(name) LIKE \"%$name%\"" );
	if ( $results == 1 )
	{
		my $query = $dbh->prepare ( "SELECT name, timestamp FROM seen WHERE lower(name) LIKE \"%$name%\"" );
		$query->execute();
		
		my @row = $query->fetchrow_array;
		return ( 1, $row[1], $row[0] );
	}
	elsif ( $results == 0 )
	{
		return 0;
	}
	else
	{
		my $query = $dbh->prepare ( "SELECT name, timestamp FROM seen WHERE lower(name) LIKE \"%$name%\"" );
		$query->execute();
		
		while ( my @row = $query->fetchrow_array )
		{
			if ( lc($row[0]) eq $name )
			{
				return ( 1, $row[1], $row[0] );
			}
		}
		return 2;
	}
}


# Return true or the bot will not work properly...
1;