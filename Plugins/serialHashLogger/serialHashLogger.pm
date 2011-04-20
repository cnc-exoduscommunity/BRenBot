#
# Serial Hash Logger plugin for BRenBot 1.52 by Daniel Paul
#
# Logs serial hashes for players automatically in the database, and
# also provides notifications when a user's hash changes frequently
#
# Version 1.01
#
package serialHashLogger;

use POE;
use plugin;
use modules;		# get_past_date_time

sub CHANNEL () { plugin::get_irc_channel()  };

# define additional events in the POE session

our %additional_events =
(
	# !command functions
	"findserials" => "findSerials"
);

# BRenBot automatically sets the plugin name
our $plugin_name;

# BRenBot automatically imports the plugin's config (from the xml file) into %config
our %config;
our $currentVersion = 1.01;


########### Functions for !commands

# Function for displaying all current warnings for players in the server
sub findSerials
{
	my %args = %{@_[ ARG0 ]};
	
	if ( $args{'nicktype'} != 1 )
		{ return; }
	
	# Get command user string (trim the @IRC off)
	my $ircnick = $args{'nick'};
	$ircnick =~ s/\@IRC//gi;
	
	# Check they supplied a name to search for
	if ( !$args{arg1} )
	{
		my $syntaxvalue = $args{settings}->{syntax}->{value};
		plugin::ircnotice ( $ircnick, "Usage: $syntaxvalue" );
	}
	else
	{
		# Get target name (might contain spaces)
		$args{'arg'} =~ m/^\!\S+\s(.+)$/i;
		my $playername = $1;
		
		# Search database for serials the specified player has used
		my @results = plugin::execute_query ( "SELECT serial, seenCount, lastSeen FROM serialHashLog WHERE LOWER(name) = '".lc($playername)."'" );
		
		# If no results were show no results message
		if ( scalar(@results) == 0 )
			{ plugin::ircnotice ( $ircnick, "No serial logs were found for $playername." ); }
		
		# Otherwise print results
		else
		{
			if ( scalar(@results) > 8 )
				{ plugin::ircnotice ( $ircnick, "Found ".scalar(@results)." results for $playername, showing first 8" ); }
			else
				{ plugin::ircnotice ( $ircnick, "Found ".scalar(@results)." results for $playername, showing all results" ); }
			
			
			# Create output format string
			my $format = "%-15s %-15s %s";
			
			# Print results header
			my $line = sprintf ( $format, "Times Used", "Last Used", "Serial Hash" );
			plugin::ircnotice ( $ircnick, "1,15$line" );
			
			# Now print out up to 8 results
			for ( my $i = 0; $i < 8 && $i < scalar(@results); $i++ )
			{
				my $lastSeen = modules::get_past_date_time( "MM/DD/YYYY", $results[$i]->{'lastSeen'} );
				$line = sprintf ( $format, $results[$i]->{'seenCount'}, $lastSeen, $results[$i]->{'serial'} );
				plugin::ircnotice ( $ircnick, $line );
			}
		}
	}
}


########### Event handlers

# Runs when BRenBot is loaded
sub start
{
	my %args = %{@_[ ARG0 ]};
	
	# Set our current version in the globals table
	plugin::set_global ( "version_plugin_serialHashLogger", $currentVersion );
	
	# Create database table if it does not exist
	my @result = plugin::execute_query( "SELECT * FROM sqlite_master WHERE name = 'serialHashLog'" );
	if ( scalar(@result) == 0 )
		{ plugin::execute_query ( "CREATE TABLE serialHashLog ( id INTEGER PRIMARY KEY, name TEXT, serial TEXT, seenCount INTEGER DEFAULT 0, lastSeen INTEGER DEFAULT 0)" ); }
}


# Runs when BRenBot is shutdown
sub stop
{	
}


# Runs when one of this plugins commands is used
sub command
{
	my $kernel = @_[KERNEL];
	my %args = %{@_[ ARG0 ]};
	$kernel->yield( $args{'command'} => \%args );
}


sub playerjoin
{
	my $kernel = @_[KERNEL];
	my %args = %{@_[ ARG0 ]};
	
	# Start timer to check their serial in 5 seconds (give RG servers
	# time to respond)
	$kernel->alarm( logSerial => int(time())+5 => \%args );
}




########### Other Functions

# Logs the specified players serial if it exists
sub logSerial
{
	my %args = %{@_[ ARG0 ]};
	
	# Search for player ingame
	my ( $result, %player ) = plugin::getPlayerData( $playername );
	if ( $result == 1 && $player{'serial'} )
	{
		# Check if this serial exists in the database
		my @result = plugin::execute_query ( "SELECT id FROM serialHashLog WHERE LOWER(name) = '".lc($player{'name'})."' AND serial = '".$player{'serial'}."'" );
		
		# Update database entry if they have used this serial hash before
		if ( scalar(@result) > 0 )
			{ plugin::execute_query ( "UPDATE serialHashLog SET seenCount = seenCount+1, lastSeen = ".time()." WHERE id = ".$result[0]->{'id'} ); }
		
		# Otherwise create new database entry
		else
			{ plugin::execute_query ( "INSERT INTO serialHashLog ( name, serial, seenCount, lastSeen ) VALUES ( '".$player{'name'}."', '".$player{'serial'}."', 1, ".time()." )" ); }
		
		
		
		# Check for an excessive number of different serials within the last month (3 within 30 days)
		my @result2 = plugin::execute_query ( "SELECT COUNT(*) FROM serialHashLog WHERE LOWER(name) = '".lc($player{'name'})."' AND lastSeen >= ".time()-2592000 );
		if ( scalar(@result2) >= 3 )
			{ plugin::ircmsg ( "05WARNING: Player ".$player{'name'}." has used more 3 or more different serials in the last month, they may be cheating!", 'A' ); }
	}
}


# Return true or the bot will not work properly...
1;