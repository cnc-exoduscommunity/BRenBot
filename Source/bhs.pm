#!/usr/bin/perl

package bhs;
use strict;

use POE;

use modules;
use brconfig;
use renlog;
use RenRem;


sub check_bhs_library
{
	if ($brconfig::config_botmode eq "LFDS")		# Linux
	{
		if (-f "$brconfig::config_fdspath" . "bhs.so")
		{
			modules::console_output ( 'Found bhs.so on the FDS, enabling support' );
			modules::set_module("bhs", 1);
			tail_bhs_linux_logfile();
		}
		elsif (-f "$brconfig::config_fdspath" . "bhs8.so")
		{
			modules::console_output ( 'Found bhs8.so on the FDS, enabling support' );
			modules::set_module("bhs", 1);
			tail_bhs_linux_logfile();
		}
		else
		{
			modules::console_output ( 'Unable to locate bhs.so or bhs8.so on the FDS, some functionality will be disabled.' );
			modules::set_module("bhs", 0);
		}
	}
	else		# Win32
	{
		if (-f "$brconfig::config_fdspath" . "tt.dll")
		{
			modules::console_output ( 'Found tt.dll on the FDS, enabling support' );
			modules::set_module("bhs", 1);
		}
		elsif (-f "$brconfig::config_fdspath" . "bhs.dll")
		{
			modules::console_output ( 'Found bhs.dll on the FDS, enabling support' );
			modules::set_module("bhs", 1);
		}
		else
		{
			modules::console_output ( 'Unable to locate bhs.dll or tt.dll on the FDS, some functionality will be disabled.' );
			modules::set_module("bhs", 0);
		}
	}
}




sub tail_bhs_linux_logfile
{
	my $name=$brconfig::config_fdspath . modules::get_linux_date_time("bhs_renlog_MM-DD-YYYY.txt");
	modules::console_output ( "Tailing $name" );
	POE::Session->create				# Initialize POE FollowTail shiznit
  	( inline_states =>
	  { _start => sub
	  	{
			if (-e $_[ARG0])
			{
				$_[HEAP]->{wheel} =
					POE::Wheel::FollowTail->new(
					Filename   => $name,
					InputEvent => 'got_line', # Go to gotline subroutine (see below) when we read a line
					ErrorEvent => 'got_error',
					SeekBack   => 1,	# 1 means start at end of file
				);
				$_[HEAP]->{first} = 0;
			}
			else
			{
				$_[HEAP]->{next_alarm_time} = int( time() ) + 5;
				$_[KERNEL]->alarm( tick => $_[HEAP]->{next_alarm_time} );

			}
			$_[KERNEL]->alias_set("tailbhs"); #set an alias to be able to call renew_wheel from the outside

			#our $kernel  = $_[KERNEL];
		},
		got_line => \&gotline,
		got_error => sub {goterror($_[ARG0])}, #sub { print "ERROR-ERROR-ERROR: FILE ERROR!\n" },
	  	renew_wheel => \&renew_wheel, # function to reset wheel
		tick => sub { $_[KERNEL]->yield("renew_wheel"); }, # renew wheel
	},
	args => [$name],
  );

} # end of tail function

sub renew_wheel
{
	my ( $session, $heap, $input ) = @_[ SESSION, HEAP, ARG0 ];
	my $name=$brconfig::config_fdspath . modules::get_linux_date_time("bhs_renlog_MM-DD-YYYY.txt");


	if (-e $name)
	{
		$heap->{wheel} = POE::Wheel::FollowTail->new(
						Filename   => "$name",
						InputEvent => 'got_line',
						ErrorEvent => 'got_error',
						SeekBack   => 1,
					);
		$heap->{first} = 0;
	}
	else
	{
		$_[HEAP]->{next_alarm_time2} = int( time() ) + 60;
		$_[KERNEL]->alarm( tick => $_[HEAP]->{next_alarm_time2} );
	}
}

# Not sure if this would still work if used...
sub gotline
{
	my ( $session, $heap, $input ) = @_[ SESSION, HEAP, ARG0 ];

	# Chat Messages Look like this: [23:58:36] flawliss9: BAD LAG
	# Team Messages Look like this: [23:58:36] [Team]: flawliss9: BAD LAG

	push (@_, "1"); # push linux flag into array
	renlog::ChatMSG(@_);
	renlog::ParseLogInput(@_); # call ParseLogInput with 1 = linux mode
}

sub goterror
{
	modules::console_output ( "Fatal Error: Got a file error in BHS renlog!\n" );
	sleep ( 2 );
	die;
}


sub playsnda
{
	my $filename = shift;

	if (modules::get_module("bhs") )
	{
		RenRem::RenRemCMD("snda $filename");
	}
}

sub playsndp
{
  my $filename  = shift;
  my $player    = shift;

  if (modules::get_module("bhs") )
  {
    my ($result, %player) = playerData::getPlayerData($player);
    if ($result == 1 && $player{'scriptsVersion'} >= 1.9)
      { RenRem::RenRemCMD("sndp $player{id} $filename"); }
  }
}


sub playsndp_team
{
  my $filename  = shift;
  my $teamid    = brTeams::get_id_from_name(shift);
  
  my %playerlist = playerData::getPlayerList();
  while ( my ( $id, $player ) = each ( %playerlist ) )
  {
    if ( $player->{'teamid'} == $teamid && $player->{'scriptsVersion'} >= 1.9 )
      { RenRem::RenRemCMD( "sndp $player->{id} $filename" ); }
  }
}


1;
