#
# FDS Status Reporter plugin for BRenBot 1.51 by Daniel Paul
# Reports the status of the FDS to an FTP location automatically by
# uploading a .txt file. Processing the raw data is up to the website
#
# Version 1.04
#
package fds_status_reporter;

use POE;
use plugin;
use gamelog;
use Net::FTP;

sub CHANNEL () { plugin::get_irc_channel()  };

# define additional events in the POE session

our %additional_events =
(
	"updateStatus" => "updateStatus"
);

# BRenBot automatically sets the plugin name
our $plugin_name;

# BRenBot automatically imports the plugin's config (from the xml file) into %config
our %config;

my $pluginVersion = 1.04;



########### Event handlers

sub start
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};
	
	# Set our current version in the globals table
	plugin::set_global ( "version_plugin_fds_status_reporter", $pluginVersion );
	
	# Schedule the first upload for 15 seconds time (giving BRenBot plenty
	# of time to get the server status)
	my $next_time = int( time() ) + 15;
	$kernel->alarm( updateStatus => $next_time => \%args );
}


sub stop
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
}





########### Other Functions

# Main program function, updates the status file and then
# schedules the next update
sub updateStatus
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	
	## Update the data in the text file
	my $statusFile;
	if( open( $statusFile, ">./$config{'filename'}" ) )
	{
		if ( $main::version >= 1.51 )
		{
			my ( $serverMode, $currentMap, $gdiPlayers, $gdiPoints, $nodPlayers, $nodPoints, $currentPlayers, $maxPlayers, $timeRemaining, $sfps ) = plugin::getGameStatus();
			print $statusFile "$serverMode\n$currentMap\n$gdiPlayers\n$gdiPoints\n$nodPlayers\n$nodPoints\n$maxPlayers\n$timeRemaining\n$sfps\n";
			
			# Print data for each player
			my %playerlist = plugin::get_playerlist();
			while ( my ( $id, $player ) = each ( %playerlist ) )
			{
				print $statusFile "$player->{name}\t$player->{side}\t$player->{score}\t$player->{stats_kills}\t$player->{stats_deaths}\t$player->{ping}\t$player->{time}\n";
			}
		}
		else
		{
			my %gameinfo = plugin::get_gameinfo();
			print $statusFile "$gameinfo{mode}\n$gameinfo{map}\n$gameinfo{gdi_players}\n$gameinfo{gdi_points}\n$gameinfo{nod_players}\n$gameinfo{nod_points}\n$gameinfo{maxplayers}\n$gameinfo{timeleft}\n$gameinfo{sfps}\n";
			
			# Print data for each player
			my @playerList = plugin::get_playerlist();
			foreach $player ( @playerList )
			{
				my $playerstats = gamelog::get_playerstats ( $player->{name} );
				print $statusFile "$player->{name}\t$player->{side}\t$player->{score}\t$playerstats->{kills}\t$playerstats->{deaths}\t$player->{ping}\t$player->{time}\n";
			}
		}
		
		close $statusFile;
	}
	else
	{
		print "FDS STATUS PLUGIN :: Failed to open $config{'filename'}... aborting."
	}
	
	
	
	## Login to the FTP and upload our file
	my $ftp = Net::FTP->new( "$config{'ftpServer'}", Debug => 0 );
	if ( $ftp )
	{
		if ( $ftp->login( $config{'ftpUsername'},$config{'ftpPassword'} ) )
		{
			print "FDS STATUS PLUGIN :: FTP :: Login Successful\n";
			if ( $ftp->cwd( $config{'ftpPath'} ) )
			{
				# Upload the file
				if ( $ftp->put ( "./$config{'filename'}" ) )
				{
					print "FDS STATUS PLUGIN :: FTP :: File $config{'filename'} uploaded successful\n";
				}
				else
				{
					print "FDS STATUS PLUGIN :: FTP :: File $config{'filename'} upload failed!\n";
				}
			}
			else
			{
				print "FDS STATUS PLUGIN :: FTP :: Path '$config{ftpPath}' does not exist!\n";
			}
			
			$ftp->quit;
			print "FDS STATUS PLUGIN :: FTP :: Disconnected\n";
		}
		else
		{
			print "FDS STATUS PLUGIN :: FTP :: Login Failed\n";
		}
	}
	
	
	
	# Schedule the next update
	my $next_time = int( time() ) + ($config{'updateInterval'}*60);
	$kernel->alarm( updateStatus => $next_time => \%args );
}



# Return true or the plugin will not work properly...
1;