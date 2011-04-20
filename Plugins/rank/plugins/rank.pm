#
# RANK PLUGIN for BRenBot 1.54 by Daniel Paul
# Original plugin by PackHunter

# Version 2.05
#
package rank;

use POE;
use plugin;
use strict;
use DBI;
use Net::FTP;


# Additional Events
our %additional_events =
(
	# Other Events
	"joinmessage" => "joinmessage",

	# Events for commands - Index name matches full command name
	"rank"			=> "rank",
	"top"			=> "top",
	"rankstats"		=> "rankstats",
	"update"		=> "update",
	"rankignore"	=> "rankIgnore",
	"rankallow"		=> "rankAllow",
	"rankmerge"		=> "rankMerge",
	"delrank"		=> "delRank",


	# Gamelog regex hooks
	"GL_buildingKill"	=> "GL_buildingKill",
	"GL_buildingRepair"	=> "GL_buildingRepair",
	"GL_vehicleKill"	=> "GL_vehicleKill",
	"GL_vehicleRepair"	=> "GL_vehicleRepair",
);

# Name and config to be filled in by BRenBot
our $plugin_name;
our %config;

# Database handle
my $dbh;

# Version
our $currentVersion = 2.05;

# Other global variables
my %ignoredPlayers;
my $recordRanks = 0;
my %bKills;
my %bRepair;
my %vKills;
my %vRepair;



################################
# Event Functions
#
# Functions for events
################################

# Start event - Triggered on bot startup
sub start
{
	# Get the number of GDI and Nod players, if both are >0 then enable ranking
	my ( undef, undef, $gdiPlayers, undef, $nodPlayers, undef, undef, undef, undef, undef ) = plugin::getGameStatus();
	if ( $gdiPlayers > 0 && $nodPlayers > 0 ) { $recordRanks = 1; }

	# Create rankUpdate.cmd if applicable
	if ( $config{'outputFormat'} == 2 )
	{
		createRankUpdateCmd();
	}

	# Run startup functions
	checkConfig();
	loadDatabase();
	loadIgnoredPlayers();
}

# Stop event - Triggered on bot shutdown
sub stop
{
	$dbh->disconnect;
}

# Command event - Triggers on any !command which is in this plugins XML file
sub command
{
	my ( $kernel, $args ) = @_[ KERNEL, ARG0 ];
	my %args = %{$args};

	# Trigger the event with the same name as the command
	if ( $args{'command'} eq "update" )
		{ $kernel->yield ( update => 0 ); }
	else
		{ $kernel->yield ( $args{'command'} => \%args ); }
}

# Playerjoin event - Triggers when a player joins the server
sub playerjoin
{
	my ( $kernel, $args ) = @_[ KERNEL, ARG0 ];
	my %args = %{$args};


	# Get the number of GDI and Nod players, if both are >0 then enable ranking
	my ( undef, undef, $gdiPlayers, undef, $nodPlayers, undef, undef, undef, undef, undef ) = plugin::getGameStatus();
	if ( $gdiPlayers > 0 && $nodPlayers > 0 ) { $recordRanks = 1; }


	# If enabled in config show the players rank after the specified delay
	if ( $config{'showRankOnJoin'} )
	{
		my $next_time = int( time() ) + $config{'showRankOnJoinDelay'};
		$kernel->alarm( joinmessage => $next_time => \%args );
	}
}

# Join message -> part of the playerjoin event
sub joinmessage
{
	my %args = %{$_[ ARG0 ]};

	my ( $result, %rankData ) = getRankData ( $args{'nick'}, 1 );
	if ( $result != 1 )
	{
		plugin::RenRemCMD ( "msg $args{nick} is not ranked yet." );
	}
	else
	{
		# Play airraid noise if enabled in config
		if ( ( $rankData{'rankPosition'} ) <= ($config{'sirenMinRank'}) ) { plugin::RenRemCMD( "snda amb_airraid.wav" ); }

		my $rankMessage = "";
		if ( $config{'rankMode'} == 1 )
			{ $rankMessage = "a total score of $rankData{score}"; }
		elsif ( $config{'rankMode'} == 2 )
			{ $rankMessage = "$rankData{kills} kills"; }
		elsif ( $config{'rankMode'} == 3 )
			{ $rankMessage = "a k/d of " . sprintf ( "%.1f", ( $rankData{'kills'} / $rankData{'deaths'} ) ); }
		elsif ( $config{'rankMode'} == 4 )
			{ $rankMessage = "$rankData{'rankPoints'} rank points"; }


		plugin::RenRemCMD( "msg $rankData{name} has $rankMessage and is ranked at position $rankData{rankPosition} out of " . rankedPlayersCount() . " players." );
	}
}

# Mapload event - Triggers when a new map has finished loading
sub mapload
{
	my ( $kernel, $args ) = @_[ KERNEL, ARG0 ];
	my %args = %{$args};

	# If recordRanks == 1 then update the website in 10 seconds
	if ( $recordRanks == 1 )
	{
		$kernel->alarm( update => ( int(time()) + 10 ) => 0 );

		# Reset record ranks variable
		$recordRanks = 0;
	}


	# Get the number of GDI and Nod players, if both are >0 then enable ranking
	my ( undef, undef, $gdiPlayers, undef, $nodPlayers, undef, undef, undef, undef, undef ) = plugin::getGameStatus();
	if ( $gdiPlayers > 0 && $nodPlayers > 0 ) { $recordRanks = 1; }
}

# Gameresult event - Triggers once BRenBot has read the results##.txt file at the end of the map
sub gameresult
{
	my %args = %{$_[ ARG0 ]};
	my @results = @{$args{'gameresults'}};

	return if ( $recordRanks == 0 );

	# Process the results
	my $mvp = 1;
	foreach ( @results )
	{
		updatePlayerStats ( $_->{'name'}, $_->{'score'}, $_->{'kills'}, $_->{'death'}, $_->{'side'}, $mvp );
		$mvp = 0;
	}

	# Finally update rank positions
	updateRankPositions();
}






################################
# Command Functions
#
# Functions for each !command
################################

# Function for !rank command - Shows rank for a player, or rank position
sub rank
{
	my %args = %{$_[ ARG0 ]};

	my $result;		my %rankData;	my $target;

	if ( !$args{'arg1'} )
	{
		if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( "!rank is not allowed in IRC. Use !rank <name> or !rank <position>.", $args{'ircChannelCode'} ); return; }
		else { $target = $args{'nick'}; ( $result, %rankData ) = getRankData ( $args{'nick'}, 1 ); }
	}
	else
	{
		# $player is either going to be a player name or a rank position
		$args{'arg'} =~ m/^\!\S+\s(.+)$/i;
		$target = $1;
		( $result, %rankData ) = getRankData ( $1 );
	}


	my $message = "";
	if ( $result == 2 )
	{
		my $namesShown = ( $rankData{'namesFound'} > 5 ) ? 5 : $rankData{'namesFound'};
		$message = "$target was found in more than $rankData{namesFound} records. The first $namesShown matches are :: $rankData{names}";
	}

	elsif ( $result != 1 )
		{ $message = "There was no rank data found for $target."; }

	else
	{
		my $rankMessage = "";
		if ( $config{'rankMode'} == 1 )			{ $rankMessage = "a total score of $rankData{score}"; }
		elsif ( $config{'rankMode'} == 2 )		{ $rankMessage = "$rankData{kills} kills"; }
		elsif ( $config{'rankMode'} == 3 )		{ $rankMessage = "a k/d of " . sprintf ( "%.1f", ( $rankData{'kills'} / $rankData{'deaths'} ) ); }
		elsif ( $config{'rankMode'} == 4 )		{ $rankMessage = "$rankData{'rankPoints'} rank points"; }

		$message = "$rankData{name} has $rankMessage and is ranked at position $rankData{rankPosition} out of " . rankedPlayersCount() . " players.";
	}


	# If there is a message to send then send it
	if ( $message )
	{
		if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
		else { plugin::pagePlayer ( $args{'nick'}, "BRenBot", $message ); }
	}
}


# Rankstats command, shows basic rank statistics for the specified player
sub rankstats
{
	my %args = %{$_[ ARG0 ]};

	my $result;		my %rankData;	my $target;

	if ( !$args{'arg1'} )
	{
		if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( "!rankstats is not allowed in IRC. Use !rankstats <name> or !rankstats <position>.", $args{'ircChannelCode'} ); return; }
		else { $target = $args{'nick'}; ( $result, %rankData ) = getRankData ( $args{'nick'}, 1 ); }
	}
	else
	{
		# $player is either going to be a player name or a rank position
		$args{'arg'} =~ m/^\!\S+\s(.+)$/i;
		$target = $1;
		( $result, %rankData ) = getRankData ( $1 );
	}


	my $message = "";
	if ( $result == 2 )
	{
		my $namesShown = ( $rankData{'namesFound'} > 5 ) ? 5 : $rankData{'namesFound'};
		$message = "$target was found in more than $rankData{namesFound} records. The first $namesShown matches are :: $rankData{names}";
	}

	elsif ( $result != 1 )
		{ $message = "There was no rank data found for $target."; }

	else
	{
		# Only show rank points field in mode 4
		my $rankPoints = ( $config{'rankMode'} == 4 ) ? " rank points: $rankData{rankPoints}," : "";
		$message = "Stats for $rankData{name}, ranked $rankData{rankPosition} ::$rankPoints score: $rankData{score}, kills: $rankData{kills}, deaths: $rankData{deaths}, games: $rankData{games}, GDI: $rankData{games_gdi}, Nod: $rankData{games_nod}, MVP: $rankData{mvp}";
	}


	# If there is a message to send then send it
	if ( $message )
	{
		if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
		else { plugin::pagePlayer ( $args{'nick'}, "BRenBot", $message ); }
	}
}


# RankIgnore command - Marks a player as ignored so they do not gain any rank data
sub rankIgnore
{
	my %args = %{$_[ ARG0 ]};

	my $message;
	if ( !$args{'arg1'} )			# Check they have given a name of a player to ignore
		{ $message = "You must specify the name of the player to ignore. Usage: !rankIgnore <playername>"; }

	else
	{
		$args{'arg'} =~ m/^\!\S+\s(.+)$/i;		# Support for names with spaces
		my $ignore = lc($1);			$ignore =~ s/'/''/g;

		if ( $ignoredPlayers{$ignore} )		# Check if they are already on the ignore list
			{ $message = "$ignore is already on the ignore list for rankings."; }
		else
		{
			$dbh->do ( "INSERT INTO ignoredPlayers ( name ) VALUES ( '$ignore' )" );
			$ignoredPlayers{$ignore} = 1;

			$message = "$ignore has been added to the ignore list for rankings";
		}
	}

	if ( $args{'nicktype'} == 1 )
		{ plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
	else
		{ plugin::pagePlayer ( $args{'nick'}, "BRenBot", $message ); }
}


# RankAllow command - Unmarks a player as being ignored
sub rankAllow
{
	my %args = %{$_[ ARG0 ]};

	my $message;
	if ( !$args{'arg1'} )			# Check they have given a name of a player to allow
		{ $message = "You must specify the name of the player to allow. Usage: !rankAllow <playername>"; }

	else
	{
		$args{'arg'} =~ m/^\!\S+\s(.+)$/i;		# Support for names with spaces
		my $allow = lc($1);			$allow =~ s/'/''/g;

		if ( $ignoredPlayers{$allow} )		# Check if they are on the ignore list
		{
			$dbh->do ( "DELETE FROM ignoredPlayers WHERE lower(name) = '$allow'" );
			delete $ignoredPlayers{$allow};

			$message = "$allow has been removed from the ignore list for rankings";
		}
		else
			{ $message = "$allow is not on the ignore list for rankings..."; }

	}

	if ( $args{'nicktype'} == 1 )
		{ plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
	else
		{ plugin::pagePlayer ( $args{'nick'}, "BRenBot", $message ); }
}



# !top command - shows top X players in the rankings
sub top
{
	my %args = %{$_[ ARG0 ]};

	# If arg1 is all digits (0-9) use that for total, otherwise use default of 3
	my $totalShown = ( $args{arg1} =~ /^[0-9]+$/ ) ? $args{arg1} : 3;

	# Check total is not >5
	if ( $totalShown > 5 )
	{
		my $message = "A maximum of 5 players is allowed. Showing top 5 ranked players.";
		if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
		else { plugin::pagePlayer ( $args{'nick'}, "BRenBot", $message ); }

		$totalShown = 5;
	}


	# Check there are ranked players
	my $totalRanked = rankedPlayersCount();
	if ( $totalRanked == 0 )
	{
		my $message = "There are no players ranked yet.";
		if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
		else { plugin::pagePlayer ( $args{'nick'}, "BRenBot", $message ); }
	}


	# If there are ranked players get the top $totalShown players
	else
	{
		# Get text for the ranking field (rankType)
		my $rankType;				my $rankField;
		if ( $config{'rankMode'} == 1 )		{ $rankType = 'points';			$rankField = 'score'; }
		elsif ( $config{'rankMode'} == 2 )	{ $rankType = 'kills';			$rankField = 'kills'; }
		elsif ( $config{'rankMode'} == 3 )	{ $rankType = 'k/d ratio';		$rankField = 'kd'; }
		elsif ( $config{'rankMode'} == 4 )	{ $rankType = 'rank points';	$rankField = 'rankPoints'; }

		# Loop and get data for each of the top $totalShown
		for ( my $i = 1; $i <= $totalShown && $i < $totalRanked; $i++ )
		{
			my ( $result, %rankData ) = getRankData ( $i );
			if ( $result == 1 )
			{
				my $message = "$rankData{rankPosition}. $rankData{name} with $rankData{$rankField} $rankType.";
				if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
				else { plugin::pagePlayer ( $args{'nick'}, "BRenBot", $message ); }
			}
		}
	}
}




# !rankMerge command - Merges two sets of rank data into one
sub rankMerge
{
	my %args = %{$_[ ARG0 ]};

	return if ( $args{'nicktype'} == 1 );


	# First check the user actually has rank data to merge
	my ( $result, %rankData ) = getRankData ( $args{'nick'}, 1 );
	if ( $result == 0 )
		{ plugin::pagePlayer ( $args{'nick'}, "BRenBot", "You do not have any rank data to merge into the target account!" ); }

	# If they have rank data to merge then see if the target account exists
	else
	{
		# Check they gave us an account to transfer the data to
		if ( $args{'arg'} =~ m/^\!\S+\s(.+)$/ )
		{
			my $name = lc( $args{'nick'} );			$name =~ s/"/\'/;
			my $newName = lc( $1 );					$newName =~ s/"/\'/;

			my ($qryResult, $qryResult2);

			# Check if $newName has any existing ranking data
			my ( $result2, %rankData2 ) = getRankData ( $newName, 1 );

			# If result == 0 then the new name has no rank data, so just change the name on the rank records
			if ( $result2 == 0 )
			{
				$qryResult = $dbh->do ( "UPDATE ranks SET name = \"$newName\" WHERE LOWER(name) = \"$name\"" );

				# If they have existing rankStats data but not ranks data then the rankStats data must be deleted
				$dbh->do ( "DELETE FROM rankStats WHERE LOWER(name) = \"$newName\"" );
				$qryResult2 = $dbh->do ( "UPDATE rankStats SET name = \"$newName\" WHERE LOWER(name) = \"$name\"" );
			}

			# If the target account already has rank data we will have to merge it...
			else
			{
				# Get any rankStats data for the accounts
				my ( $result3, %rankStats ) = getRankStats ( $name, 1 );
				my ( $result4, %rankStats2 ) = getRankStats ( $newName, 1 );

				# Add the data in $rankData and $rankStats to the data in $rankData2 and $rankStats2
				foreach my $k ( keys %rankData2 )
					{ $rankData2{$k} = $rankData2{$k} + $rankData{$k}; }

				foreach my $k ( keys %rankStats2 )
					{ $rankStats2{$k} = $rankStats2{$k} + $rankStats{$k}; }


				# Update target account, delete old one
				$qryResult = $dbh->do ( "UPDATE ranks SET
					kills = $rankData2{kills},
					deaths = $rankData2{deaths},
					score = $rankData2{score},
					MVP = $rankData2{mvp},
					games = $rankData2{games},
					GDI = $rankData2{games_gdi},
					Nod = $rankData2{games_nod},
					buildingKills = $rankData2{buildingKills},
					buildingRepair = $rankData2{buildingRepair},
					vehicleKills = $rankData2{vehicleKills},
					vehicleRepair = $rankData2{vehicleRepair}
					WHERE LOWER(name) = \"$newName\"" );
				$dbh->do ( "DELETE FROM ranks WHERE LOWER(name) = \"$name\"" );



				$qryResult2 = $dbh->do ( "UPDATE rankStats SET
					nodHarv = $rankStats2{nodHarv},			nodBug = $rankStats2{nodBug},			nodApc = $rankStats2{nodApc},
					nodArt = $rankStats2{nodArt},			nodLight = $rankStats2{nodLight},		nodFlame = $rankStats2{nodFlame},
					nodStank = $rankStats2{nodStank},		nodApache = $rankStats2{nodApache},	nodTrans = $rankStats2{nodTrans},
					gdiHarv = $rankStats2{gdiHarv},			gdiHum = $rankStats2{gdiHum},			gdiApc = $rankStats2{gdiApc},
					gdiMrl = $rankStats2{gdiMrl},			gdiMed = $rankStats2{gdiMed},			gdiMam = $rankStats2{gdiMam},
					gdiOrca = $rankStats2{gdiOrca},			gdiTrans = $rankStats2{gdiTrans},		nodHon = $rankStats2{nodHon},
					nodRef = $rankStats2{nodRef},			nodObi = $rankStats2{nodObi},			nodPp = $rankStats2{nodPp},
					nodAir = $rankStats2{nodAir},			gdiBar = $rankStats2{gdiBar},			gdiRef = $rankStats2{gdiRef},
					gdiAgt = $rankStats2{gdiAgt},			gdiPp = $rankStats2{gdiPp},				gdiWf = $rankStats2{gdiWf}
					WHERE LOWER(name) = \"$newName\"" );
				$dbh->do ( "DELETE FROM rankStats WHERE LOWER(name) = \"$name\"" );
			}

			if ( defined ( $qryResult ) ) { plugin::pagePlayer ( $args{'nick'}, "BRenBot", "Your rank data has been merged into the data for player $newName. Position in the rankings will be updated at the start of the next map." ); }
			else { plugin::pagePlayer ( $args{'nick'}, "BRenBot", "Unable to merge rank data for the players $name and $newName... " ); }
		}

		# No target account name given
		else
			{ plugin::pagePlayer ( $args{'nick'}, "BRenBot", "You must specify the account name you wish to merge your rank data into." ); }
	}
}




# !delRank command - Deletes a players rank data
sub delRank
{
	my %args = %{$_[ ARG0 ]};

	# Support for names with spaces
	if ( $args{'arg'} =~ m/^\!\S+\s(.+)$/ )
	{
		my $name = lc ( $1 );			$name =~ s/"/\'/;
		my $result = $dbh->do ( "DELETE FROM ranks WHERE LOWER(name) = \"$name\"" );
		$dbh->do ( "DELETE FROM rankStats WHERE LOWER(name) = \"$name\"" );

		if ( $result == 1 ) { plugin::ircmsg ( "All rank data for $name has been deleted, ranks will be re-ordered when the map next changes.", "A" ); }
		else { plugin::ircmsg ( "Unable to find any rank data for $name to delete.", "A" ); }
	}
	else { plugin::ircmsg ( "You must specify the name of the player whose rank data you wish to delete.   USAGE: !delRank <playername>", "A" ); }
}



# !update command, and also runs after each map
# Need to track update number so that we can't get two
# updates running at the same time
my $updateNumber = 0;
sub update
{
	my ( $kernel, $startPosition, $uNumber ) = @_[ KERNEL, ARG0, ARG1 ];

	if ( $startPosition == 0 )
		{ $uNumber = ++$updateNumber; }

	# If the update numbers do not match then another updated has been started
	# since this one began, so return.
	if ( $updateNumber != $uNumber )
		{ return; }

	# Create the ranks.txt file in batches of 50
	createRanksTxt( $startPosition+1, $startPosition+50 );

	# Schedule the next block of 100
	if ( $startPosition+50 < rankedPlayersCount() )
		{ $kernel->delay( update => 2 => $startPosition+50 => $uNumber ); }

	# If we reached the end of the playerlist then upload the file
	elsif ( $config{'enableFTP'} )
		{ upload() };
}


# Uploads the updated ranks.txt file to the FTP
sub upload
{
	my $ftp = Net::FTP->new( "$config{'ftpServer'}", Debug => 0 );
	if ( $ftp )
	{
		if ( $ftp->login( $config{'ftpUsername'},$config{'ftpPassword'} ) )
		{
			print "[Plugin - Rank] FTP :: Login Successful\n";
			if ( !$ftp->cwd( $config{'ftpPath'} ) )
			{
				print "[Plugin - Rank] FTP :: Path '$config{ftpPath}' does not exist!\n";

			}
			else
			{
				if ( $ftp->put ( "$config{sitePath}$config{outputFile}" ) )
					{ print "[Plugin - Rank] FTP :: File $config{outputFile} uploaded successful\n"; }
				else
					{ print "[Plugin - Rank] FTP :: File $config{outputFile} upload failed!\n"; }
			}

			print "[Plugin - Rank] FTP :: Disconnected\n";
			$ftp->quit;
		}
		else
			{ print "[Plugin - Rank] FTP :: Login Failed\n"; }
	}
	else
		{ print "[Plugin - Rank] FTP :: Invalid FTP server address\n"; }
}




################################
# Output File Functions
#
# Functions used in creating website output files
################################


# Creates the ranks.txt file
sub createRanksTxt
{
	my $startPosition = shift;
	my $endPosition = shift;

	# If output mode is 2 (SQL Dump) run the SQL dump commands and return
	if ( $config{'outputFormat'} == 2 )
	{
		system ( "DEL /Q .\\$config{outputFile}" );
		system ( ".\\sqlite .\\rankings.dat < .\\rankUpdate.cmd" );
		return;
	}

	# Otherwise do normal actions

	if ( $endPosition > rankedPlayersCount() )
		{ $endPosition = rankedPlayersCount(); }


	# Open file and truncate if we are starting at 1, otherwise open and append
	my $ranksTxt;
	if( $startPosition == 1 && !open( $ranksTxt, ">$config{sitePath}$config{outputFile}" ) )
		{ print "[Plugin - Rank] Failed to open $config{sitePath}$config{outputFile}"; }
	elsif( $startPosition != 1 && !open( $ranksTxt, ">>$config{sitePath}$config{outputFile}" ) )
		{ print "[Plugin - Rank] Failed to open $config{sitePath}$config{outputFile}"; }

	else
	{
		# Print each row of data into it one by one
		for ( my $i = $startPosition; $i <= $endPosition; $i++ )
		{
			my ( $result, %rankData ) = getRankData ( $i, 1 );
			my ( $result2, %rankStats ) = getRankStats ( $rankData{'name'} );

			if ( $result )
			{
				print $ranksTxt "$rankData{rankPosition}\t$rankData{name}\t$rankData{kills}\t$rankData{deaths}\t$rankData{score}\t$rankData{mvp}\t$rankData{games}\t$rankData{games_gdi}\t$rankData{games_nod}\t";
				print $ranksTxt "$rankData{buildingKills}\t$rankData{buildingRepair}\t$rankData{vehicleKills}\t$rankData{vehicleRepair}\t$rankStats{nodHarv}\t$rankStats{nodBug}\t$rankStats{nodApc}\t$rankStats{nodArt}\t$rankStats{nodLight}\t";
				print $ranksTxt "$rankStats{nodFlame}\t$rankStats{nodStank}\t$rankStats{nodApache}\t$rankStats{nodTrans}\t$rankStats{gdiHarv}\t$rankStats{gdiHum}\t$rankStats{gdiApc}\t$rankStats{gdiMrl}\t$rankStats{gdiMed}\t";
				print $ranksTxt "$rankStats{gdiMam}\t$rankStats{gdiOrca}\t$rankStats{gdiTrans}\t$rankStats{nodHon}\t$rankStats{nodRef}\t$rankStats{nodObi}\t$rankStats{nodPp}\t$rankStats{nodAir}\t$rankStats{gdiBar}\t";
				print $ranksTxt "$rankStats{gdiRef}\t$rankStats{gdiAgt}\t$rankStats{gdiPp}\t$rankStats{gdiWf}\n";
			}
		}

		close $ranksTxt;
	}
}


# Creates the rankUpdate.cmd file
sub createRankUpdateCmd
{
	open (RANKSINPUT, ">rankUpdate.cmd");
	print RANKSINPUT ".mode list\n";
	print RANKSINPUT ".separator \"*\"\n";
	print RANKSINPUT ".nullvalue \"0\"\n";
	print RANKSINPUT ".output .\\$config{outputFile}\n";
	print RANKSINPUT "SELECT rankPosition, ranks.name, kills, deaths, score, mvp, games, GDI, Nod, buildingKills, buildingRepair, vehicleKills, vehicleRepair, nodHarv, nodBug, nodApc, nodArt, nodLight, nodFlame, nodStank, nodApache, nodTrans, gdiHarv, gdiHum, gdiApc, gdiMrl, gdiMed, gdiMam, gdiOrca, gdiTrans, nodHon, nodRef, nodObi, nodPp, nodAir, gdiBar, gdiRef, gdiAgt, gdiPp, gdiWf, rankPoints FROM ranks LEFT OUTER JOIN rankStats ON LOWER(ranks.name) = rankStats.name ORDER BY rankPosition ASC;\n";
	print RANKSINPUT ".quit\n";
	close (RANKSINPUT);
}




################################
# Gamelog Functions
#
# Functions triggered by our gamelog regex hooks
################################

# Building kill detected
sub GL_buildingKill
{
	my %args = %{$_[ ARG0 ]};
	my $line = $args{'line'};

	return if ( $recordRanks == 0 );

	#KILLED;BUILDING;1500000045;CnC_GDI_Barracks;72;-87;0;-175;1500001168;CnC_Nod_Minigunner_0;67;-95;0;-145;Weapon_AutoRifle_Player_Nod
	if ( $line =~ m/KILLED;BUILDING;\d+;([^;]+);-?\d+;-?\d+;-?\d+;-?\d+;(\d+);[^;]+;-?\d+;-?\d+;-?\d+;-?\d+;/i )
	{
		my $player = plugin::getPlayerFromObjectID ( $2 );
		if ( defined ( $player ) )
		{
			$player = lc($player);
			my $ok = recordBuildingKill ( $1, $player );

			if ( $ok == 1 )
			{
				if ( !exists($bKills{$player} ) ) { $bKills{$player} = 1; }
				else { $bKills{$player}++; }
			}
		}
	}
}


# Building repair detected
sub GL_buildingRepair
{
	my %args = %{$_[ ARG0 ]};
	my $line = $args{'line'};

	return if ( $recordRanks == 0 );

	#DAMAGED;BUILDING;1500000045;CnC_GDI_Barracks;72;-87;0;-175;1500001168;CnC_Nod_Minigunner_0;65;-104;0;-173;2.399994;150;147;0
	if ( $line =~ m/DAMAGED;BUILDING;\d+;[^;]+;-?\d+;-?\d+;-?\d+;-?\d+;(\d+);[^;]+;-?\d+;-?\d+;-?\d+;-?\d+;(-\d+\.\d+);\d+;\d+;\d+$/i )
	{
		my $player = plugin::getPlayerFromObjectID ( $1 );
		if ( defined ( $player ) )
		{
			$player = lc($player);

			if ( !exists($bRepair{$player} ) ) { $bRepair{$player} = ($2*-1); }
			else { $bRepair{$player} += ($2*-1); }
		}
	}
}


# Vehicle kill detected
sub GL_vehicleKill
{
	my %args = %{$_[ ARG0 ]};
	my $line = $args{'line'};

	return if ( $recordRanks == 0 );

	#KILLED;VEHICLE;1500000045;CnC_GDI_Humm-vee;72;-87;0;-175;1500001168;CnC_Nod_Minigunner_0;67;-95;0;-145;Weapon_AutoRifle_Player_Nod
	if ( $line =~ m/KILLED;VEHICLE;\d+;([^;]+);-?\d+;-?\d+;-?\d+;-?\d+;(\d+);[^;]+;-?\d+;-?\d+;-?\d+;-?\d+;/i )
	{
		my $player = plugin::getPlayerFromObjectID ( $2 );
		if ( defined ( $player ) )
		{
			$player = lc($player);
			my $ok = recordVehicleKill ( $1, $player );

			if ( $ok == 1 )
			{
				if ( !exists($vKills{$player} ) ) { $vKills{$player} = 1; }
				else { $vKills{$player}++; }
			}
		}
	}
}


# Vehicle repair detected
sub GL_vehicleRepair
{
	my %args = %{$_[ ARG0 ]};
	my $line = $args{'line'};

	return if ( $recordRanks == 0 );

	#DAMAGED;VEHICLE;1500000930;CnC_GDI_Medium_Tank;-132;4;-2;142;1500000189;CnC_GDI_Engineer_0;-127;4;-3;-92;-2.000000;400;390;0
	if ( $line =~ m/DAMAGED;VEHICLE;\d+;[^;]+;-?\d+;-?\d+;-?\d+;-?\d+;(\d+);[^;]+;-?\d+;-?\d+;-?\d+;-?\d+;(-\d+\.\d+);\d+;\d+;\d+$/i )
	{
		my $player = plugin::getPlayerFromObjectID ( $1 );
		if ( defined ( $player ) )
		{
			$player = lc($player);

			if ( !exists($vRepair{$player} ) ) { $vRepair{$player} = ($2*-1); }
			else { $vRepair{$player} += ($2*-1); }
		}
	}
}






################################
# Ranking Functions
#
# Functions which control and update rankings
################################

# Updates basic stats for a player ( data from results##.txt )
sub updatePlayerStats
{
	my ( $name, $score, $kills, $deaths, $side, $mvp ) = @_;
	$name =~ s/'/''/g;

	return if ( $score < $config{'rankingMinScore'} );
	return if ( $ignoredPlayers{lc($name)} );


	# Get players existing rank data
	my ( $result, %rankData ) = getRankData ( $name, 1 );
	if ( $result == 1 )
	{
		$rankData{'kills'} += $kills;
		$rankData{'deaths'} += $deaths;
		$rankData{'score'} += $score;
		$rankData{'games'}++;

		if( ( $side =~ m/Nod/i ) || ( $side =~ m/Soviet/i ) )
			{ $rankData{'games_gdi'}++; }
		else
			{ $rankData{'games_nod'}++; }

		if ( $mvp == 1 )
			{ $rankData{'mvp'}++; }

		# Get any building / vehicle kill / repair stats from the hashes
		if ( exists($bKills{lc($name)}) ) { $rankData{'buildingKills'} += $bKills{lc($name)}; delete $bKills{lc($name)}; }
		if ( exists($bRepair{lc($name)}) ) { $rankData{'buildingRepair'} += $bRepair{lc($name)}; delete $bRepair{lc($name)}; }
		if ( exists($vKills{lc($name)}) ) { $rankData{'vehicleKills'} += $vKills{lc($name)}; delete $vKills{lc($name)}; }
		if ( exists($vRepair{lc($name)}) ) { $rankData{'vehicleRepair'} += $vRepair{lc($name)}; delete $vRepair{lc($name)}; }


		# Update database
		$dbh->do( "
			UPDATE ranks
			SET	kills			= $rankData{kills}
			,	deaths			= $rankData{deaths}
			,	score			= $rankData{score}
			,	MVP				= $rankData{mvp}
			,	games			= $rankData{games}
			,	GDI				= $rankData{games_gdi}
			,	Nod				= $rankData{games_nod}
			,	buildingKills	= $rankData{buildingKills}
			,	buildingRepair	= $rankData{buildingRepair}
			,	vehicleKills	= $rankData{vehicleKills}
			,	vehicleRepair	= $rankData{vehicleRepair}
			WHERE name = '" . $rankData{name} . "'" );
	}

	else
	{
		my $gdi		= 0;
		my $nod		= 0;
		my $bkill	= 0;
		my $brep	= 0;
		my $vkill	= 0;
		my $vrep	= 0;

		if( ( $side =~ m/Nod/i ) || ( $side =~ m/Soviet/i ) )
			{ $nod++; }
		else
			{ $gdi++; }


		# Get any building / vehicle kill / repair stats from the hashes
		if ( exists($bKills{lc($name)}) ) { $bkill = $bKills{lc($name)}; delete $bKills{lc($name)}; }
		if ( exists($bRepair{lc($name)}) ) { $brep = $bRepair{lc($name)}; delete $bRepair{lc($name)}; }
		if ( exists($vKills{lc($name)}) ) { $vkill = $vKills{lc($name)}; delete $vKills{lc($name)}; }
		if ( exists($vRepair{lc($name)}) ) { $vrep = $vRepair{lc($name)}; delete $vRepair{lc($name)}; }

		# Insert into database
		$dbh->do("
			INSERT INTO ranks
			VALUES('$name'
			,		$kills
			,		$deaths
			,		0
			,		0
			,		$score
			,		$mvp
			,		1
			,		$gdi
			,		$nod
			,		$bkill
			,		$brep
			,		$vkill
			,		$vrep)");
	}
}


# Update rank positions
sub updateRankPositions
{
	$dbh->do( "DELETE FROM temp" );

	if ( $config{'rankMode'} == 1 )
	{ $dbh->do( "INSERT INTO temp SELECT NULL, * FROM ranks ORDER BY score desc" ); }
	elsif ( $config{'rankMode'} == 2 )
	{ $dbh->do( "INSERT INTO temp SELECT NULL, * FROM ranks ORDER BY kills desc" ); }
	elsif ( $config{'rankMode'} == 3 )
	{ $dbh->do( "INSERT INTO temp SELECT NULL, * FROM ranks ORDER BY (kills/deaths) desc" ); }
	elsif ( $config{'rankMode'} == 4 )
	{
		# Building up the calculation using the elements that are greater than 0 (otherwise we get divide by 0!)
		my $rankPointsCalculation = "(0";
		if ( $config{'scorePerRankPoint'} > 0 ) { $rankPointsCalculation .= "+(score/$config{scorePerRankPoint})"; }
		if ( $config{'killsPerRankPoint'} > 0 ) { $rankPointsCalculation .= "+(kills/$config{killsPerRankPoint})"; }
		if ( $config{'deathsPerMinusRankPoint'} > 0 ) { $rankPointsCalculation .= "-(deaths/$config{deathsPerMinusRankPoint})"; }
		if ( $config{'buildingKillsPerRankPoint'} > 0 ) { $rankPointsCalculation .= "+(buildingKills/$config{buildingKillsPerRankPoint})"; }
		if ( $config{'buildingRepairPerRankPoint'} > 0 ) { $rankPointsCalculation .= "+(buildingRepair/$config{buildingRepairPerRankPoint})"; }
		if ( $config{'vehicleKillsPerRankPoint'} > 0 ) { $rankPointsCalculation .= "+(vehicleKills/$config{vehicleKillsPerRankPoint})"; }
		if ( $config{'vehicleRepairPerRankPoint'} > 0 ) { $rankPointsCalculation .= "+(vehicleRepair/$config{vehicleRepairPerRankPoint})"; }
		$rankPointsCalculation .= ")";

		$dbh->do( "UPDATE ranks SET rankPoints = $rankPointsCalculation" );
		$dbh->do( "INSERT INTO temp SELECT NULL, * FROM ranks ORDER BY rankPoints DESC" );
	}

	$dbh->do( "DELETE FROM ranks" );

	$dbh->do( "INSERT INTO ranks
		SELECT a.name1
		,	  a.kills1
		,	  a.deaths1
		,	  a.rank1
		,	  a.rankPoints1
		,	  a.score1
		,	  a.MVP1
		,	  a.games1
		,	  a.GDI1
		,	  a.Nod1
		,	  a.buildingKills1
		,	  a.buildingRepair1
		,	  a.vehicleKills1
		,	  a.vehicleRepair1
		FROM temp a" );
}


# Records a vehicle kill
sub recordVehicleKill
{
	my $vehiclePreset	= shift;
	my $player			= lc(shift);
	$player =~ s/'/''/g;

	# Work out what update string to use for rankStats
	my $updateString = "";
	if ( $vehiclePreset =~ m/Nod_Harvester/i ) { $updateString = "nodHarv = (nodHarv + 1)"; }
	elsif ( $vehiclePreset =~ m/Nod_Buggy/i ) { $updateString = "nodBug = (nodBug + 1)"; }
	elsif ( $vehiclePreset =~ m/Nod_APC/i ) { $updateString = "nodApc = (nodApc + 1)"; }
	elsif ( $vehiclePreset =~ m/Nod_Mobile_Artillery/i ) { $updateString = "nodArt = (nodArt + 1)"; }
	elsif ( $vehiclePreset =~ m/Nod_Light_Tank/i ) { $updateString = "nodLight = (nodLight + 1)"; }
	elsif ( $vehiclePreset =~ m/Nod_Flame_Tank/i ) { $updateString = "nodFlame = (nodFlame + 1)"; }
	elsif ( $vehiclePreset =~ m/Nod_Stealth_Tank/i ) { $updateString = "nodStank = (nodStank + 1)"; }
	elsif ( $vehiclePreset =~ m/Nod_Apache/i ) { $updateString = "nodApache = (nodApache + 1)"; }
	elsif ( $vehiclePreset =~ m/Nod_Transport/i ) { $updateString = "nodTrans = (nodTrans + 1)"; }


	elsif ( $vehiclePreset =~ m/GDI_Harvester/i ) { $updateString = "gdiHarv = (gdiHarv + 1)"; }
	elsif ( $vehiclePreset =~ m/GDI_Humm-vee/i || $vehiclePreset =~ m/GDI_Humvee/i ) { $updateString = "gdiHum = (gdiHum + 1)"; }
	elsif ( $vehiclePreset =~ m/GDI_APC/i ) { $updateString = "gdiApc = (gdiApc + 1)"; }
	elsif ( $vehiclePreset =~ m/GDI_MRLS/i ) { $updateString = "gdiMrl = (gdiMrl + 1)"; }
	elsif ( $vehiclePreset =~ m/GDI_Medium_Tank/i ) { $updateString = "gdiMed = (gdiMed + 1)"; }
	elsif ( $vehiclePreset =~ m/GDI_Mammoth_Tank/i ) { $updateString = "gdiMam = (gdiMam + 1)"; }
	elsif ( $vehiclePreset =~ m/GDI_Orca/i ) { $updateString = "gdiOrca = (gdiOrca + 1)"; }
	elsif ( $vehiclePreset =~ m/GDI_Transport/i ) { $updateString = "gdiTrans = (gdiTrans + 1)"; }

	if ( $updateString )
	{
		my ( $result, %rankStats ) = getRankStats ( $player );
		if ( $result != 1 )
		{
			$dbh->do ( "INSERT INTO rankStats VALUES( '$player', 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 )" );
			$dbh->do ( "UPDATE rankStats SET $updateString WHERE name = '$player'" );
		}
		else
		{
			$dbh->do ( "UPDATE rankStats SET $updateString WHERE name = '$rankStats{name}'" );
		}
		return 1;
	}
	return 0;
}


# Records a building kill
sub recordBuildingKill
{
	my $buildingPreset	= shift;
	my $player			= lc(shift);
	$player =~ s/'/''/g;

	# Work out what update string to use for rankStats
	my $updateString = "";
	if ( $buildingPreset =~ m/Hand_of_Nod/i ) { $updateString = "nodHon = (nodHon + 1)"; }
	elsif ( $buildingPreset =~ m/Nod_Refinery/i ) { $updateString = "nodRef = (nodRef + 1)"; }
	elsif ( $buildingPreset =~ m/Nod_Obelisk/i ) { $updateString = "nodObi = (nodObi + 1)"; }
	elsif ( $buildingPreset =~ m/Nod_Power_Plant/i ) { $updateString = "nodPp = (nodPp + 1)"; }
	elsif ( $buildingPreset =~ m/Nod_Airstrip/i ) { $updateString = "nodAir = (nodAir + 1)"; }


	elsif ( $buildingPreset =~ m/GDI_Barracks/i ) { $updateString = "gdiBar = (gdiBar + 1)"; }
	elsif ( $buildingPreset =~ m/GDI_Refinery/i ) { $updateString = "gdiRef = (gdiRef + 1)"; }
	elsif ( $buildingPreset =~ m/GDI_Advanced_Guard_Tower/i || $buildingPreset =~ m/GDI_AGT/i ) { $updateString = "gdiAgt = (gdiAgt + 1)"; }
	elsif ( $buildingPreset =~ m/GDI_Power_Plant/i ) { $updateString = "gdiPp = (gdiPp + 1)"; }
	elsif ( $buildingPreset =~ m/GDI_War_Factory/i ) { $updateString = "gdiWf = (gdiWf + 1)"; }

	if ( $updateString )
	{
		my ( $result, %rankStats ) = getRankStats ( $player );
		if ( $result != 1 )
		{
			$dbh->do ( "INSERT INTO rankStats VALUES( '$player', 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 )" );
			$dbh->do ( "UPDATE rankStats SET $updateString WHERE name = '$player'" );
		}
		else
		{
			$dbh->do ( "UPDATE rankStats SET $updateString WHERE name = '$rankStats{name}'" );
		}
		return 1;
	}
	return 0;
}


# Gets basic rank data for a player
sub getRankData
{
	my $player = lc(shift);
	my $exactMatch = (scalar(@_) > 0) ? shift : 0;
	$player =~ s/'/''/g;

	my $sth;

	# If $player is a rank position we can only use exact match mode
	if ( $player =~ m/^\d+$/i )
	{
		$exactMatch = 1;
		$sth = $dbh->prepare( "SELECT *, (kills/deaths) FROM ranks WHERE rankPosition = $player" );
	}
	else { $sth = $dbh->prepare( "SELECT *, (kills/deaths) FROM ranks WHERE LOWER(name) = '$player'" ); }
	$sth->execute();

	# Try an exact match first..
	my @result = $sth->fetchrow_array;

	# If no result found try a LIKE match (unless $exactMatch == 1)
	my $nameList = "";
	my $nameCount = 0;
	if ( !@result && $exactMatch != 1 )
	{
		$sth = $dbh->prepare( "SELECT *, (kills/deaths) FROM ranks WHERE LOWER(name) LIKE \"%$player%\"" );
		$sth->execute();

		my @prevresult;
		while ( @result = $sth->fetchrow_array )
		{
			@prevresult = @result;

			# If this is an exact match jump out immediatly
			if ( lc($result[0]) eq $player )
				{ last; }

			# If this is one of the first 5 names add it to the list of names
			if ( $nameCount++ < 5 )
				{ $nameList .= "$result[0], "; }
		}

		if ( $nameCount == 1 )
			{ @result = @prevresult; }
	}


	# If there is a result return it (either exact or non-exact)
	if ( @result )
	{
		my %resultHash = (
			"name" => $result[0],				"kills" => $result[1],					"deaths" => $result[2],
			"rankPosition" => $result[3],		"rankPoints" => sprintf ( "%.0f", $result[4] ),
			"score" => $result[5],				"mvp" => $result[6],					"games" => $result[7],
			"games_gdi" => $result[8],			"games_nod" => $result[9],				"buildingKills" => $result[10],
			"buildingRepair" => $result[11],	"vehicleKills" => $result[12],			"vehicleRepair" => $result[13],
			'kd' => $result[14]
		);

		return ( 1, %resultHash );
	}

	# If there is a list of names return that instead
	if ( $nameList )
	{
		my %resultHash = (
			'names' => substr ( $nameList, 0, -2 ),		# Trim trailing ', '
			'namesFound' => $nameCount
		);
		return ( 2, %resultHash );
	}

	return ( 0, () );
}

# Retrieves rank stats data for a player ( number of each vehicle / building killed )
sub getRankStats
{
	my $player = lc(shift);
	$player =~ s/'/''/g;

	my @result = $dbh->selectrow_array ( "SELECT * FROM rankStats WHERE LOWER(name) = '$player'" );

	if ( @result )
	{
		my %resultHash = (
			"name" => $result[0],			"nodHarv" => $result[1],			"nodBug" => $result[2],
			"nodApc" => $result[3],			"nodArt" => $result[4],				"nodLight" => $result[5],
			"nodFlame" => $result[6],		"nodStank" => $result[7],			"nodApache" => $result[8],
			"nodTrans" => $result[9],		"gdiHarv" => $result[10],			"gdiHum" => $result[11],
			"gdiApc" => $result[12],		"gdiMrl" => $result[13],			"gdiMed" => $result[14],
			"gdiMam" => $result[15],		"gdiOrca" => $result[16],			"gdiTrans" => $result[17],
			"nodHon" => $result[18],		"nodRef" => $result[19],			"nodObi" => $result[20],
			"nodPp" => $result[21],			"nodAir" => $result[22],			"gdiBar" => $result[23],
			"gdiRef" => $result[24],		"gdiAgt" => $result[25],			"gdiPp" => $result[26],
			"gdiWf" => $result[27]
		);

		return ( 1, %resultHash );
	}

	return ( 0, undef );
}

# Function for getting the total number of ranked players
sub rankedPlayersCount
{
	return $dbh->selectrow_array ( "SELECT IFNULL(MAX(rankPosition),0) FROM ranks" );
}






################################
# Other Functions
#
# Maintanence and startup functions
################################

# Checks all the config settings are ok, resets them to defaults where necessary
sub checkConfig
{
	if ( $config{'showRankOnJoin'} !~ m/^(0|1)$/ )
	{
		print "[Plugin - Rank] showRankOnJoin is set to an invalid value. Valid values are 0 or 1. Defaulting to 1.\n";
		$config{'showRankOnJoin'} = 1;
	}

	if ( $config{'showRankOnJoinDelay'} !~ m/^\d+$/ )
	{
		print "[Plugin - Rank] showRankOnJoinDelay is not set or non numerical. Defaulting to 10 seconds.\n";
		$config{'showRankOnJoinDelay'} = 10;
	}

	if ( $config{'rankingMinScore'} !~ m/^\d+$/ )
	{
		print "[Plugin - Rank] rankingMinScore is not set or non numerical. Defaulting to 50 points.\n";
		$config{'rankingMinScore'} = 50;
	}

	if ( $config{'rankMode'} !~ m/^(1|2|3|4)$/ )
	{
		print "[Plugin - Rank] rankMode is set to an invalid value. Valid values are 1, 2, 3 or 4. Defaulting to 1\n";
		$config{'rankMode'} = 1;
	}
}

# Loads and checks the database
sub loadDatabase
{
	my $newDB = 1;
	if (-e "rankings.dat" ) { $newDB = 0; }

	if ( $^O eq "MSWin32" )
	{
		$dbh = DBI->connect("dbi:SQLite2:dbname=rankings.dat","","");
	}
	else	# Use alternative SQLite driver for linux
	{
		$dbh = DBI->connect("dbi:SQLite:dbname=rankings.dat","","");
	}

	# If $newDB == 1 then we are creating a new database
	if( $newDB == 1 )
	{
		$dbh->do(
			"CREATE TABLE ranks
			 (name				char(128) PRIMARY KEY
			 ,kills				int
			 ,deaths			int
			 ,rankPosition		int
			 ,rankPoints		int
			 ,score				int
			 ,MVP				int
			 ,games				int
			 ,GDI				int
			 ,Nod				int
			 ,buildingKills		int
			 ,buildingRepair	int
			 ,vehicleKills		int
			 ,vehicleRepair		int )" );

		$dbh->do ( "CREATE TABLE temp (
			rank1				integer PRIMARY KEY
			,name1				char(128)
			,kills1				int
			,deaths1			int
			,rankPosition1		int
			,rankPoints1		int
			,score1				int
			,MVP1				int
			,games1				int
			,GDI1				int
			,Nod1				int
			,buildingKills1		int
			,buildingRepair1	int
			,vehicleKills1		int
			,vehicleRepair1		int )" );

		$dbh->do ( "CREATE TABLE rankStats (
			name				char(128) PRIMARY KEY
			,nodHarv			int
			,nodBug				int
			,nodApc				int
			,nodArt				int
			,nodLight			int
			,nodFlame			int
			,nodStank			int
			,nodApache			int
			,nodTrans			int
			,gdiHarv			int
			,gdiHum				int
			,gdiApc				int
			,gdiMrl				int
			,gdiMed				int
			,gdiMam				int
			,gdiOrca			int
			,gdiTrans			int
			,nodHon				int
			,nodRef				int
			,nodObi				int
			,nodPp				int
			,nodAir				int
			,gdiBar				int
			,gdiRef				int
			,gdiAgt				int
			,gdiPp				int
			,gdiWf				int
		)" );


		$dbh -> do ( "CREATE TABLE ignoredPlayers ( name char(128) )" );
	}
	else
	{
		# Check version
		my $dbVersion = plugin::get_global ( "version_plugin_rank" );
		if ( !$dbVersion ) { $dbVersion = 1.0; }

		if ( $dbVersion != $currentVersion )
		{
			print "[Plugin - Rank] Database is out of date. DB is $dbVersion, current is $currentVersion. Updating to new version...\n";

			# Run updates for each old version sequentially
			if ( $dbVersion < 1.1 )
			{
				print "[Plugin - Rank] Updating db to 1.1....\n";
				print "  creating table ignoredPlayers\n";
				$dbh -> do ( "CREATE TABLE ignoredPlayers ( name char(128) )" );

				# Recreate the temp table
				print "  dropping extra columns in temp\n";
				$dbh -> do ( "DROP TABLE temp" );
				$dbh -> do ( "CREATE TABLE temp ( rank1	integer PRIMARY KEY, name1 char(128), kills1 int ,deaths1 int ,place1 int ,score1 int ,MVP1 int ,games1 int ,GDI1 int ,Nod1 int) ");

				# If only SQLite supported DROP COLUMN this would be SOOOO much easier...
				print "  dropping extra columns in ranks\n";
				$dbh -> do ( "INSERT INTO temp SELECT NULL, name, kills, deaths, place, score, MVP, games, GDI, Nod FROM ranks ORDER BY score DESC");
				$dbh -> do ( "DROP TABLE ranks" );
				$dbh -> do ( "CREATE TABLE ranks ( name char(128) PRIMARY KEY, kills int ,deaths int ,place int ,score int ,MVP int ,games int ,GDI int ,Nod int) ");
				$dbh -> do ( "INSERT INTO ranks SELECT name1, kills1, deaths1, rank1, score1, MVP1, games1, GDI1, Nod1 FROM temp");
			}

			# Now do update 1.1 -> 1.2
			if ( $dbVersion < 1.2 )
			{
				print "[Plugin - Rank] Updating db to 1.2....\n";
				print "  checking for split userdata records..\n";

				my $sth = $dbh->prepare( "SELECT COUNT(name) AS number, name, SUM(kills), SUM(deaths), SUM(score), SUM(mvp), SUM(games), SUM(gdi), SUM(nod) FROM ranks GROUP BY LOWER(name) ORDER BY COUNT(name) DESC" );
				$sth->execute();

				my $counter = 0;
				my @row;
				while ( @row = $sth->fetchrow_array )
				{
					# Check if there are no more accounts to repair
					if ( $row[0] == 1 ) { last; }

					# If there are more than two identical names first DELETE the
					# multiple accounts
					$dbh->do ( "DELETE FROM ranks WHERE lower(name) = \"" . lc($row[1]) . "\"" );

					# Now create one new record with the correct totals
					$dbh->do ( "INSERT INTO ranks ( name, kills, deaths, score, mvp, games, gdi, nod, place ) VALUES ( \"$row[1]\", $row[2], $row[3], $row[4], $row[5], $row[6], $row[7], $row[8], 0 )" );
					$counter++;
				}

				print "  $counter sets of results have been repaired\n";

				# If there were fixed results, reorder all the rankings
				if ( $counter ) { calc_rank_v2() };
			}


			# Now do update 1.2 -> 2.0
			if ( $dbVersion < 2.0 )
			{
				print "[Plugin - Rank] Updating db to 2.0....\n";

				# Recreate the temp table
				print "  Adding additional columns to temp table..\n";
				$dbh -> do( "DROP TABLE temp" );
				$dbh -> do( "CREATE TABLE temp ( rank1 integer PRIMARY KEY, name1 char(128), kills1 int, deaths1 int, rankPosition1 int, rankPoints1 int, score1 int, MVP1 int, games1 int, GDI1 int, Nod1 int, buildingKills1 int, buildingRepair1 int, vehicleKills1 int, vehicleRepair1 int )" );

				# If only SQLite supported EDIT TABLE this would be SOOOO much easier...
				print "  Adding additional columns to ranks table..\n";
				$dbh -> do( "INSERT INTO temp SELECT NULL, name, kills, deaths, place, 0, score, MVP, games, GDI, Nod, 0, 0, 0, 0 FROM ranks ORDER BY score DESC" );
				$dbh -> do( "DROP TABLE ranks" );
				$dbh -> do( "CREATE TABLE ranks ( name char(128) PRIMARY KEY, kills int, deaths int, rankPosition int, rankPoints int, score int, MVP int, games int, GDI int, Nod int, buildingKills int, buildingRepair int, vehicleKills int, vehicleRepair int )" );
				$dbh -> do( "INSERT INTO ranks SELECT name1, kills1, deaths1, rank1, 0, score1, MVP1, games1, GDI1, Nod1, 0, 0, 0, 0 FROM temp" );


				print "  Creating table rankStats, this may take a few minutes..\n";
				$dbh->do ( "CREATE TABLE rankStats ( name char(128) PRIMARY KEY, nodHarv int, nodBug int, nodApc int, nodArt int, nodLight int, nodFlame int, nodStank int, nodApache int, nodTrans int, gdiHarv int, gdiHum int, gdiApc int, gdiMrl int, gdiMed int, gdiMam int, gdiOrca int, gdiTrans int, nodHon int, nodRef int, nodObi int, nodPp int, nodAir int, gdiBar int, gdiRef int, gdiAgt int, gdiPp int, gdiWf int )" );

				# Create an empty record for each player
				my $sth = $dbh->prepare( "SELECT name FROM ranks" );
				$sth->execute();

				my @row;
				while ( @row = $sth->fetchrow_array ) { $dbh->do ( "INSERT INTO rankStats VALUES( '$row[0]', 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 )" ); }


				# Drop redundant globals table
				print "  Dropping redundant table globals..\n";
				$dbh->do( "DROP TABLE globals" );
			}

			# Set our current version in the globals table
			plugin::set_global ( "version_plugin_rank", $currentVersion );
		}
	}
}


# Loads the list of ignored players from the database
sub loadIgnoredPlayers
{
	my $query = $dbh->prepare ( "SELECT name FROM ignoredPlayers" );
	$query->execute();

	my @row;
	while ( @row = $query->fetchrow_array ) { $ignoredPlayers{lc($row[0])} = 1; }
}



1;