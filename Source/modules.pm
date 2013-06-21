#!/usr/bin/perl

package modules;
use strict;

use POE;
use POE::Kernel;	# Needed for successful pp compile
use POE::Session;	# Needed for successful pp compile
use Date::Calc qw( Delta_YMDHMS Time_to_Date);
use XML::Simple;
use Digest::MD5 qw(md5 md5_hex md5_base64);


use brdatabase;
use RenRem;
use brconfig;
use brAuth;


my @modules;
my $os = $^O;

my $mapSettings;			# Map settings XML hash array
our $donatelimit	= 0;	# Donate limit for current map
our $maprules		= "";	# Rules for current map
our $minelimit		= 30;	# Mine limit for current map
our $vehiclelimit	= 8;	# Current vehicle limit




# Prints a message to the console with the timestamp of the message. It also supports messages
# made up of multiple parts sent one after the other, for instance 'Trying to do X...' followed
# by 'success' or 'failure', without adding newlines and extra timestamps. Note that a newline
# will automatically be output if a non-multipart message or a new multipart message is sent
# whilst expecting the continuation of another multipart message.
#
# Parameters
# Message					Message to be output to the console
# Multipart Type			1 for the start of a message, 2 for middle sections, 3 for end
my $console_output_multipart_status = 0;
sub console_output
{
	my $message = shift;
	my $multipart_type = shift;

	# If this is not a multipart message, the start of a new one, or a continuation of
	# one when we are not expecting a continuation, output timestamp
	if ( !defined($multipart_type) || $multipart_type == 1 || $console_output_multipart_status != 1 )
	{
		# If a current multipart message is in progress then end it now
		if ( $console_output_multipart_status == 1 )
			{ print "\n"; }

		# Get current timestamp
		my ($second,$minute,$hour,undef,undef,undef,undef,undef,undef)=localtime(time);

		# Output timestamp
		printf ( "[%02d:%02d:%02d] ",$hour,$minute,$second);

		# Set new multipart message status
		$console_output_multipart_status = ( defined($multipart_type) && $multipart_type == 1 ) ? 1 : 0;
	}

	# Output message
	print $message;

	# If this is not a multipart message, or the end of one, output newline
	if ( !defined($multipart_type) || $multipart_type == 3 )
	{
		print "\n";

		# Set new multipart message status
		$console_output_multipart_status = 0;
	}
}


# Checks if the name specified is in the users table
sub user_exists
{
	my $name = lc(shift);		$name =~ s/'/''/g;

	my @array = brdatabase::execute_query( "SELECT * FROM auth_users WHERE LOWER(name)='$name'" );

	return 1 if ( scalar(@array) == 1 );
	return 0;

}

sub add_user
{
	my $name = lc(shift);		$name =~ s/'/''/g;
	my $password = md5_hex(shift);

	brdatabase::execute_query( "INSERT INTO auth_users ( name, password ) VALUES ( '$name', '$password' )", 1 );
}

sub del_user
{
	my $name = lc(shift);		$name =~ s/'/''/g;

	brdatabase::execute_query( "DELETE FROM auth_users WHERE LOWER(name) = '$name'", 1 );
}


sub time_difference
{
	my $timestamp1 = shift;
	my $timestamp2 = shift;

	my ( $year1, $month1, $day1, $hour1, $min1, $sec1 ) = BRTime_To_Date( $timestamp2 );
	my ( $year2, $month2, $day2, $hour2, $min2, $sec2 ) = BRTime_To_Date( $timestamp1 );


  	my ($D_y,$D_m,$D_d, $Dh,$Dm,$Ds) =
	 	Delta_YMDHMS($year1,$month1,$day1, $hour1,$min1,$sec1,
				   	$year2,$month2,$day2, $hour2,$min2,$sec2);

	my $result_text;

	$result_text .= "$D_y years, " if ($D_y);
	$result_text .= "$D_m months, " if ($D_m);
	$result_text .= "$D_d days, " if ($D_d);
	$result_text .= "$Dh hours, " if ($Dh);
	$result_text .= "$Dm minutes, " if ($Dm);
	$result_text .= "$Ds seconds, " if ($Ds);

	chop $result_text;
	chop $result_text;
	return $result_text;
}


# Gets the bot's uptime
sub get_uptime
{
	my $result_text = time_difference ( time(), shift );
	$result_text =~ s/\-//g;		# Because the values are negative, remove the - signs to get the uptime
	return $result_text;
}

sub del_ban
{
	my $id = shift;
	my @array = brdatabase::execute_query( "SELECT * FROM bans WHERE id = $id" );
	if (@array != 0)
	{
		brdatabase::execute_query( "DELETE FROM bans WHERE id = $id", 1 );
		return 1;
	}

	return 0;
}




###################################################
####
## Functions related to kicks (24 hour bans)
####
###################################################

# Kicks a player from the server and optionally records it in the database as a 24 hour ban
#
# Parameters
#	Target				ID or name of player to be kicked
#	Kicker				Name of the person who kicked them
#	Reason				Reason for them being kicked from the server
#	Temporary_Ban		Set to 1 to ban the player for 24 hours
sub kick_player
{
	my $target = shift;			$target =~ s/'/''/g;
	my $kicker = shift;			$kicker =~ s/'/''/g;
	my $reason = shift;			$reason =~ s/'/''/g;
	my $temporary_ban = shift;

	# Get data for the player to be kicked
	my ( $result, %player ) = playerData::getPlayerData ( $target, 1 );
	return if ( $result != 1 );

	# Prepare the message for the server announcement and message to the kicked player
	my $message = 'been kicked';
	$message .= ' and given a 24hr ban' if $temporary_ban;
	$message .= ' from the server by '.$kicker.' for '.$reason;

	# Send the server announcement and the message to the kicked player (in SSGM >= 4 the page to
	# the player is handled by the kick command)
	RenRem::RenRemCMD ( 'msg [BR] '.$player{'name'}.' has '.$message );
	RenRem::RenRemCMD ( 'pamsg '.$player{'id'}.' You have '.$message ) if ($brconfig::ssgm_version < 4);

	# Kick the player from the server (1 second delay to allow the pamsg to reach them)
	my $command = 'kick '.$player{'id'};
	$command .= ' '.$reason if ($brconfig::ssgm_version >= 4);
	RenRem::RenRemCMDtimed ( $command, 1 );

	# Write a kick record to the log
	brdatabase::writeLog ( 1, "[KICK] $player{name} ($player{ip}) was kicked by $kicker for '$reason'." );

	# If necessary also record the kick in the database for a 24hr ban
	if ( $temporary_ban )
	{
		my $serial = ( exists ( $player{'serial'} ) ) ? $player{'serial'} : "";
		brdatabase::execute_query ( "INSERT INTO kicks ( name, ip, serial, kicker, reason, timestamp ) VALUES ( '$player{name}', '$player{ip}', '$serial', '$kicker', '$reason', ".time()." )", 1 );
	}

	# Otherwise they are allowed straight back into the server so issue the allow command
	# unless we are running SSGM 4.0 or higher (where it is depreciated)
	elsif ( $brconfig::ssgm_version < 4 )
	{
		RenRem::RenRemCMDtimed ( 'allow '.$player{'id'}, 5 );
	}
}


# Removes a kick record from the database
sub remove_kick
{
	my $name = lc(shift);		$name =~ s/'/''/g;

	my @array = brdatabase::execute_query( "SELECT * FROM kicks WHERE LOWER(name) = '$name'" );
	if ( scalar(@array) > 0 )
	{
		brdatabase::execute_query ( "DELETE FROM kicks WHERE LOWER(name) = '$name'", 1 );
		return 1;
	}
	return 0;
}


# Checks if the specified player is kicked, and if they are kicks them out
sub check_kicks
{
	my $name = shift;			$name =~ s/'/''/g;

	# Before we start clear any out of date kicks (older than 24 hours)
	brdatabase::execute_query ( "DELETE FROM kicks WHERE timestamp <= " . (time()-86400), 1 );

	# Data should already be in the playerData array - Exact match only
	my ( $result, %player ) = playerData::getPlayerData ( $name, 1 );
	return 0 if ( $result != 1 );
	return 1 if ( $player{'kicked'} && $player{'kicked'} == 1 );

	# Now look for any entries in the kicks table
	my $serial = ( exists ( $player{'serial'} ) ) ? "OR serial = '$player{serial}'" : "";
	my @array = brdatabase::execute_query( "SELECT * FROM kicks WHERE LOWER(name) = '".lc($player{'name'})."' OR ip = '$player{ip}' $serial" );

	if ( scalar(@array) > 0 )
	{
		my ( undef, undef, $day, $hour, $minute, undef ) = BRTime_To_Date( $array[0]->{'timestamp'} );
		my ( undef, undef, $daynow, undef, undef, undef ) = BRTime_To_Date( time() );

		my $kickday = ( $daynow == $day ) ? "today" : "yesterday";
		my $reasonSuffix = ( lc($player{'name'}) eq lc($array[0]->{'name'}) ) ? "" : ( $player{'ip'} eq $array[0]->{'ip'} ) ? " (IP Matched)" : " (Serial Matched)";
		RenRem::RenRemCMD( "msg [BR] $player{name} was KICKED $kickday at $hour.$minute by ".$array[0]->{'kicker'}." for: ".$array[0]->{'reason'}.$reasonSuffix );

		if ( get_module( "bhs" ) )
			{ RenRem::RenRemCMD( "pamsg $player{id} You were KICKED $kickday at $hour.$minute by ".$array[0]->{'kicker'}." for: ".$array[0]->{'reason'}.". You may return to the server in ".((86400-(time()-$array[0]->{'timestamp'}))/60)." minutes" ); }

		RenRem::RenRemCMD( "kick $player{id}" );
		playerData::setKeyValue ( $player{'id'}, "kicked", 1 );
		return 1;
	}

	return 0;
}




###################################################
####
## Functions related to the banning system
####
###################################################

# Bans a player from the server and records it in the database
#
# Parameters
#	Target				ID or name of player to be banned
#	banner				Name of the person who banned them
#	Reason				Reason for them being banning them from the server
sub ban_player
{
	my $target = shift;					$target =~ s/'/''/g;
	my $banner = shift;					$banner =~ s/'/''/g;
	my $reason = shift;					$reason =~ s/'/''/g;

	# Get data for the player to be banned
	my ( $result, %player ) = playerData::getPlayerData ( $target, 1 );
	return if ( $result != 1 );

	# Prepare the message for the server announcement and message to the banned player
	my $message = 'been banned from the server by '.$banner.' for '.$reason;

	# Send the server announcement message
	RenRem::RenRemCMD ( 'msg [BR] '.$player{'name'}.' has '.$message );

	# If using SSGM >= 4.0 then use the ban console command (1 second delay to allow the pamsg to reach them)
	if ( $brconfig::ssgm_version >= 4 )
		{ RenRem::RenRemCMDtimed ( 'ban '.$player{'id'}.' '.$reason, 1 ); }

	# Otherwise use the kick command to evict them (1 second delay to allow the pamsg to reach them)
	else
	{
		# Send the page to the banned player (under SSGM >= 4 the ban console command handles)
		RenRem::RenRemCMD ( 'pamsg '.$player{'id'}.' You have '.$message );

		RenRem::RenRemCMDtimed ( 'kick '.$player{'id'}, 1 );
	}


	# Create a record of the ban
	record_ban ( $player{'name'}, $banner, $reason, $player{'ip'}, $player{'serial'} );
}




# Creates a ban record in the database
#
# Parameters
#	Player				Name to be banned from the server
#	banner				Name of the person who banned them
#	Reason				Reason for them being banning them from the server
#	Serial				Serial hash to be banned from the server
#	IP					IP Address to be banned from the server
sub record_ban
{
	my $name = shift;					$name =~ s/'/''/g;
	my $banner = shift;					$banner =~ s/'/''/g;
	my $reason = shift;					$reason =~ s/'/''/g;
	my $ip = shift;
	my $serial = shift;

	my $timestamp = time();
	brdatabase::execute_query ( "INSERT INTO bans ( name, ip, serial, banner, reason, timestamp ) VALUES ( '$name', '$ip', '$serial', '$banner', '$reason', '$timestamp' )", 1 );

	# Get the ban id
	my @maxBanID = brdatabase::execute_query ( "SELECT MAX(id) as id FROM bans" );
	my $banid = $maxBanID[0]->{'id'};

	# Write the ban to the logs table
	if ( length($name) > 0 )
		{ brdatabase::writeLog ( 2, "[BAN] $name ($ip) was banned by $banner for '$reason'. (Ban ID $banid)" ); }
	elsif ( $ip =~ m/\.\*/ )
		{ brdatabase::writeLog ( 2, "[BAN] IP range $ip was banned by $banner for '$reason'. (Ban ID $banid)" ); }
	else
		{ brdatabase::writeLog ( 2, "[BAN] IP $ip was banned by $banner for '$reason'. (Ban ID $banid)" ); }
}



sub is_banned
{
	my $name = shift;					$name =~ s/'/''/g;

	# Data should already be in the playerData array - Exact match only
	my ( $result, %player ) = playerData::getPlayerData ( $name, 1 );
	return if ( $result != 1 );


	# Generate query string
	my $whereCondition = "WHERE LOWER(name) = '".lc($name)."'";

	if ( $player{'serial'} )
		{ $whereCondition .= " OR serial = '".$player{'serial'}."'"; }

	if ( $player{'ip'} ne "X.X.X.X" )
	{
		$whereCondition .= " OR ip = '".$player{'ip'}."'";

		# IP range matching
		if ( $player{'ip'} =~ m/(\d+\.\d+\.\d+)\.\d+/ )
			{ $whereCondition .= " OR ip = '".$1.".*'"; }
	}

	# Now run the query and see if we get any results
	my @bansArray = brdatabase::execute_query( "SELECT * FROM bans $whereCondition" );
	if (scalar(@bansArray) > 0)
	{
		my ( $year, $month, $day, $hour, $min, $sec ) = BRTime_To_Date( $bansArray[0]->{'timestamp'} );
		return ( 1, "'".$bansArray[0]->{'reason'}."' (Ban ID ".$bansArray[0]->{'id'}.")", $bansArray[0]->{'banner'}, "$month.$day.$year" );
	}


	# If we get down to here there were no bans found, so return 0.
	return 0;
}


###################################################
####
## Functions related to join messages (module join_messages)
####
###################################################

sub get_joinmessage
{
	my $name = lc(shift);
	$name =~ s/'/''/g;

	my @array = brdatabase::execute_query( "SELECT * FROM join_messages WHERE LOWER(name) = '$name'" );
	if ( scalar(@array) > 0 )
		{ return $array[0]->{'message'}; }
	return undef;
}

sub show_joinmessage
{
	my $name = shift;
	my $message = get_joinmessage($name);
	if ( defined($message) )
	{
		RenRem::RenRemCMD( "msg [$name] $message" );
	}
}

sub set_joinmessage
{
	my $name = lc(shift);
	my $message = shift;
	$name =~ s/'/''/g;
	$message =~ s/'/''/g;

	my @count = brdatabase::execute_query( "SELECT * FROM join_messages WHERE LOWER(name) = '$name'" );
	if (scalar(@count) == 0)
		{ brdatabase::execute_query( "INSERT INTO join_messages ( name, message ) VALUES ( '$name','$message' )", 1 ); }
	else
		{ brdatabase::execute_query( "UPDATE join_messages SET message = '$message' WHERE LOWER(name) = '$name'", 1 ); }
}


###################################################
####
## Various functions for controlling and querying
## module information
####
###################################################

## Fetches current module information from the database
sub load_modules
{
	@modules = brdatabase::execute_query( "SELECT * FROM modules ORDER BY name ASC" );
}


## Changes the status of a module to on or off
sub set_module
{
	my $module = lc(shift);
	my $status = shift;

	brdatabase::execute_query( "UPDATE modules SET status = $status WHERE LOWER(name) = '$module'", 1 );
	load_modules();
}


## Used by outside files to get the current module statuses
sub get_modules
{
	return ( @modules );
}


## Gets the status of a specified module
sub get_module
{
	my $module = shift;

	foreach ( @modules )
	{
		if ( $_->{name} eq $module )
		{
			return $_->{'status'};
		}
	}
}


## Gets the description of a specified module
sub get_module_description
{
	my $module = lc( shift );

	foreach ( @modules )
	{
		if ( lc( $_->{name} ) eq $module )
		{
			return ( 1, $_->{'description'} );
		}
	}

	return 0;
}


## Used when BRenBot is loaded to ensure all modules are present
## in the database, and adds them if they are not found
sub check_modules
{
	my %modulesList =
	(
		teammessages => "Displays team (f3) chat messages in IRC",
		join_messages => "Enables !setjoin / !viewjoin on the server",
		gamespy_players => "Broadcast this server to the GameSpy Arcade server browser",
		gamelog => "Enables support for the SSGM gamelog",
		bhs => "Support for Tiberian Technologies / Blackhand Studios FDS library (ppage, pamsg etc)",
		new_gi => "!gi shows info on one line instead of five lines",
		donate => "Allows players to donate money to their teammates (bhs only)",
		map_settings => "Allows customising server settings on a per-map basic. Includes time limit, mine limit, vehicle limit, donate limit and map rules.",
		ssgmlog => "Support for SSGM extended logging (Beacon, Game Results, BW alerts etc)",
		autobalance => "Enables the autobalance module, which attempts to make teams even when a new map loads.",
		BRenBot_dll => "Enables support for extended console commands inside BRenBot.dll"
	);

	while ( (my $k, my $v) = each %modulesList )
	{
		my @array = brdatabase::execute_query( "SELECT * FROM modules WHERE name = '$k'" );
		if ( scalar(@array) == 0 )
		{
			# Module not found, add it to the database and set it to enabled, not locked
			my $query = "INSERT INTO modules ( name, status, description, locked ) VALUES ('$k', 1, '$v', 0 )";
			brdatabase::execute_query( $query, 1 );
		}
	}
}





###################################################
####
## Functions related to getting and storing players
## bandwidth data
####
###################################################

sub get_bandwidth
{
	my ($playerid) = @_;

	if (!$playerid)
	{
		my %playerlist = playerData::getPlayerList();
		while ( my ( $id, $player ) = each ( %playerlist ) )
		{
			RenRem::RenRemCMD("GETBW $id");
		}
	}
	else
	{
		RenRem::RenRemCMD("GETBW $playerid");
	}
}



###################################################
####
## Functions for getting the mod status of a player
####
###################################################

# Returns true if the user is a half mod, false otherwise
sub IsHalfMod
{
	my ($name)=lc($_[0]);

	if ( $brconfig::halfMods{$name} )
	{
		# Check they are authed
		my $authStatus = brAuth::GetAuthState( $name );

		if ( $authStatus == 1 || ( $brconfig::config_moderators_force_auth == 0 && $authStatus == 2 ) )
		{ return 1; }
	}

	return 0;
}

# Returns true if the user is a full mod, false otherwise
sub IsFullMod
{
	my ($name)=lc($_[0]);

	if ( $brconfig::fullMods{$name} )
	{
		# Check they are authed
		my $authStatus = brAuth::GetAuthState( $name );

		if ( $authStatus == 1 || ( $brconfig::config_moderators_force_auth == 0 && $authStatus == 2 ) )
		{ return 1; }
	}

	return 0;
}

# Returns true if the user is an admin, false otherwise
sub IsAdmin
{
	my ($name)=lc($_[0]);

	if ( $brconfig::admins{$name} )
	{
		# Check they are authed
		my $authStatus = brAuth::GetAuthState( $name );

		if ( $authStatus == 1 || ( $brconfig::config_moderators_force_auth == 0 && $authStatus == 2 ) )
		{ return 1; }
	}

	return 0;
}

# Returns true if the user is a temporary mod, false otherwise
sub IsTempMod
{
	my $name = lc($_[0]);

	if ( $main::tempMods{$name} )
	{
		# Check they are authed
		if ( brAuth::GetAuthState($name) != 0 )
		{ return 1; }
	}

	return 0;
}



###################################################
####
## Functions for adding or removing temp moderators
####
###################################################

sub AddTempModerator
{
	my ($name) = @_;

	my ( $result, %player ) = playerData::getPlayerData( $name );
	if ( $result == 1 )
	{
		$main::tempMods{lc($player{'name'})} = $player{'name'};
		RenRem::RenRemCMD( "msg [BR] $player{'name'} has been made a temporary game moderator." );
	}
	elsif ( $result == 2 )
	{
		RenRem::RenRemCMD( "msg [BR] $name is not unique, please be more specific." );
	}
	else
	{
		RenRem::RenRemCMD( "msg [BR] $name was not found ingame." );
	}

	return;
}

sub DelTempModerator
{
	my ($name) = @_;

	my ( $result, %player ) = playerData::getPlayerData( $name );
	if ( $result == 1 )
	{
		if ( $main::tempMods{lc($player{'name'})} )
		{
			delete $main::tempMods{lc($player{'name'})};
			RenRem::RenRemCMD( "msg $player{name} is no longer a temporary game moderator." );
			return;
		}

		RenRem::RenRemCMD( "msg [BR] $player{'name'} was not a temporary game moderator to begin with." );
	}
	elsif ( $result == 2 )
	{
		RenRem::RenRemCMD( "msg [BR] $name is not unique, please be more specific." );
	}
	else
	{
		RenRem::RenRemCMD( "msg [BR] $name has not been found." );
	}

	return;
}





###################################################
####
## Functions related to automatic announcements system
####
###################################################


# Initialises the automatic announcements system and creates the session
sub AutoAnnounce_Init
{
	# If the message interval is configured to 0 then we do not need to create the session as it is disabled
	if ( $brconfig::config_autoannounceinterval > 0 )
	{
		POE::Session->create
		( inline_states =>
			{
				_start => sub
				{
					$_[KERNEL]->alarm( tick => int( time() ) + $brconfig::config_autoannounceinterval );
				},
				tick => sub
				{
					AutoAnnounce_DoAnnoucement();
					$_[KERNEL]->alarm( tick => int( time() ) + $brconfig::config_autoannounceinterval );
				},
			},
		);
	}
}


# Randomly chooses an announcement from the announcements file and sends it to the server
sub AutoAnnounce_DoAnnoucement
{
	my $index        = rand @brconfig::autoannounce;
	my $announcement = $brconfig::autoannounce[$index];

	if ($announcement =~ /TIMECOOKIE/i)
	{
		$announcement = modules::get_date_time( "The local server time is hh:mm:ss" );
	}

	# Abort if selected announcement requires results of previous match and they are
	# not available
	if (($announcement =~ /MOST.+COOKIE/i) and (!($results::mostkills)))
	{
		return;
	}

	if ($announcement =~ /MOSTKILLCOOKIE/i)
	{
		$announcement = $results::mostkills;
	}

	if ($announcement =~ /MOSTDEATHCOOKIE/i)
	{
		$announcement = $results::mostdeaths;
	}

	if ($announcement =~ /MOSTKDCOOKIE/i)
	{
		$announcement = $results::mostkd;
	}

	if ( serverStatus::getCurrentPlayers() > 0 && length($announcement) > 0 )
	{
		RenRem::RenRemCMD( "msg [BR] $announcement" );
	}
}






###################################################
####
## Miscellaneous functions
####
###################################################

# Displays a runtime error in the console window and/or the admin IRC channel
#
# \param[in] $target
#   Optional. Specify the target for the error message. Valid values are 'b' for both console and
#   IRC, 'i' for IRC only and 'c' for console only. If not defined both outputs are used.
sub display_error
{
	my $error = shift;
	return if (!$error);
	my $target = shift;

	if ( !defined($target) || $target eq 'b' || $target eq 'i' )
		{ brIRC::ircmsg ( "Runtime Error: $error", "A" ); }
	if ( !defined($target) || $target eq 'b' || $target eq 'c' )
		{ modules::console_output ( "[ERROR] $error" ); }
}

# Searches the list of installed maps to determine if a specified map is installed. Under SSGM >=
# 4.0 the 'installed' maps are those returned by the listgamedefs console command.
#
# \param[in] $mapname
#   Name or partial name of the map to search for
#
# \return
#   List of ($result,$mapname) where $result indicates the success or failure of the search and, if
#   successful, $mapname contains the full name of the map. Possible values of $result are 0 (not
#   found), 1 (success) or 2 (multiple possible matches, none exact).
sub FindInstalledMap
{
	my $search = lc($_[0]);
	my $result = 0;
	my $mapname;

	foreach (@brconfig::installed_maps)
	{
		if ($_ =~ m/(.*?)$search(.*?)/gi)
		{
			# If this is an exact match then this is our result
			if ( $search eq lc($_) )
				{ return (1,$_); }

			# Not an exact match, if we have not found any previous match then this is a candiate
			# for our result
			if ( $result == 0 )
			{
				$result = 1;
				$mapname = $_;
			}

			# Otherwise we already have a candidate result so there must be multiple possible
			# matches, set result to 2. NB: Don't simple return here as we could yet find an exact
			# match futher on in the installed maps list
			else
			{
				$result = 2;
				undef $mapname;
			}
		}
	}

	# Return result
	return ($result,$mapname);
}


# Sets the next map in the rotation to the specified map
#
# \param[in] $mapname
#   Full or unique partial name of the map to set
#
# \return
#   Array of ($result,$mapname) where $result which will be one of 0 (map not found), 1 (success),
#   2 (multiple possible non-exact map matches) or 3 (failed to set map) and $mapname will be the
#   full name of the map that was set if successful or undef otherwise
sub SetNextMap
{
	# Find the mapname
	my($findresult,$mapname) = FindInstalledMap(shift);
	if ( $findresult != 1 ) { return ($findresult,undef); }

	# For SSGM <= 4.0 we need to re-write the FDS config file with the new rotation
	elsif ( $brconfig::ssgm_version < 4 )
	{
		my $result = SetNextMap_WriteNewConfig($mapname);
		if ( $result == 0 ) { return (3,$mapname); }
	}

	else
	{
		# Get the index of the next map in the rotation
		my $nextmap = GetNextMap();
		return (3,$mapname) if (!$nextmap);

		# Send a RenRemCMD to instruct the Resource Manager to change the next map
		modules::console_output ( "Setting map at index $nextmap->{id} to $mapname." );
		RenRem::RenRemCMD ( "mlistc $nextmap->{id} $mapname" );

		# Unless we have already recorded the fact the nextmap has been changed during this map set
		# the relevant flag in the database (with the value 4 instead of 1 to indicate a Resource
		# Manager update) and store the details of the map that was replaced so we can restore it
		if ( !brdatabase::get_global( 'nextmap_changed' ) )
		{
			print "DEBUG: Recording map change details\n";
			brdatabase::set_global( 'nextmap_changed', '4' );

			# Record the details of the map we replaced
			brdatabase::set_global( 'nextmap_changed_id', $nextmap->{'id'} );
			brdatabase::set_global( 'nextmap_changed_mapname', $nextmap->{'mapname'} );
		}

		# Update the rotation
		foreach (@brconfig::maplist)
		{
			if ( $_->{'id'} == $nextmap->{'id'} )
			{
				$_->{'mapname'} = $mapname;
				last;
			}
		}
	}

	# Report success
	return (1,$mapname);
}


# Sets the next map in the rotation to the specified map
sub SetNextMap_WriteNewConfig
{
	my $mapname = shift;

	# Read in the existing contents of the config file
	my $config;
	open ( FDSfile, $brconfig::config_fdsconfigfile );
	while ( <FDSfile> ) { $config .= $_; }
	close ( FDSfile );

	# Get the name and ID of the current next map
	my $nextmap = GetNextMap();
	return 0 if (!$nextmap);

	# If we have already changed the next map once we must NOT backup the FDS config again
	if ( brdatabase::get_global('nextmap_changed') )
	{
		modules::console_output ( "Map rotation has already been changed once this map, skipping backup of FDS config file." );
	}
	else
	{
		modules::console_output ( "Backing up FDS config file." );
		open (FDSfile, ">svrcfg_cnc.ini.old");
		print FDSfile $config;
		close (FDSfile);
	}

	modules::console_output ( "Setting MapName$nextmap->{id} to $mapname." );
	$config =~ s/MapName$nextmap->{id}=.+/MapName$nextmap->{id}=$mapname/g;

	open (FDSfile, ">$brconfig::config_fdsconfigfile");
	print FDSfile $config;
	close (FDSfile);

	# Record the fact that we have changed the next map
	brdatabase::set_global( 'nextmap_changed', '1' );

	# Read the new map list into the brconfig maplist
	brconfig::readServerSettings();

	return 1;
}




sub GetNextMap
{
	# Get map number from the gameinfo array
	my $currentMap = serverStatus::getMapNum();
	my $nextmap = ( defined $brconfig::maplist[$currentMap+1] )
		? $brconfig::maplist[$currentMap+1]
		: $brconfig::maplist[0];


	return $nextmap if ( defined $nextmap );

	return undef;
}

sub padd_string
{
	my $minlength = shift;
	my $string	= shift;

	my $output = $string;

	for (my $i=1; $i <= $minlength - length($string); $i++)
	{
		$output .= " ";
	}
	return $output;
}

sub GetRotation
{
	my @array;
	my $currentMap = serverStatus::getMapNum();
	push ( @array, "The map rotation includes:" );

	for (my $i =0; $i < scalar(@brconfig::maplist); $i +=4 )
	{
		my $mapName1 = ( $i == $currentMap )
			? '[' . $brconfig::maplist[$i]->{'mapname'} . ']'
			: $brconfig::maplist[$i]->{'mapname'};

		my $mapName2 = ( ( $i+1 ) == $currentMap )
			? '[' . $brconfig::maplist[$i+1]->{'mapname'} . ']'
			: ($i+1 < scalar(@brconfig::maplist) ) ? $brconfig::maplist[$i+1]->{'mapname'} : "";

		my $mapName3 = ( ( $i+2 ) == $currentMap )
			? '[' . $brconfig::maplist[$i+2]->{'mapname'} . ']'
			: ($i+2 < scalar(@brconfig::maplist) ) ? $brconfig::maplist[$i+2]->{'mapname'} : "";

		my $mapName4 = ( ( $i+3 ) == $currentMap )
			? '[' . $brconfig::maplist[$i+3]->{'mapname'} . ']'
			: ($i+3 < scalar(@brconfig::maplist) ) ? $brconfig::maplist[$i+3]->{'mapname'} : "";

		$mapName1 =~ s/\.mix//i;			$mapName1 =~ s/c\&c_//i;
		$mapName2 =~ s/\.mix//i;			$mapName2 =~ s/c\&c_//i;
		$mapName3 =~ s/\.mix//i;			$mapName3 =~ s/c\&c_//i;
		$mapName4 =~ s/\.mix//i;			$mapName4 =~ s/c\&c_//i;

		push ( @array, "$mapName1  $mapName2  $mapName3  $mapName4" );
	}
	return @array;

}

sub GetInstalledMaps
{
	my @array;
	push (@array, "The following maps are installed:");
	for (my $i =0; $i < scalar(@brconfig::installed_maps); $i +=4)
	{
		my $map1 = $brconfig::installed_maps[$i];
		my $map2 = ($i+1 < scalar(@brconfig::installed_maps)) ? $brconfig::installed_maps[$i+1] : "";
		my $map3 = ($i+2 < scalar(@brconfig::installed_maps)) ? $brconfig::installed_maps[$i+2] : "";
		my $map4 = ($i+3 < scalar(@brconfig::installed_maps)) ? $brconfig::installed_maps[$i+3] : "";

		push (@array, "$map1 $map2 $map3 $map4");
	}
	return @array;
}

sub IsMapInRotation
{
	# returns 1 if the map is in the rotation
	my $map = shift;
	foreach (@brconfig::maplist)
	{

	  	if ($map eq $_->{'mapname'})
	  	{
	  		return 1;
	  	}

	}
	return 0;
}












# This routine gets the current date, and spits out
# the proper current logfile name we should be opening.
#
# You pass it a string (filename) and it automatically
# replaces MM DD YYYY HH MM SS with the current time digits.
sub get_date_time
{
	my $string = $_[0];

	my ($second,$minute,$hour,$day,$month,$year,$weekday,$yearday,$dst_flag)=localtime(time);

	$year  += 1900;
	my $year_short = substr ( $year, 2 );
	$month += 1;

	if ($second < 10) {$second ="0".$second;}
	if ($hour   < 10) {$hour   ="0".$hour;}
	if ($minute < 10) {$minute ="0".$minute;}

#	The actual substition of the matched strings for values.
	$string =~ s/YYYY/$year/;
	$string =~ s/YY/$year_short/;
	$string =~ s/DD/$day/;
	$string =~ s/MM/$month/;
	$string =~ s/ss/$second/;
	$string =~ s/hh/$hour/;
	$string =~ s/mm/$minute/;

	return $string;
}

sub get_linux_date_time
{
	my $string = $_[0];

	my ($second,$minute,$hour,$day,$month,$year,$weekday,$yearday,$dst_flag)=localtime(time);

	my $year_short = substr ( $year, 2 );

	if ($second < 10) {$second ="0".$second;}
	if ($hour   < 10) {$hour   ="0".$hour;}
	if ($minute < 10) {$minute ="0".$minute;}

#	The actual substition of the matched strings for values.
	$string =~ s/YYYY/$year/;
	$string =~ s/YY/$year_short/;
	$string =~ s/DD/$day/;
	$string =~ s/MM/$month/;
	$string =~ s/ss/$second/;
	$string =~ s/hh/$hour/;
	$string =~ s/mm/$minute/;

	return $string;
}

sub get_past_date_time
# This routine gets the current date, and spits out
# the proper current logfile name we should be opening.
#
# You pass it a string (filename) and it automatically
# replaces MM DD YYYY HH MM SS with the current time digits.
#
# !!This routine will not work without the Time::localtime function/module!!

{
	my $string = $_[0];
	my $timestamp = $_[1];


	my ($second,$minute,$hour, $day,$month,$year, $weekday,$yearday,$dst_flag)=localtime($timestamp);

	$year = $year + 1900;
	my $year_short = substr ( $year, 2 );
	$month++;

#   Convert single digits to double digits
#   ie "1" becomes "01".

	if ($month  < 10) {$month  ="0".$month;}
	if ($day	< 10) {$day	="0".$day;}
	if ($second < 10) {$second ="0".$second;}
	if ($hour   < 10) {$hour   ="0".$hour;}
	if ($minute < 10) {$minute ="0".$minute;}

#   The actual substition of the matched strings for values.
	$string =~ s/YYYY/$year/;
	$string =~ s/YY/$year_short/;
	$string =~ s/DD/$day/;
	$string =~ s/MM/$month/;
	$string =~ s/ss/$second/;
	$string =~ s/hh/$hour/;
	$string =~ s/mm/$minute/;

	return $string;
}



# Converts a timestamp to a date using Time_To_Date and then formats with with
# prefixed 0's
sub BRTime_To_Date
{
	my ( $year, $month, $day, $hour, $min, $sec ) = Time_to_Date( shift );

	# Prefix each with a 0 if its less than 10
	if ($month  < 10) {$month  ="0".$month;}
	if ($day	< 10) {$day	="0".$day;}
	if ($sec	< 10) {$sec ="0".$sec;}
	if ($hour   < 10) {$hour   ="0".$hour;}
	if ($min	< 10) {$min ="0".$min;}

	return ( $year, $month, $day, $hour, $min, $sec );
}



# Gets the SERVERS ip address
sub get_ip
{
	my $config_ip;
	my $config_botmode = $brconfig::config_botmode;

	if ($config_botmode eq "LFDS")
	{
		my $ip = `/sbin/ifconfig eth0`;
		if ( $ip =~ m/inet ad(.+?):(.+?)\s/i )
		{
			$config_ip = $2;
		}
	}
	else
	{
		my $ip = `ipconfig`;
		$ip =~ /IP Address.+?(\d+.\d+.\d+.\d+)/;
		$config_ip=$1;
	}

	return $config_ip;
}



# Takes a playername and add's moderator symbols (if applicable)
sub parseModName
{
	my $name		= shift;
	my $addIRCcodes	= shift;
	my $returnName	= $name;

	# If we want IRC codes set them up now
	my $bold = "";		my $underline = "";
	if ( $addIRCcodes eq '1' )
	{
		$bold = "";			$underline = "";
	}

	# If moderator symbols are enabled show them, otherwise dont
	if ( $brconfig::config_moderator_symbols == 1)
	{
		$returnName = $underline.$brconfig::config_temp_mod_symbol.$name.$underline if ( IsTempMod( $name ) );
		$returnName = $bold.$brconfig::config_half_mod_symbol.$name.$bold if ( IsHalfMod( $name ) );
		$returnName = $bold.$brconfig::config_full_mod_symbol.$name.$bold if ( IsFullMod( $name ) );
		$returnName = $bold.$brconfig::config_admin_symbol.$name.$bold if ( IsAdmin( $name ) );
	}
	else
	{
		$returnName=$underline.$name.$underline if ( IsTempMod( $name ) );
		$returnName=$bold.$name.$bold if ( IsHalfMod( $name ) or IsFullMod( $name ) or IsAdmin( $name ) );
	}

	return $returnName;
}



###################################################
####
## Functions for communicating with users
####
###################################################

# Picks best method of paging based on server's bhs.dll, and players bhs.dll
sub pagePlayer
{
	my $playername	= shift;
	my $sender		= shift;
	my $message		= shift;

	my ( $result, %player ) = playerData::getPlayerData ( $playername );
	if ( $result == 1 )
	{
		# CMSG supported if player and server have bhs.dll >= 2.6
		if ( $brconfig::enableCmsg && modules::get_module( "bhs" )
			&& $player{'scriptsVersion'} >= 2.6 && $brconfig::serverScriptsVersion >= 2.6 )
		{
			RenRem::RenRemCMD ( "cmsgp $player{id} 0,255,0 \(PM from $sender): $message" );
		}
		elsif ( modules::get_module( "bhs" ) )
		{
			RenRem::RenRemCMD ( "ppage $player{id} \(PM from $sender): $message" );
		}
		else
		{
			RenRem::RenRemCMD ( "page $player{name} \(PM from $sender): $message" );
		}
	}

	return $result;
}



###################################################
####
## Map specific settings
####
###################################################

sub loadMapSettings
{
	my $error;
  eval
  {
    no warnings 'deprecated';  # Suppress XML::Parser::Expat warning about tied handles...
    $mapSettings = XMLin( "mapsettings.xml", SuppressEmpty => 1, ForceArray => [ 'map' ] );
  }
	or $error = $@;

	if ( $error )
	{
		modules::console_output ( "The following error occured reading mapsettings.xml: $error" );
		return;
	}

	# Under Win32 replace all &amp; with & in map names
	while ( my ($mapname, $data) = each %{$mapSettings->{'map'}} )
	{
		my $mapname_new = $mapname;
		$mapname_new =~ s/&amp;/&/gi;
		if ( $mapname_new ne $mapname )
		{
			$mapSettings->{'map'}->{$mapname_new} = $data;
			delete $mapSettings->{'map'}->{$mapname};
		}
	}

#	use Data::Dumper;
#	open ( DATA_DUMP, '>xmlmapsettings.txt' );
#	print DATA_DUMP Dumper($mapSettings);
#	close DATA_DUMP;

	# Ensure we have default settings for everything
	if ( !exists($mapSettings->{'default'}->{'time'}) )			{ $mapSettings->{'default'}->{'time'} = 30; }
	if ( !exists($mapSettings->{'default'}->{'mines'}) )		{ $mapSettings->{'default'}->{'mines'} = 30; }
	if ( !exists($mapSettings->{'default'}->{'donatelimit'}) )	{ $mapSettings->{'default'}->{'donatelimit'} = 0; }
	if ( !exists($mapSettings->{'default'}->{'vehicles'}) )		{ $mapSettings->{'default'}->{'vehicles'} = 8; }
	if ( !exists($mapSettings->{'default'}->{'rules'}) )		{ $mapSettings->{'default'}->{'rules'} = ""; }
}


sub applyMapSettings
{
	my $map = shift;
	my $applyTime = shift;

	if ( get_module ( "map_settings" ) != 1 )
		{ return; }

	my $new_time		= $mapSettings->{'default'}->{'time'};
	$minelimit			= $mapSettings->{'default'}->{'mines'};
	$vehiclelimit		= $mapSettings->{'default'}->{'vehicles'};
	$donatelimit		= $mapSettings->{'default'}->{'donatelimit'};
	$maprules			= $mapSettings->{'default'}->{'rules'};

	# Get any map specific settings
	if ( exists $mapSettings->{'map'}->{$map} )
	{
		if ( IsNumeric($mapSettings->{'map'}->{$map}->{'time'}) )			{ $new_time = $mapSettings->{'map'}->{$map}->{'time'}; }
		if ( IsNumeric($mapSettings->{'map'}->{$map}->{'mines'}) )			{ $minelimit = $mapSettings->{'map'}->{$map}->{'mines'}; }
		if ( IsNumeric($mapSettings->{'map'}->{$map}->{'vehicles'}) )		{ $vehiclelimit = $mapSettings->{'map'}->{$map}->{'vehicles'}; }
		if ( IsNumeric($mapSettings->{'map'}->{$map}->{'donatelimit'}) )	{ $donatelimit = $mapSettings->{'map'}->{$map}->{'donatelimit'}; }
		if ( exists($mapSettings->{'map'}->{$map}->{'rules'}) )				{ $maprules = $mapSettings->{'map'}->{$map}->{'rules'}; }
	}

	# Apply all settings
	if ( $applyTime != 0 )
		{ RenRem::RenRemCMD ( "time ".$new_time*60 ); }
	RenRem::RenRemCMD ( "mlimit $minelimit" );
	RenRem::RenRemCMD ( "vlimit $vehiclelimit" );

	my $message = "Settings for $map: Time Limit: $new_time, Mine Limit: $minelimit, Vehicle Limit: $vehiclelimit.";
	if ( $donatelimit > 0 && get_module( "donate" ) == 1 )
		{ $message .= "Donations are allowed after $donatelimit minutes."; }
	RenRem::RenRemCMDtimed ( "msg [BR] $message", 5 );
	
	if ( $maprules )
		{ RenRem::RenRemCMDtimed ( "msg [BR] Special rules for $map: $maprules", 5 ); }
}






# Return true if a value is numeric
sub IsNumeric
{
	my $number = shift;

	return (defined($number) && $number =~ /^(\d+\.?\d*|\.\d+)$/);
}








# Process autobalance, called on mapload
sub do_autobalance
{
	# Is autobalance enabled?
	if ( !modules::get_module( "autobalance" ) || !modules::get_module( "bhs" ) ) { return; }

	# Attempts to automatically balance the teams 5 seconds after the map has loaded
	POE::Session->create
	( inline_states =>
		{
			_start => sub
			{
				# Make sure we have up to date game info when it calls the alarm
				RenRem::RenRemCMD ( "game_info" );
				RenRem::RenRemCMD ( "player_info" );
				$_[HEAP]->{next_alarm_time} = int( time() ) + 5;
				$_[KERNEL]->alarm( tick => $_[HEAP]->{next_alarm_time} );
			},
			tick => sub
			{
				return if ( serverStatus::getCurrentPlayers() == 0 );
				modules::console_output ( "Starting autobalance...", 1 );

				# Get difference
				my $difference = ( serverStatus::getPlayers_GDI() - serverStatus::getPlayers_Nod() );
				#print "DEBUG: Difference is $difference, gdi has $gameinfo{'gdi_players'} and nod has $gameinfo{'nod_players'}\n";

				if ( $difference <= 1 && $difference >= -1 )
				{
					modules::console_output ( "Teams are balanced, no action necessary.", 3 );
					return;
				}
				else
				{
					if ( $difference > 1 )
					{
						modules::console_output ( "GDI has more players, balancing teams...", 3 );

						my %playerlist = playerData::getPlayerList();
						while ( my ( $id, $player ) = each ( %playerlist ) )
						{
							if ( $player->{'side'} eq "GDI" || $player->{'side'} eq "All" )
							{
								my $loaded = gamelog::get_player( $player->{'name'} );
								if ( $loaded && $loaded->{'name'} eq $player->{'name'} )
								{
									modules::console_output ( "Swapping $player->{name} from GDI to Nod." );
									RenRem::RenRemCMD( "team2 $player->{id} 0" );
									RenRem::RenRemCMD( "msg $player->{name} has been automatically changed to Nod to balance the teams." );
									modules::pagePlayer( $player->{'id'}, "BRenBot", "You have been automatically moved to Nod to balance the teams." );
									$difference -= 2;
								}
							}
							last unless ( $difference > 1 )
						}
					}
					else
					{
						modules::console_output ( "Nod has more players, balancing teams...", 3 );

						my %playerlist = playerData::getPlayerList();
						while ( my ( $id, $player ) = each ( %playerlist ) )
						{
							if ( $player->{'side'} eq "NOD" || $player->{'side'} eq "Sov" )
							{
								my $loaded = gamelog::get_player( $player->{'name'} );
								if ( $loaded && $loaded->{'name'} eq $player->{'name'} )
								{
									modules::console_output ( "Swapping $player->{name} from Nod to GDI." );
									RenRem::RenRemCMD( "team2 $player->{id} 1" );
									RenRem::RenRemCMD( "msg $player->{name} has been automatically changed to GDI to balance the teams." );
									modules::pagePlayer( $player->{'id'}, "BRenBot", "You have been automatically moved to GDI to balance the teams." );
									$difference += 2;
								}
							}
							last unless ( $difference < -1 )
						}
					}

					modules::console_output ( "Autobalancing finished." );
				}
			},
		},
	);
}

1;