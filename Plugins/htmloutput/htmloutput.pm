#
# Seen plugin for BRenBot 1.51 by Daniel Paul
# Based on the htmloutput module in BR 1.41 and earlier
#
# Version 1.03
#
package htmloutput;

use POE;
use plugin;

sub CHANNEL () { plugin::get_irc_channel()  };

# Define additional events in the POE session
our %additional_events =
(
	# Timer events
	"check_gameinfo" => "check_gameinfo",

	# Renlog regex hook events
	"hostMsg" => "hostMsg",
	"vehiclePurchase" => "vehiclePurchase",
	"playerKicked" => "playerKicked",
	"buildingKilled" => "buildingKilled",
	"playerKilled" => "playerKilled",
	"1" => "1",
);

# BRenBot automatically sets the plugin name
our $plugin_name;

# BRenBot automatically imports the plugin's config (from the xml file) into %config
our %config;

my $pluginVersion = 1.03;

# Current logfile
my $currentLogFile;
my $currentMap;
our @output_buffer;		# When the bot is starting up we might have to use the buffer while we wait for the map name




########### Event handlers

sub start
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};
	
	# Set our current version in the globals table
	plugin::set_global ( "version_plugin_htmloutput", $pluginVersion );
	
	# Wait 5 seconds before checking the gameinfo, otherwise we may
	# get the wrong map name...
	my $next_time = int( time() ) + 5;
	$kernel->alarm( check_gameinfo => $next_time => \%args );
	return;
}


# If the start sub did not get any data from get_gameinfo it will set an alarm to come here
sub check_gameinfo
{
	my $kernel = $_[KERNEL];
	
	my $currentMap;
	if ( $main::version >= 1.51 )
		{ ( undef, $currentMap, undef, undef, undef, undef, undef, undef, undef, undef ) = plugin::getGameStatus(); }
	else
		{ $currentMap = $gameinfo{'map'}; }
	
	# If there was no gameinfo schedule another check...
	if ( $currentMap eq "last round" || $currentMap eq "" )
	{
		my $next_time = int( time() ) + 60;
		$kernel->alarm( check_gameinfo => $next_time => \%args );
	}
	else
	{
		# If the gameinfo hash was retrieved work out if we are resuming a logfile
		# or starting a new one
		$currentMap =~ s/\.mix$//i;
		
		# Get the name of the last logfile we were using...
		my $lastlog = plugin::get_global ( "htmloutput_logfilename" );
		
		if ( $lastlog )
		{
			$lastlog =~ m/^(\d?\d)-(\d?\d)-\d?\d_(\d?\d)-\d?\d-\d?\d_(.+)$/i;
			my $lastlog_day = $1;
			my $lastlog_month = $2;
			my $lastlog_hour = $3;
			my $lastlog_map = $4;
			
			my $current_day = plugin::get_date_time( "DD" );
			my $current_month = plugin::get_date_time( "MM" );
			my $current_hour = plugin::get_date_time( "hh" );
			
			if ( $lastlog_map eq $currentMap
				&& $lastlog_day == $current_day
				&& $lastlog_month == $current_month
				&& ( ( $current_hour - $lastlog_hour ) >= 0 )
				&& ( ( $current_hour - $lastlog_hour ) < 2 ) )
			{
				# Resume existing log
				$currentLogFile = $lastlog;
				my $logResumed = plugin::get_date_time( "hh:mm:ss on DD-MM-YY" );
				fileWrite ( "<br>\n<br>\n<br>\n<b>BRenBot restarted, resuming log at $logResumed</b>", 1 );
			}
			else
			{
				# Close old logfile
				close_logfile($lastlog);
				
				# Start new log
				my $logtime = plugin::get_date_time( "DD-MM-YY_hh-mm-ss" );
			
				$currentLogFile = $logtime . '_' . $currentMap;
				start_logfile();
			}
		}
		else
		{
			my $logtime = plugin::get_date_time( "DD-MM-YY_hh-mm-ss" );
			
			$currentLogFile = $logtime . '_' . $currentMap;
			start_logfile();
		}
	}
}


sub stop
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};
	
	my $logSuspended = plugin::get_date_time( "hh:mm:ss on DD-MM-YY" );
	fileWrite ( "<br>\n<b>BRenBot shutting down, log suspended at $logSuspended</b>", 0, 1 );
}

sub mapload
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};
	
	my $oldLogFile = $currentLogFile;
	my $logtime = plugin::get_date_time( "DD-MM-YY_hh-mm-ss" );
	
	$currentMap = $args{map};
	$currentMap =~ s/\.mix//i;
	
	$currentLogFile = $logtime . '_' . $currentMap;
	start_logfile();
	
	close_logfile($oldLogFile);
}

sub playerjoin
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};
	
	fileWrite ( "<font color=blue><b>$args{nick}</b> joined the game</font>" );
}

sub playerleave
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};
	
	fileWrite ( "<font color=blue><b>$args{nick}</b> left the game</font>" );
}


sub changeteam
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};
	
	fileWrite ( "<font color=blue><b>$args{nick}</b> changed from $args{oldteam} to $args{newteam}</font>" );
}

sub text
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};
	
	# Ignore messages in IRC..
	if ( $args{nicktype} == 1 )
	{ return; }
	
	my $prefix;
	if ( $args{messagetype} eq "team" )
	{ $prefix .= "<font color=purple><i>[TEAM]</i></font> &nbsp;"; }
	
	if ( $args{team} eq "GDI" || $args{team} eq "All" )
	{ $prefix .= "<font color=yellow>"; }
	else
	{ $prefix .= "<font color=red>"; }
	
	fileWrite ( "$prefix<b>$args{nick}</b>: $args{message}</font>" );
}



########### Gamelog regex hook handler

# Handles buildings being killed
sub buildingKilled
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my $line = $args->{line};
	
	$line =~ m/KILLED;BUILDING;\d+;([^;]+);/gi;
	
	my $building = plugin::translatePreset($1);
	
	fileWrite ( "$building was destroyed." );
}

# Handles players being killed
sub playerKilled
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my $line = $args->{line};
	
	$line =~ m/KILLED;SOLDIER;(\d+);.+;(\d+);([^;]+);-?\d+;-?\d+;-?\d+;-?\d+;-?\d+/gi;
	
	my $killedName = plugin::getPlayerFromObjectID($1);
	my $killerName = plugin::getPlayerFromObjectID($2);
	
	if ( !$killerName )
	{
		# If the second ID is not a player's ID it might be a base defense, so
		# try and translate it's name
		$killerName = plugin::translatePreset($3);
	}
	
	if ( $killedName && $killerName )
	{
		fileWrite ( "$killedName was killed by $killerName." );
	}
}




########### Renlog regex hook handlers

# Handles host messages
sub hostMsg
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my $line = $args->{line};
	
	fileWrite ( "<font color=gray>$line</font>" );
}

# Handles vehicle purchases
sub vehiclePurchase
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my $line = $args->{line};
	
	fileWrite ( "<font color=green>$line</font>" );
}

# Handles players being kicked from the game
sub playerKicked
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my $line = $args->{line};
	
	fileWrite ( "<font color=blue>$line</font>" );
}







########### File writing routines

# Writes data to the logfile
sub fileWrite
{
	my $line = shift;
	my $resumeline = shift;
	my $shutdownline = shift;
	my $time = plugin::get_date_time( "[hh:mm:ss] " );
	
	# If we don't have a logfile name yet use the buffer
	if ( !$currentLogFile )
	{ push ( @output_buffer, "$time$line" ); return; }
	
	
	if ( !( -e "./HTML_Game_Logs/" . $currentLogFile . '.htm' ) )
	{
		start_logfile();
	}
	
	if ( open ( LOGFILE, '>>' . "./HTML_Game_Logs/" . $currentLogFile . '.htm' ) )
	{
		# Deal with anything in the buffer, unless we are printing the log resume line
		while ( @output_buffer && !$resumeline )
		{
			my $bufferline = shift( @output_buffer );
			print LOGFILE "$bufferline<br>\n";
		}
		
		if ( !$resumeline && !$shutdownline ) { $line = "$time$line"; }
		print LOGFILE "$line<br>\n";
		close ( LOGFILE );
	}
	else
	{
		print "Failed writing to /HTML_Game_Logs/$currentLogFile.htm\n";
	}
	
	return;
}


# Starts a logfile
sub start_logfile
{
	if ( !$currentLogFile )
	{ return; }
	
	if ( open ( LOGFILE, '>' . "./HTML_Game_Logs/" . $currentLogFile . '.htm' ) )
	{
		my $logtime = plugin::get_date_time( "hh:mm:ss on DD-MM-YY" );
		print LOGFILE "<html>\n\n<head>\n<title>BRenBot HTML Logfile for map $currentMap, played at $logtime</title>\n</head>\n\n<body bgcolor=black text=white>\n";
		close ( LOGFILE );
	}
	else
	{
		print "Failed writing to /HTML_Game_Logs/$currentLogFile.htm\n";
	}
	
	plugin::set_global ( "htmloutput_logfilename", $currentLogFile );
	
	return;
}


# Closes a logfile
sub close_logfile
{
	my $oldlogfile = shift;
	
	if ( -e "./HTML_Game_Logs/" . $oldlogfile . '.htm' )
	{
		if ( open ( LOGFILE, '>>' . "./HTML_Game_Logs/" . $oldlogfile . '.htm' ) )
		{
			my $logtime = plugin::get_date_time( "hh:mm:ss on DD-MM-YY" );
			print LOGFILE "<br>\n<br>\n<br>\n<i>Logfile closed at $logtime\n</body>\n</html>";
			close ( LOGFILE );
		}
		else
		{
			print "Failed writing to /HTML_Game_Logs/$oldlogfile.htm\n";
		}
	}
	
	return;
}

1;