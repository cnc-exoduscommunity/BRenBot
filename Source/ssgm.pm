#!/usr/bin/perl

package ssgm;
use strict;

use POE;
use POE qw/Wheel::FollowTail/;
use POE::Kernel;					# Needed for successful pp compile
use POE::Session;					# Needed for successful pp compile

use bhs;
use brconfig;
use modules;


our $midnight = 0;

sub start
{
	# Is SSGM 4.0 installed?
	if ( $brconfig::ssgm_version >= 4 )
	{
		# Create session for TCP connection
		POE::Session->create
		( inline_states =>
			{
				# Start subroutinue - setup parameters, assign alias and schedule initial connection attempt
				_start => sub
				{
					$_[HEAP]->{'ip'} = '127.0.0.1';
					$_[HEAP]->{'port'} = $brconfig::ssgm_logging_port;
					$_[HEAP]->{'connected'} = 0;
					$_[KERNEL]->alias_set( 'ssgmlog' );
					$_[KERNEL]->yield( 'attempt_connect' );
				},


				# Attempt to connect to the SSGM log server
				attempt_connect => sub
				{
					modules::console_output ( 'Connecting to SSGM Log Server on '.$_[HEAP]->{'ip'}.':'.$_[HEAP]->{'port'}.'... ', 1 );
	 				$_[HEAP]->{'socket'} = IO::Socket::INET->new(
	 					PeerAddr => $_[HEAP]->{'ip'},
	 					PeerPort => $_[HEAP]->{'port'},
	 					Proto => 'tcp' );


	 				if ( $_[HEAP]->{'socket'} && $_[HEAP]->{'socket'}->connected() )
	 				{
	 					$_[HEAP]->{'connected'} = 1;
	 					modules::console_output ( 'Success!', 3 );

	 					# Set module status for ssgmlog and gamelog (in SSGM 4.0 these are always handled
	 					# together) to active
	 					modules::set_module( "ssgmlog", 1 );
	 					modules::set_module( "gamelog", 1 );

	 					# Create wheel to recieve input
	 					$_[HEAP]->{'wheel'} = new POE::Wheel::ReadWrite
						(
							Handle     => $_[HEAP]->{'socket'},
							Filter => POE::Filter::Line->new(
								InputLiteral => chr(0),
								OutputLiteral => "\n"
							),
							InputEvent => 'data_recieved',
							ErrorEvent => 'connection_error'
					    );
	 				}
	 				else
	 				{
	 					modules::console_output ( 'Failed! Will retry in one minute.', 3 );
	 					$_[KERNEL]->alarm ( "attempt_connect" => (time()+60) );

	 					# Set module statuses to the error condition
	 					modules::set_module( "ssgmlog", -1 );
	 					modules::set_module( "gamelog", -1 );
	 				}
				},


				# Called externally to send a RenRem command in ARG0 to the FDS via the TCP log connection
				send_command => sub
				{
					return if ( $_[HEAP]->{'connected'} != 1 );
					$_[HEAP]->{'socket'}->send( $_[ARG0] );
				},


				# Data has been recieved through the connection
				data_recieved => sub
				{
					my $input = $_[ARG0];

					# Strip newlines out of the input (the first line of player_info response
					# is bugged and starts with a new line for some bizarre reason)
					$input =~ s/\n//g;

					# Decide what type of input this is based on the three digit prefix
					if ( $input =~ m/^(\d{3})(.+)$/i )
					{
						my $input_code = $1;
						$input = $2;

						# 000 : SSGMLog
						if ( $input_code eq '000' )
						{
							#print "[SSGMLOG] $input\n";
							parse_line($input);
						}

						# 001 : Gamelog
						elsif ( $input_code eq '001' )
						{
							#print "[GAMELOG] $input\n";
							gamelog::parse_line($input);
						}

						# 002 : Renlog
						elsif ( $input_code eq '002' )
						{
							#print "[RENLOG] $input\n";
							renlog::parse_line($input);
						}

						# 003 : Raw Console (We are not interested in these, mostly a clone of 002 without timestamps)
						elsif ( $input_code eq '003' )
						{
							#print "[CONSOLE] $input\n";
						}

						# Unknown message codes (this is here for debugging purposes)
						else
						{
							#print "[UNK ($input_code)] $input\n";
						}
					}

					# Invalid input (this is here for debugging purposes)
					else
					{
						#print "[INVALID] $input\n";
					}
				},


				# An error has occured in $_[HEAP]->{wheel} which means the connection to the server
				# has failed. Shut down the wheel and socket and schedule a reconnection attempt.
				connection_error => sub
				{
					my ( $error, $errorCode, $errorString ) = @_[ ARG0, ARG1, ARG2 ];
					modules::console_output ( 'An error has occured with the SSGM Log Server connection, resetting socket...' );

					# Set connection status to 0 and module statuses to error condition
					$_[HEAP]->{'connected'} = 0;
	 				modules::set_module( "ssgmlog", -1 );
	 				modules::set_module( "gamelog", -1 );

					# Shutdown socket and wheel
					$_[HEAP]->{'wheel'}->shutdown_input();
					$_[HEAP]->{'wheel'}->shutdown_output();
					delete $_[HEAP]->{'wheel'};
					shutdown ( $_[HEAP]->{'socket'}, 2 );

					# Schedule reconnection attempt
					$_[KERNEL]->alarm ( "attempt_connect" => (time()+60) );
				}
			}
		);
	}






	# Otherwise this is a pre 4.0 version of SSGM, attempt to read logs from file
	else
	{
		# Get filename for the ssgm logfile
		my $filename;
		if ( $brconfig::config_botmode eq "LFDS" )
		{
			$filename = $brconfig::config_fdslogpath . $brconfig::ssgmLogPrefix . "_" . modules::get_linux_date_time( "MM-DD-YYYY.txt" );
		}
		else
		{
			$filename = $brconfig::config_fdslogpath . $brconfig::ssgmLogPrefix . "_" . modules::get_date_time( "MM-DD-YYYY.txt" );
		}


		# If gamelog_in_ssgm setting is enabled, we need to scan the ssgm logfile for
		# gamelog lines, so we can get the playerlist setup properly.

		# UPDATE - Use config setting from ssgm.ini as prefix name, followed by _
		if ( $brconfig::gamelog_in_ssgm == 1 && ( modules::get_module ( "gamelog" ) ) )
		{
			if ( -e $filename )
			{
				my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks)
					= stat( $filename );

				if ( $size <= 20000000 )
				{
					modules::console_output ( 'Beginning (SSGM)Gamelog back read ('.$size.' bytes)...', 1 );
					$gamelog::startup = 1;

					open (FILE, "<" . $filename);
					while (<FILE>)
					{
						chomp $_;
						if ( $_ =~ "_GAMELOG" )
						{
							my $gamelog_line = $_;
							$gamelog_line =~ s/_GAMELOG\s//gi;
							gamelog::parse_line($gamelog_line);
						}
					}

					close (FILE);
					modules::console_output ( 'Finished.', 3 );
				}
				else
					{ modules::console_output ( '(SSGM)Gamelog file is too large ('.$size.' bytes) to back read, gamelog will resume on next map' ); }

				$gamelog::startup = 0;
			}
		}


		# Start file tail
		POE::Session->create
		( inline_states => {
			_start => sub {
				modules::console_output ( 'Starting SSGM log follow thread.' );

				if (-e $filename)
				{
					$_[HEAP]->{wheel} = POE::Wheel::FollowTail->new(
						Filename   => $filename,
						InputEvent => 'got_line',
						ErrorEvent => 'got_error',
						SeekBack   => 1,
					);

					modules::set_module( "ssgmlog", 1 );
					if ( $brconfig::gamelog_in_ssgm == 1 && ( modules::get_module ( "gamelog" ) ) )
						{ modules::set_module( "gamelog", 1 ); }
					$_[HEAP]->{first} = 0;
				}
				else
				{
					# Try again in 5 seconds
					$_[HEAP]->{next_alarm_time} = int( time() ) + 5;
					$_[KERNEL]->alarm( tick => $_[HEAP]->{next_alarm_time} );

					modules::set_module( "ssgmlog", -1 );
					if ( $brconfig::gamelog_in_ssgm == 1 && ( modules::get_module ( "gamelog" ) ) )
						{ modules::set_module( "gamelog", -1 ); }
				}

				$_[KERNEL]->alias_set( "ssgm_tail" ); #set an alias to be able to call renew_wheel from the outsie
			},
			got_line     => sub { parse_line($_[ARG0]) },
			got_error    => sub { warn "$_[ARG0]\n" },
			stop_ssgmlog => sub
			{
				modules::set_module( "ssgmlog", 0 );
				if ( $brconfig::gamelog_in_ssgm == 1 )
					{ modules::set_module( "gamelog", 0 ); }

				$_[HEAP]->{rename} = 1;
				$_[HEAP]->{wheel} = undef;
				$_[KERNEL]->alias_remove( "ssgm_tail" );
				$_[KERNEL]->yield( "shutdown" );
			},
			renew_wheel => \&renew_wheel, # function to reset wheel
			_stop => sub
			{
				modules::console_output ( 'SSGM log follow thread has stopped' );
			},
			tick => sub
			{
				if ( modules::get_module( "ssgmlog" ) != 0 )
				{
					$_[KERNEL]->yield( "renew_wheel" ); # renew wheel
				}
			}
		} ); # End of POE::Session->create
	}
}

sub renew_wheel
{
	# Is SSGM 4.0 installed? If so we don't need to do anything...
	if ( $brconfig::ssgm_version >= 4 ) { return; }

	my ( $session, $heap, $input ) = @_[ SESSION, HEAP, ARG0 ];
	my $name;

	if ($brconfig::config_botmode eq "LFDS")
	{
		$name = $brconfig::config_fdslogpath . $brconfig::ssgmLogPrefix . "_" . modules::get_linux_date_time( "MM-DD-YYYY.txt" );
	}
	else
	{
		$name = $brconfig::config_fdslogpath . $brconfig::ssgmLogPrefix . "_" . modules::get_date_time( "MM-DD-YYYY.txt" );
	}


	modules::console_output ( "Looking for SSGM logfile at $name...", 1 );
	if (-e $name)
	{
		modules::console_output ( 'Found', 3 );

		if ($midnight == 1)
		{
			brIRC::ircmsg( "[BR] Switching to new SSGM logfile...");
			$heap->{wheel} = POE::Wheel::FollowTail->new(
			     Filename   => "$name",
			     InputEvent => 'got_line',
			     ErrorEvent => 'got_error',
			     #Seek       => 0,
			     );
			$heap->{first} = 0;

			$midnight = 0;
		}
		else
		{
			$heap->{wheel} = POE::Wheel::FollowTail->new(
			     Filename   => "$name",
			     InputEvent => 'got_line',
			     ErrorEvent => 'got_error',
			     );
			$heap->{first} = 0;
		}

		modules::set_module( "ssgmlog", 1 );
		if ( $brconfig::gamelog_in_ssgm == 1 && ( modules::get_module ( "gamelog" ) ) )
			{ modules::set_module( "gamelog", 1 ); }
	}
	else
	{
		$_[HEAP]->{next_alarm_time2} = int( time() ) + 120;
		$_[KERNEL]->alarm( tick => $_[HEAP]->{next_alarm_time2} );
		modules::console_output ( 'Not found! Will try again in 2 minutes', 3 );

		modules::set_module( "ssgmlog", -1 );
		if ( $brconfig::gamelog_in_ssgm == 1 && ( modules::get_module ( "gamelog" ) ) )
			{ modules::set_module( "gamelog", -1 ); }
	}
}


# Parse a line of input from the SSGMLog
sub parse_line
{
	my $input = shift;

	# _Vehicle is no longer used, but we will keep it for backwards
	# compatibility with ssaow 1.5 and lower
	if ( $input =~ /^\[\d\d:\d\d:\d\d\]\s_VEHICLE\s(.+)$/ )
	{
		vehicle($1);
	}
	elsif ( $input =~ /^\[\d\d:\d\d:\d\d\]\s_ALERT\s(.+)$/ )
	{
		alert($1);
	}
	elsif ( $input =~ /^\[\d\d:\d\d:\d\d\]\s_BEACON\s(.+)$/ )
	{
		beacon($1);
	}
	elsif ( $input =~ /^\[\d\d:\d\d:\d\d\]\s_GENERAL\s(.+)$/ )
	{
		general($1);
	}
	elsif ( $input =~ /^\[\d\d:\d\d:\d\d\]\s_OREDUMP\s(.+)$/ )
	{
		ssapb_oredump($1);
	}
	elsif ( $input =~ /^\[\d\d:\d\d:\d\d\]\s_BUILDING_PURCHASE\s(.+)$/ )		# MP Script for Spacer
	{
		buildingPurchase($1);
	}
	elsif ( $brconfig::gamelog_in_ssgm == 1
		&& $input =~ /^\[\d\d:\d\d:\d\d\]\s_GAMELOG\s(.+)$/
		&& modules::get_module ( "gamelog" ) )
	{
		$input =~ s/_GAMELOG\s//gi;			# Trim _Gamelog and one space
		gamelog::parse_line( $input );		# Send it to the gamelog for processing
	}

	undef $input;
}


# Backwards compatibility with ssaow 1.5
sub vehicle
{
	my $line = shift;
	my $output;

	if ( $line =~ /^(.+)\sHarvester\screated$/ )
	{
		$output = "3[VEHICLE] ";

		if ( $1 eq "Nod" )
		{
			$output = $output . "04";
		}
		else
		{
			$output = $output . "08";
		}

		$output = $output . $line;
	}

	if ( $output )
	{
		brIRC::ircmsg( $output );
	}

	undef $line;
	undef $output;
}


sub alert
{
	my $line = shift;
	my $output;

	if ( $line =~ /^(.+)$/ )
	{
		$output = "3[ALERT]16 " . $line;
		brIRC::ircmsg( $output );
	}

	undef $line;
	undef $output;
}

sub beacon
{
	my $line = shift;
	my $output;

	if ($line =~ /^(.+)$/)
	{
		$output = "3[BEACON]16 " . $line;
		brIRC::ircmsg($output);
	}

	undef $line;
	undef $output;
}

sub general
{
	my $line = shift;
	my $output;

	if ( $line =~ /^Current game on map (.+) has ended\. Game was won by (.+) by (.+)\.$/ )
	{
		$output = "3[GENERAL]16 " . $line;
		brIRC::ircmsg( $output );
	}

	undef $line;
	undef $output;
}

# SSAPB support
sub ssapb_oredump
{
	my $line = shift;
	my $output;

	if ( $line =~ /^(.+) dumped (.+), funding the (.+) with (\d+) additional credits\.$/ )
	{
		$output = "3[OREDUMP]16 " . $line;
		brIRC::ircmsg( $output );
	}

	undef $line;
	undef $output;
}


# Support for rebuildable buildings heading
# MP Script for Spacer
sub buildingPurchase
{
	my $line = shift;

	if ( $line =~ /^(.+)$/ )
	{
		brIRC::ircmsg( "3[BUILDING]16 " . $line );
	}

	undef $line;
}



1;
