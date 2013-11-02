#!/usr/bin/perl -w

use Time::HiRes qw(time);   # Used by POE to make alarms more accurate
use POE;
use POE::Kernel;
use POE::Session;
use POE qw/Wheel::FollowTail/;

## mac LFDS start ##
use POE::Component::Client::TCP;
use POE::Filter::Stream;
use IO::Socket;
## mac LFDS stop ##

use strict;

### DEBUGGING
# sub POE::Kernel::TRACE_DEFAULT () { 1 }
# sub POE::Kernel::TRACE_FILES () { 0 }
# sub POE::Kernel::TRACE_RETVALS () { 0 }
# sub POE::Kernel::TRACE_REFCNT () { 1 }
# sub POE::Kernel::TRACE_FILENAME () { 'memoryleakdebug.txt' }

# Define these before loading BRenBot modules as they may be used inside those modules
use constant BR_VERSION         => 1.53;
use constant BR_BUILD           => 17;
use constant BR_COPYRIGHT_YEAR  => "2003-2013";

# Load BRenBot modules
use modules;
use brconfig;
use RenRem;
use serverStatus;
use brdatabase;
use playerData;
use gamelog;
use bhs;
use commands;
use brIRC;
use renlog;
use results;
use plugin;
use ssgm;
use gamespy;
use brAuth;

# Disable buffering on STDIN / STDOUT
$| = 1;

# Print version info
modules::console_output ( "BRenBot ".BR_VERSION." build ".BR_BUILD );
modules::console_output ( "Copyright ".BR_COPYRIGHT_YEAR.", Tiberian Technologies. All rights reserved." );

# Main variables
my $start_time = time();
brdatabase::db_connect();
brconfig::init();

our %tempMods;                  # List of temporary moderators






###################################################
####
## Runs when a player joins, processes any necessary actions
####
###################################################

sub joinstuff
{
	my $name = shift;

	my ( $result, %player ) = playerData::getPlayerData( $name );
	if ( $result == 1 )
	{
		if ( !( renlog::check_banlist( $name ) ) && !( modules::check_kicks( $name ) ) )
		{
      if ( !plugin::call_core_override('playerjoin_msg', $name) )
        { brIRC::ircmsg( brIRC::colourise(11,"$name joined the game on team ").brTeams::get_colourised_name($player{'side'}) ); }

			# If they are authed, or not protected, show their mod status
			my $authed = brAuth::GetAuthState ( $player{'name'} );
			if ( $authed == 1 || $authed == 2 && !$brconfig::config_moderators_force_auth )
				{ ShowModJoinMessage( $player{'name'} ); }

			# BHS.dll version checking stuff
			if ( modules::get_module( "bhs" ) )
			{
				# If minimum scripts version is specified, or this map requires bhs.dll, trigger check in 5
				# seconds. Note that the playerData module takes care of requesting their scripts version
				if ( $brconfig::config_minimum_scripts_version > 0 || $brconfig::config_force_bhs_dll_map == 1 )
				{
					# Start check session
					POE::Session->create
					(
						inline_states =>
						{
							_start => sub
							{
								# Define how many extra chances they get if we don't recieve a response
								$_[HEAP]->{'chances'} = 2;

								# Start the clock
								$_[KERNEL]->alarm( tick => int(time()) + 2 );
							},
							tick => sub
							{
								# Has the version been provided yet?
								my ( $result, %player ) = playerData::getPlayerData( $player{'id'} );
								if ( $result == 1 )
								{
									if ( length($player{'scriptsVersion'}) > 0 )
									{
										# They have reported their version, but is it high enough? This check is not
										# applicable when bhs.dll is only required by the map
										if ( $player{'scriptsVersion'} < $brconfig::config_minimum_scripts_version && $brconfig::config_minimum_scripts_version > 0 )
										{
											modules::kick_player ( $player{'id'}, 'BRenBot', 'Scripts version '.$brconfig::config_minimum_scripts_version.' or higher is required to play on this server ('.$player{'scriptsVersion'}.' installed)' );
										}
									}

									# No version reported, do they have any chances left?
									elsif ( $_[HEAP]->{'chances'} > 0 )
									{
										$_[HEAP]->{'chances'}--;
										RenRem::RenRemCMD( "version $player{id}" );
										$_[KERNEL]->alarm( tick => int(time()) + 2 );
									}

									# No chances left... bye bye!
									else
									{
										modules::kick_player ( $player{'id'}, 'BRenBot', 'Scripts version '.$brconfig::config_minimum_scripts_version.' or higher is required to play on this server (pre 1.3 installed)' );
									}
								}
							} # end of tick
						} # end of inline states
					);
				}
			}


			# Process playerjoin plugin events
			my %args;
			$args{'id'}			= $player{'id'};
			$args{'nick'}		= $player{'name'};
			$args{'name'}		= $player{'name'};
			$args{'side'}		= $player{'side'};

			my @plugins = plugin::get_plugin_event( "playerjoin" );
			foreach ( @plugins )
			{
				my $plugin = $_;
				my $alias = "plugin_" . $plugin;
				$main::poe_kernel->post( $alias => "playerjoin" => \%args );
			}

			$#plugins = -1;
		} # end of banlist if
	}
} # end of joinstuff


# Shows an ingame message stating the moderator level of a given player. This is called once a
# player has authenticated themselves with the server. If the show_mod_join_message configuration
# setting is disabled no message will be shown.
sub ShowModJoinMessage
{
	return if ( $brconfig::show_mod_join_message == 0 );
	my $name = shift;

	my ( $result, %player ) = playerData::getPlayerData( $name );
	if ( $result == 1 )
	{
		if ( modules::IsAdmin( $name ) )
			{ RenRem::RenRemCMD( "msg $name is a server administrator." ); }

		elsif ( modules::IsFullMod( $name ) )
			{ RenRem::RenRemCMD( "msg $name is a full moderator." ); }

		elsif ( modules::IsHalfMod( $name ) )
			{ RenRem::RenRemCMD( "msg $name is a half moderator." ); }
	}
}


# Get the uptime for the bot, in seconds
sub get_uptime()
{
  return int(time()-$start_time);
}




###################################################
####
## Connect to RenRem
####
###################################################

# linux renrem session
if ( $brconfig::config_botmode eq "LFDS" )
{
	modules::console_output ( "Starting up renrem thread..." );
	POE::Component::Client::TCP->new
	(
		( InlineStates =>
			{	send_command => sub
				{
					my ( $kernel, $heap, $input ) = @_[ KERNEL, HEAP, ARG0 ];
					if ( $heap->{connected} )
					{
						$_[HEAP]->{server}->put( "$input\n" );
					}
					else
					{
						modules::console_output ( "Connection to renrem not possible. Can't send $input" );
					}
				}
			}
		), # end of inlinestates
		RemoteAddress => $brconfig::config_renrem_host,
		RemotePort    => $brconfig::config_renrem_port,
		#BindAddress   => $brconfig::config_server_ip,
		Filter        => "POE::Filter::Stream",
		Connected     => sub
		{
			$_[HEAP]->{banner_buffer} = [];
		},
		ConnectError => sub
		{
			my ( $kernel, $heap, $syscall, $errorcode, $error ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2 ];
			modules::console_output ( "Can\'t connect to LFDS Wrapper!\nsyscall: $syscall\nerrorcode: $errorcode\nerror: $error" );
			$_[KERNEL]->delay("reconnect" => 5);
		},
		ServerError => sub
		{
			my ( $kernel, $heap, $syscall, $errorcode, $error ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2 ];
			modules::console_output ( "Disconnected from LFDS Wrapper..\nsyscall: $syscall\nerrorcode: $errorcode\nerror: $error" );
			$_[KERNEL]->delay("reconnect" => 5);
		},
		ServerInput => sub
		{
			my ( $kernel, $heap, $input ) = @_[ KERNEL, HEAP, ARG0 ];
			push @{ $heap->{banner_buffer} }, $input;

			if ($input =~ "password")
			{
				$_[HEAP]->{server}->put("$brconfig::config_renrem_password\n");    # sends enter
			}
			elsif ($input =~ "accepted") {}
		},
		Alias => "renrem"
	);
} # end of if botmode = LFDS


###################################################
####
## Main startup, load all configuration settings
####
###################################################

serverStatus::init();
modules::load_modules();
modules::check_modules();
bhs::check_bhs_library();

if ( $brconfig::gamelog_in_ssgm != 1 && modules::get_module ( "gamelog" ) )
	{ gamelog::init(1); }

if ( modules::get_module( "ssgmlog" ) )
	{ ssgm::start(); }

# Get initial status of server
RenRem::RenRemCMD ( "game_info" );
RenRem::RenRemCMD ( "player_info" );
RenRem::RenRemCMD ( "sversion" );

# Load GSA if necessary
if ( modules::get_module( "gamespy_players" ) != 0 )
{
  gamespy::init();
}

# Load modules
modules::AutoAnnounce_Init();

# Initialize renlog
renlog::init();

# Load plugins
plugin::init();

# Load IRC once everything else is ready
brIRC::init();






###################################################
####
## Midnight session setup
## Switches logfiles at midnight
####
###################################################

POE::Session->create
( inline_states =>
	{
		_start => sub
		{
			$_[KERNEL]->yield("set_midnight_alarm");
		},
		set_midnight_alarm => sub
		{
			my ($sec,$min,$hour,undef,undef,undef,undef,undef,undef) = localtime(time);
			my $to_midnight = ((23-$hour)*3600)+((59-$min)*60)+(59-$sec)+2;

			# Set alarm for next midnight (or, rather, just after)
			$_[KERNEL]->alarm( midnight_alarm => int(time()) + $to_midnight );
		},
		midnight_alarm => sub
		{
			# Set next alarm call
			$_[KERNEL]->yield("set_midnight_alarm");

			# Output midnight message to console and IRC
			my (undef,undef,undef,$day,$month,$year,undef,undef,undef) = localtime(time);
			my $midnight_message = "It's midnight, the date is now $day/".($month+1)."/".($year+1900). (($brconfig::ssgm_version < 4) ? " Switching to new log files." : "");
			modules::console_output ( $midnight_message );
			brIRC::ircmsg( $midnight_message, "A" );

			# Force creation of new renlog file by sending player_info command and
			# then schedule a call to reset_logfiles in 3 seconds time
			RenRem::RenRemCMD( "player_info" );
			$_[KERNEL]->delay ( "reset_logfiles", 3 );
		},
		reset_logfiles => sub
		{
			# Call events to trigger new logfiles as required
			$_[KERNEL]->post("renlog_tail", "renew_wheel");
			$_[KERNEL]->post("tailbhs", "renew_wheel");
			$renlog::renew_ssgm = 1;
		},
	},
);


# Start the kernel running.
$poe_kernel->run();

# When BRenBot exits this code will be executed
brdatabase::dumpLogs ( 1, $brconfig::config_banlogfile );
brdatabase::dumpLogs ( 2, $brconfig::config_kicklogfile );
brdatabase::dumpLogs ( 3, $brconfig::config_misclogfile );

modules::console_output ( "Done updating logfiles...graceful shutdown...yay!" );
sleep(2);

exit 1;
