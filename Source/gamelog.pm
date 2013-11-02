#!/usr/bin/perl

package gamelog;
use strict;

use POE;
use POE qw/Wheel::FollowTail/;
use POE::Kernel;
use POE::Session;
use XML::Simple;
use POSIX qw( ceil floor );

use bhs;
use brconfig;


my @clients;
my $gamelog_running = 0;
my $gamelog_name;


# Create hashes to hold preset names
my %wreckages;
my %vehicles;
my %presets;
my %weapons;

# Create pointer for area data
my $areaData;



# Everything evolves around this one hash. It stores all active gameobjects.
my %gameobjects;

our $startup = 0;
my %curplayers;
my $last_purchase_nod;
my $last_purchase_gdi;
my $vehicleFromCrate;			# Holds the preset of the last vehicle that came out of a vehicle crate



# Initialize gamelog
sub init
{
	my $firstrun = shift;

	# Bail out if the gamelog is already running, or SSGM version is >= 4 or SSGM is not installed
	return if ( $gamelog_running == 1 || $brconfig::ssgm_version >= 4 || $brconfig::ssgm_version < 1 );


	if ( $brconfig::gamelog_in_ssgm != 1 )
	{
		POE::Session->create
		( inline_states => {
			_start => sub {
				$_[HEAP]->{tries} = 0;
				$gamelog_running=1;

				if (-e $brconfig::config_fdslogpath . "gamelog2.txt")
				{
					$gamelog_name = "gamelog2.txt";
				}
				elsif (-e $brconfig::config_fdslogpath . "gamelog.txt")
				{
					$gamelog_name = "gamelog.txt";
				}

				if ($gamelog_name)
				{
					my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks)
						= stat($brconfig::config_fdslogpath . $gamelog_name);

					if ($size <= 20000000)
					{
						modules::console_output ( 'Beginning Gamelog back read ('.$size.' bytes)...', 1 );
						$startup = 1;

						open (FILE, "<" . $brconfig::config_fdslogpath . $gamelog_name);
						while (<FILE>)
						{
							chomp $_;
							#if	(($_ =~ "CREATED") || ($_ =~ "DESTROYED") || ($_ =~ "KILLED") || ($_ =~ "WIN") )
							#{
								parse_line($_);
							#}
						}

						close (FILE);
						modules::console_output ( 'Finished.', 3 );
					}
					else
						{ modules::console_output ( 'Gamelog file is too large ('.$size.' bytes) to back read, gamelog will resume on next map' ); }

					$startup = 0;

	#					my $fhGamelog;
	#					sysopen ($fhGamelog, $brconfig::config_fdslogpath . $gamelog_name, O_RDONLY);

	#					if ($fhGamelog)
	#					{
						$_[HEAP]->{wheel} = POE::Wheel::FollowTail->new(
							Filename	=> $brconfig::config_fdslogpath . $gamelog_name,
	#							Handle	 => $fhGamelog,
							InputEvent => 'got_line',
							ErrorEvent => 'got_error',
							SeekBack	=> 1,
						);

						modules::set_module( "gamelog", 1 );
						$_[HEAP]->{first} = 0;
	#					}
	#					else
	#					{
	#						print "Error opening " . $brconfig::config_fdslogpath . $gamelog_name . "!";
	#						$_[HEAP]->{next_alarm_time2} = int( time() ) + 10;
	#						$_[KERNEL]->alarm( tick => $_[HEAP]->{next_alarm_time2} );
	#					}
				}
				else
				{
					$_[HEAP]->{next_alarm_time} = int( time() ) + 5;
					$_[KERNEL]->alarm( tick => $_[HEAP]->{next_alarm_time} );
					modules::set_module( "gamelog", -1 );
				}

				$_[KERNEL]->alias_set( "gamelog_tail" ); #set an alias to be able to call renew_wheel from the outsie
			},

			got_line	 => sub { parse_line($_[ARG0]) },

			got_error	=> sub { warn "$_[ARG0]\n" },

			stop_gamelog => sub {
				modules::set_module( "gamelog", 0 );

				$_[HEAP]->{rename} = 1;
				$_[HEAP]->{wheel} = undef;
				$_[KERNEL]->alias_remove( "gamelog_tail" );
				$_[KERNEL]->yield( "shutdown" );
			},

			renew_wheel => \&renew_wheel, # function to reset wheel

			_stop => sub {
				modules::console_output ( "Gamelog follow thread has stopped" );
				$gamelog_running = 0;
			},

			retry_rename => sub
			{
				$_[HEAP]->{rename} = 1;
				$_[HEAP]->{wheel} = undef;
				$_[KERNEL]->alias_remove( "gamelog_tail" );
			},

			tick => sub {
				if ( modules::get_module( "gamelog" ) != 0 )
				{
					$_[KERNEL]->yield( "renew_wheel" ); # renew wheel
				}
			},
		}

		);
	}
}

sub renew_wheel
{
	my ( $session, $heap, $input ) = @_[ SESSION, HEAP, ARG0 ];

  return if ( $brconfig::ssgm_version < 1 );
  
	if (-e $brconfig::config_fdslogpath . "gamelog2.txt")
	{
		$_[HEAP]->{wheel} =
			POE::Wheel::FollowTail->new(
				Filename	=> $brconfig::config_fdslogpath . "gamelog2.txt",
				InputEvent => 'got_line',
				ErrorEvent => 'got_error',
				SeekBack	=> 1,
			);


		modules::set_module( "gamelog", 1 );
	}
	if (-e $brconfig::config_fdslogpath . "gamelog.txt")
	{
		$_[HEAP]->{wheel} =
			POE::Wheel::FollowTail->new(
				Filename	=> $brconfig::config_fdslogpath . "gamelog.txt",
				InputEvent => 'got_line',
				ErrorEvent => 'got_error',
				SeekBack	=> 1,
			);


		modules::set_module( "gamelog", 1 );
	}
	else
	{
		$_[HEAP]->{next_alarm_time2} = int( time() ) + 10;
		$_[KERNEL]->alarm( tick => $_[HEAP]->{next_alarm_time2} );
	}
}

sub parse_line
{
	my $line = shift;

	if ( $line =~ m/\[(.+?)\] CRATE/ && $startup != 1 )
	{
		crate($line);
	}
	elsif ( $line =~ m/\[(.+?)\] CREATED/ )
	{
		created($line);
	}
	elsif ( $line =~ m/\[(.+?)\] DESTROYED/ )
	{
		destroyed($line);
	}
	elsif ( $line =~ m/\[(.+?)\] POS/ && $startup != 1 )
	{
		position($line);
	}
	elsif ( $line =~ m/\[(.+?)\] ENTER/ )
	{
		enter($line);
	}
	elsif ( $line =~ m/\[(.+?)\] EXIT/ )
	{
		exit_vehicle($line);
	}
	elsif ( $line =~ m/\[(.+?)\] DAMAGED/ && $startup != 1 )
	{
		damaged($line);
	}
	elsif ( $line =~ m/\[(.+?)\] KILLED/ )
	{
		killed($line);
	}
	elsif ( $line =~ m/\[(.+?)\] WIN/ )
	{
		clear();
	}
	elsif ( $line =~ m/\[(.+?)\] CONFIG/ && $startup != 1)
	{
		clear();
	}
  
  # Look for any plugins whose regex hooks match this line
  my %args = (
    'line'    => $line,
    'startup' => $startup
  );

  my %plugins = plugin::get_plugin_gamelog_regexes();
  while ( my($plugin, %regexes) = each(%plugins) )
  {
    while (my ($regex, $event) = each %regexes)
    {
      if ( $line =~ m/$regex/i )
        { $main::poe_kernel->post("plugin_".$plugin => $event => \%args); }
    }
  }
}

sub created
{
	my $line = shift;

	eval
	{
		my @splitted = split (";", $line);
		my %object;

		#[10:16:13] CREATED;BUILDING;1551560;mp_Nod_Obelisk;43;-58;-10;0;500.000000;0.000000;0

		$object{type}		= $splitted[1];
		$object{object}		= $splitted[2];
		$object{preset}		= $splitted[3];
		$object{x}			= $splitted[4];
		$object{y}			= $splitted[5];
		$object{z}			= $splitted[6];
		$object{facing}		= $splitted[7];
		$object{max_health}	= $splitted[8];
		$object{health}		= $splitted[8];
		$object{armor}		= $splitted[9];
		$object{max_armor}	= $splitted[9];
		$object{team}		= $splitted[10];
		$object{name}		= $splitted[11];
		$object{destroyed}	= 0;
		$object{killed}		= 0;
		$object{vehicle}	= 0;
		$object{drivers}	= 0;

		# If the object is a vehicle set the last_team so brenbot can spot if it is
		# stolen from the wf / airstrip
		if ( $object{type} eq "VEHICLE" )
		{
			if ( defined($vehicleFromCrate) && $vehicleFromCrate eq $object{preset} )
			{	# Prevent vehicles from vehicle crates being 'stolen'
				$object{last_team} = 2;
				$vehicleFromCrate = undef;
			}
			else
			{
				$object{last_team} = $object{team};
			}
		}

		# Add/Replace the new object to our hash.
		$gameobjects{ $object{object} } = \%object;

		if ($object{type} eq "SOLDIER")
		{
			$curplayers{ lc($object{'name'}) } = $object{'object'};
		}

		if ($object{type} eq "VEHICLE" && $startup != 1)
		{
			if ($object{preset} ne "CnC_GDI_Harvester" && $object{preset} ne "CnC_Nod_Harvester")
			{
				POE::Session->create
				( inline_states =>
					{
						_start => sub
						{
							$_[HEAP]->{next_alarm_time} = int( time() ) + 5;
							$_[KERNEL]->alarm( tick => $_[HEAP]->{next_alarm_time} );

							$_[HEAP]->{veh_object} = \%object
						},
						tick => \&vehicle_created_gamelog
					}
				);
			}
		}

	}
	or modules::display_error($@);
}

sub destroyed
{
	my $line = shift;

	eval
	{
		my @splitted = split (";", $line);
		my %object;

		$object{type}		= $splitted[1];
		$object{object}		= $splitted[2];
		$object{preset}		= $splitted[3];
		$object{y}			= $splitted[4];
		$object{x}			= $splitted[5];
		$object{z}			= $splitted[6];
		$object{health}		= $splitted[7];

		if ($object{type} eq "SOLDIER")
		{
			delete($curplayers{ lc($object{'name'}) });
		}

		# Clean up destroyed gameobjects.
		if ( exists $gameobjects{$object{object}} )
		{
			$gameobjects{$object{object}}->{destroyed} = 1;
		}

		# Destroy temporary information.
		%object = ();
	}
	or modules::display_error($@);
}

sub damaged
{
	my $line = shift;

	eval
	{
		my @splitted = split (";", $line);
		my %object;
		my %damager;

		$object{type}		= $splitted[1];
		$object{object}		= $splitted[2];
		$object{preset}		= $splitted[3];
		$object{y}			= $splitted[4];
		$object{x}			= $splitted[5];
		$object{z}			= $splitted[6];
		$object{facing}		= $splitted[7];
		$damager{object}	= $splitted[8];
		$damager{preset}	= $splitted[9];
		$damager{y}			= $splitted[10];
		$damager{x}			= $splitted[11];
		$damager{z}			= $splitted[12];
		$damager{facing}	= $splitted[13];
		$object{damage}		= $splitted[14];
		$object{health}		= $splitted[15];
		$object{armor}		= $splitted[16];

		# Setting new health and armor of the object.
		if (exists $gameobjects{ $object{object} })
		{
			$gameobjects{ $object{object} }->{health}	= $object{health};
			$gameobjects{ $object{object} }->{armor}	= $object{armor};
		}


		# If the damage is less than 0 it's actually being repaired
		if ( exists $gameobjects{ $damager{object} } && $object{damage} < 0 )
		{
			my $damagerhash = $gameobjects{ $damager{object} };

			my ( $reason, %player ) = playerData::getPlayerData ( $damagerhash->{'name'} );
			if ( $reason == 1 )
			{
				if ($object{type} eq "BUILDING")
				{
					# Because the damage is negative, we take it OFF the building repair ( minus minus = positive )
					playerData::setKeyValue ( $player{'id'}, "stats_buildingRepair", $player{'stats_buildingRepair'} - $object{'damage'} );
				}
				elsif ($object{type} eq "VEHICLE")
				{
					# Only give points if the vehicle has a driver
					if ( $gameobjects{ $object{object} }->{drivers} > 0 )
					{
						# Because the damage is negative, we take it OFF the vehicle repair ( minus minus = positive )
						playerData::setKeyValue ( $player{'id'}, "stats_vehicleRepair", $player{'stats_vehicleRepair'} - $object{'damage'} );
					}
				}
			}
		}

		# Destroy temporary information.
		%object = ();
		%damager = ();
	}
	or modules::display_error($@);
}

sub position
{
	my $line = shift;

	eval
	{
		my @splitted = split (";", $line);
		my %object;

		$object{type}		= $splitted[1];
		$object{object}		= $splitted[2];
		$object{preset}		= $splitted[3];
		$object{x}			= $splitted[4];
		$object{y}			= $splitted[5];
		$object{z}			= $splitted[6];
		$object{facing}		= $splitted[7];
		$object{max_health}	= $splitted[8];
		$object{health}		= $splitted[8];
		$object{armor}		= $splitted[9];

		# Setting new health of the object.
		if ( exists $gameobjects{ $object{object} } )
		{
			$gameobjects{ $object{object} }->{health}	= $object{health};
			$gameobjects{ $object{object} }->{armor}	= $object{armor};
			$gameobjects{ $object{object} }->{x}		= $object{x};
			$gameobjects{ $object{object} }->{y}		= $object{y};
			$gameobjects{ $object{object} }->{z}		= $object{z};
			$gameobjects{ $object{object} }->{facing}	= $object{facing};
		}

		# Destroy temporary information.
		%object = ();
	}
	or modules::display_error($@);
}

sub enter
{
	my $line = shift;

	eval
	{
		my @splitted = split (";", $line);
		my %object;

		$object{vehicle_object}		= $splitted[1];
		$object{vehicle_preset}		= $splitted[2];
		$object{vehicle_x}			= $splitted[3];
		$object{vehicle_y}			= $splitted[4];
		$object{vehicle_z}			= $splitted[5];
		$object{player_object}		= $splitted[6];
		$object{player_preset}		= $splitted[7];
		$object{player_x}			= $splitted[8];
		$object{player_y}			= $splitted[9];
		$object{player_z}			= $splitted[10];

		if (exists $gameobjects{ $object{player_object} } )
		{
			$gameobjects{ $object{player_object} }->{vehicle} = $object{vehicle_object};
			$gameobjects{ $object{vehicle_object} }->{drivers}++;

			if ( $gameobjects{ $object{vehicle_object} }->{drivers} == 1 )
			{
				$gameobjects{ $object{vehicle_object} }->{driver} = $object{player_object};
				$gameobjects{ $object{vehicle_object} }->{last_driver} = $object{player_object};
				$gameobjects{ $object{vehicle_object} }->{team} = $gameobjects{ $object{player_object} }->{team};

				# Check if this vehicle was stole by the other team
				if ( $gameobjects{ $object{vehicle_object} }->{last_team} != $gameobjects{ $object{player_object} }->{team} )
				{
					my $translatedPreset = translatePreset ( $gameobjects{$object{vehicle_object}}->{preset} );

					# If we are not in startup, and the vehicle was not unteamed (from a
					# crate usually) announce it was stolen
					if ( $startup != 1 && $gameobjects{ $object{vehicle_object} }->{last_team} != 2
						&& $brconfig::gamelog_show_vehicle_stolen == 1 )
					{ RenRem::RenRemCMD ( "msg [BR] $gameobjects{ $object{player_object} }->{name} has stolen a $translatedPreset!" ); }

					$gameobjects{ $object{vehicle_object} }->{last_team} = $gameobjects{ $object{player_object} }->{team};
				}
			}
		}
	}
	or modules::display_error($@);
}

sub exit_vehicle
{
	my $line = shift;

	eval
	{
		my @splitted = split (";", $line);
		my %object;

		$object{vehicle_object}		= $splitted[1];
		$object{vehicle_preset}		= $splitted[2];
		$object{vehicle_x}			= $splitted[3];
		$object{vehicle_y}			= $splitted[4];
		$object{vehicle_z}			= $splitted[5];
		$object{player_object}		= $splitted[6];
		$object{player_preset}		= $splitted[7];
		$object{player_x}			= $splitted[8];
		$object{player_y}			= $splitted[9];
		$object{player_z}			= $splitted[10];

		if (exists $gameobjects{ $object{player_object} })
		{
			$gameobjects{ $object{player_object} }->{vehicle} = 0;
			$gameobjects{ $object{vehicle_object} }->{drivers}--;

			if ( $gameobjects{ $object{vehicle_object} }->{drivers} == 0 )
			{
				$gameobjects{ $object{vehicle_object} }->{driver} = "";
				$gameobjects{ $object{vehicle_object} }->{team} ="-1";		# Neutral Team
			}
		}
	}
	or modules::display_error($@);
}

sub crate
{
	my $line	= shift;

	eval
	{
		my @splitted = split (";", $line);
		my %hash;

		$hash{type}		= $splitted[1];
		$hash{param}	= $splitted[2];
		$hash{object}	= $splitted[3];
		$hash{preset}	= $splitted[4];

		$hash{x}		= $splitted[5];
		$hash{y}		= $splitted[6];
		$hash{z}		= $splitted[7];
		$hash{facing}	= $splitted[8];
		$hash{health} 	= $splitted[9];
		$hash{armor}	= $splitted[10];
		$hash{team}		= $splitted[11];

		my $param;

		$param = "Weapon"			if ($hash{type} eq "WEAPON");
		$param = "Money"			if ($hash{type} eq "MONEY");
		$param = "Points"			if ($hash{type} eq "POINTS");
		$param = "Vehicle"			if ($hash{type} eq "VEHICLE");
		$param = "Death"			if ($hash{type} eq "DEATH");
		$param = "Tiberium Death"	if ($hash{type} eq "TIBERIUMDEATH");
		$param = "Full Ammo"		if ($hash{type} eq "FULLAMMO");
		$param = "Armor Increase"	if ($hash{type} eq "ARMORINCREASE");
		$param = "Armor Maxx"		if ($hash{type} eq "ARMORMAXX");
		$param = "Armor Lost"		if ($hash{type} eq "ARMORLOST");
		$param = "Health Upgrade" 	if ($hash{type} eq "HEALTHUPGRADE");
		$param = "Health Maxx"		if ($hash{type} eq "HEALTHMAXX");
		$param = "Health Lost"		if ($hash{type} eq "HEALTHREDUCE");
		$param = "Vehicle"			if ($hash{type} eq "VEHICLE");
		$param = "Character"		if ($hash{type} eq "CHARACTER");
		$param = "Butter Finger"	if ($hash{type} eq "BUTTERFINGER");
		$param = "Refill"			if ($hash{type} eq "REFILL");
		$param = "Beacon"			if ($hash{type} eq "BEACON");
		$param = "Beacon Death"		if ($hash{type} eq "BEACONDEATH");
		$param = "God"				if ($hash{type} eq "GOD");
		$param = "Spy"				if ($hash{type} eq "SPY");
		$param = "Stealth"			if ($hash{type} eq "STEALTH");
		$param = "Thief"			if ($hash{type} eq "THIEF");

		if ( !$param )
		{
			$param = $hash{type};
		}

		if (exists $gameobjects{ $hash{object} })
		{
			my $team = $gameobjects{ $hash{object} }->{team};
			my $name = $gameobjects{ $hash{object} }->{name};

			my $param2;

			if (length($hash{param}) > 0)
			{
				$param2 = " ( $hash{param} )";
			}

			# If it is a vehicle crate make a note of it so it does not get 'stolen'
			if ( $param eq "Vehicle" )
			{
				my $crateVehiclePreset;
				if ( $hash{param} eq "GDI Humvee" ) { $crateVehiclePreset = "CnC_GDI_Humm-vee"; }
				elsif ( $hash{param} eq "Nod Buggy" ) { $crateVehiclePreset = "CnC_Nod_Buggy"; }
				elsif ( $hash{param} eq "GDI APC" ) { $crateVehiclePreset = "CnC_GDI_APC"; }
				elsif ( $hash{param} eq "Nod APC" ) { $crateVehiclePreset = "CnC_Nod_APC"; }
				elsif ( $hash{param} eq "GDI MRLS" ) { $crateVehiclePreset = "CnC_GDI_MRLS"; }
				elsif ( $hash{param} eq "Nod Mobile Artillery" ) { $crateVehiclePreset = "CnC_Nod_Mobile_Artillery"; }
				elsif ( $hash{param} eq "GDI Medium Tank" ) { $crateVehiclePreset = "CnC_GDI_Medium_Tank"; }
				elsif ( $hash{param} eq "Nod Light Tank" ) { $crateVehiclePreset = "CnC_Nod_Light_Tank"; }
				elsif ( $hash{param} eq "Nod Flame Tank" ) { $crateVehiclePreset = "CnC_Nod_Flame_Tank"; }
				elsif ( $hash{param} eq "Nod Stealth Tank" ) { $crateVehiclePreset = "CnC_Nod_Stealth_Tank"; }
				elsif ( $hash{param} eq "GDI Mammoth Tank" ) { $crateVehiclePreset = "CnC_GDI_Mammoth_Tank"; }
				elsif ( $hash{param} eq "Nod Recon Bike" ) { $crateVehiclePreset = "CnC_Nod_Recon_Bike"; }

				if ( $crateVehiclePreset )
				{ $vehicleFromCrate = $crateVehiclePreset; }
			}

			if ( $brconfig::gamelog_showCrateMsgs != 0 && $startup != 1 )
			{
				my $ircChannelCode = ( $brconfig::gamelog_showCrateMsgs == 1 ) ? "A" : "";
				brIRC::ircmsg ( "3[Crate]:" . brTeams::colourise($team,"$name got the $param crate $param2"), $ircChannelCode );
			}
		}
	}
	or modules::display_error($@);
}

sub killed
{
	my $line = shift;

	eval
	{
		my @splitted = split (";", $line);
		my %object;

		# [10:17:00] KILLED;SOLDIER;1500000170;CnC_GDI_MiniGunner_0;-12;58;0;-170;1500000084;Nod_Obelisk;-58;43;34;0;

		$object{killed_type}		= $splitted[1];
		$object{killed_object}		= $splitted[2];
		$object{killed_preset}		= $splitted[3];
		$object{killed_x}			= $splitted[4];
		$object{killed_y}			= $splitted[5];
		$object{killed_z}			= $splitted[6];
		$object{killed_direction}	= $splitted[7];

		$object{killer_object}		= $splitted[8];
		$object{killer_preset}		= $splitted[9];
		$object{killer_x}			= $splitted[10];
		$object{killer_y}			= $splitted[11];
		$object{killer_z}			= $splitted[12];
		$object{killer_direction}	= $splitted[13];
		$object{killer_weapon}		= $splitted[14];

		if (exists $gameobjects{ $object{killed_object} })
		{
			my $killed = $gameobjects{ $object{killed_object} };

			if ($gameobjects{$object{killed_object}}->{killed} eq 0)
			{
				# Don't show kill message twice.
				$gameobjects{$object{killed_object}}->{killed} = 1;

				# If a base defense killed a soldier run killed_by_basedefence
				if ( ( $object{killer_preset} eq "Nod_Obelisk"
						|| $object{killer_preset} eq "GDI_AGT"
						|| $object{killer_preset} eq "GDI_Guard_Tower"
						|| $object{killer_preset} =~ m/Nod_Turret/i
						|| $object{killer_preset} =~ m/Ceiling_Gun/i
					)
					&& $killed->{type} eq "SOLDIER"
				)
				{
					killed_by_basedefence($object{killer_preset}, $killed);
					return;
				}

				my $killer		= 0;		# Unknown

				if ( exists $gameobjects{ $object{killer_object} } )
				{
					$killer = $gameobjects{ $object{killer_object} };
				}

				if ( $killed->{type} eq "BUILDING" && $killer ne "0" ) #&& !exists $wreckages{$killed->{preset}} )
				{
					if ( exists $wreckages{$killed->{preset}} )
					{
						killed_wreck($killer, $killed, $object{killer_weapon});
					}
					else
					{
						killed_building($killer, $killed, $object{killer_weapon});
					}
				}
# 				elsif ( $killed->{type} eq "BUILDING" && exists $wreckages{$killed->{preset}} )
# 				{
# 					killed_wreck($killer, $killed, $object{killer_weapon});
# 				}

				elsif ( $killed->{type} eq "VEHICLE" && $killer ne "0" )
				{
					killed_vehicle($killer, $killed, $object{killer_weapon});
				}
				elsif ( $killed->{type} eq "SOLDIER" )
				{
					killed_soldier($killer, $killed, $object{killer_weapon});
				}

				if ( $killer ne "0" )
				{
					if ( $killed->{type} eq "BUILDING"
						&& !exists $wreckages{$killed->{preset}}
						&& $killed->{preset} !~ m/Nod_Turret/i
						&& $killed->{preset} ne "GDI_Guard_Tower"
						&& $killed->{preset} !~ m/Emplacement/i
						&& $killed->{preset} !~ m/Ceiling_Gun/i
					)
					{
						playerData::incrementKeyValue ( $killer->{'name'}, "stats_buildingKills" );
					}
					elsif ( $killed->{type} eq "VEHICLE" && $killed->{drivers} > 0 )
					{
						# Increment number of vehicles killed
						playerData::incrementKeyValue ( $killer->{'name'}, "stats_vehicleKills" );
					}
				}
			}
		}
	}
	or modules::display_error($@);
}

sub killed_wreck
{
	my $killer = shift;
	my $killed = shift;
	my $weapon = shift;

	eval
	{
		my $team = $killer->{'team'};
		my $color = brTeams::get_colour($team);

		my $killerchar = translatePreset ( $killer->{'preset'} );

		if ($killer->{vehicle} ne '0')
		{
			if (exists $gameobjects{ $killer->{vehicle} })
			{
				my $killerVehicle = $gameobjects{ $killer->{vehicle} };

				$weapon = translatePreset ( $killerVehicle->{preset} );
			}
			else
			{
				$weapon = "error";
			}
		}
		else
		{
			$weapon = translateWeaponPreset ( $weapon );
		}

		if ( ( $killer->{name} ) && ( $startup != 1 ) && ( $brconfig::gamelog_showVehicleKillMsgs != 0 ) )
		{
			my $ircChannelCode = ( $brconfig::gamelog_showVehicleKillMsgs == 1 ) ? "A" : "";
			brIRC::ircmsg ( "" . $color . "$killer->{name} destroyed a " . translatePreset ( $killed->{preset} ) . " ($killerchar/$weapon" . $color . ")", $ircChannelCode );
		}
	}
	or modules::display_error($@);
}

sub killed_by_basedefence
{
  my $killerpreset = shift;
  my $killed		= shift;

  eval
  {
    my $team = $killed->{team};

    if ( $brconfig::gamelog_showKillMsgs != 0 && $startup != 1 )
    {
      my $ircChannelCode = ( $brconfig::gamelog_showKillMsgs == 1 ) ? "A" : "";
      brIRC::ircmsg(brTeams::colourise($team,"$killed->{name} was pwnd by the " . translatePreset($killerpreset)), $ircChannelCode );
    }

    playerData::incrementKeyValue ( $killed->{'name'}, "stats_deaths" );;
  }
  or modules::display_error($@);
}

sub killed_building
{
	my $killer = shift;
	my $killed = shift;
	my $weapon = shift;

	if ( $killer )
	{
		eval
		{
			my $team = $killer->{team};

			if ($killer->{name})
			{
				if ( $brconfig::gamelog_showBuildingKillMsgs != 0 && $startup != 1 )
				{
					my $ircChannelCode = ( $brconfig::gamelog_showBuildingKillMsgs == 1 ) ? "A" : "";
					brIRC::ircmsg(brTeams::colourise($team,"$killer->{name} destroyed the " . translatePreset($killed->{preset})), $ircChannelCode );
				}
			}
		}
		or modules::display_error($@);
	}
}

sub killed_soldier
{
	my $killer = shift;
	my $killed = shift;
	my $weapon = shift;

	eval
	{
		my $team = ( $killer ne 0 ) ? $killer->{team} : $killed->{team};
		my $color = brTeams::get_colour($team);

		if ( $killer ne 0 )
		{
			if ($killer->{type} eq "SOLDIER")
			{
				if ($killer->{name} ne $killed->{name})
				{
					if ( $brconfig::gamelog_showKillMsgs != 0 && $startup != 1 )
					{
						my $killerpreset = translatePreset ( $killer->{preset} );
						my $ircChannelCode = ( $brconfig::gamelog_showKillMsgs == 1 ) ? "A" : "";

						if ($killer->{vehicle} ne 0)
						{
							if (exists $gameobjects{ $killer->{vehicle} })
							{
								my $killerVehicle = $gameobjects{ $killer->{vehicle} };

								$weapon = translatePreset ( $killerVehicle->{preset} );
							}
							else
							{
								$weapon = "error";
							}
						}
						else
						{
							$weapon = translateWeaponPreset ( $weapon );
						}

						my $killedpreset = translatePreset ( $killed->{preset} );

						if ( $killedpreset ne "Visceroid" )		# Dont show players killing visceroids
						{
							brIRC::ircmsg ( "" . $color . "$killer->{name} killed $killed->{name} ($killerpreset/$weapon " . $color . "vs $killedpreset" . $color . ")", $ircChannelCode );
						}
					}

					playerData::incrementKeyValue ( $killer->{'name'}, "stats_kills" );
				}
				elsif ($killer->{name} eq $killed->{name})
				{
					if ( $brconfig::gamelog_showKillMsgs != 0 && $startup != 1 )
					{
						my $ircChannelCode = ( $brconfig::gamelog_showKillMsgs == 1 ) ? "A" : "";
						brIRC::ircmsg ( "" . $color . "$killer->{name} killed theirself.", $ircChannelCode );
					}
				}
			}
			elsif ( $killer->{type} eq "VEHICLE" && $brconfig::gamelog_showKillMsgs == 1 )
			{
				if ( $brconfig::gamelog_showKillMsgs != 0 && $startup != 1 )
				{
					my $ircChannelCode = ( $brconfig::gamelog_showKillMsgs == 1 ) ? "A" : "";
					brIRC::ircmsg ( "" . $color . "$killed->{name} was ran over by the " . translatePreset ( $killer->{preset} ) . ".", $ircChannelCode );
				}
			}
		}
		elsif ( $brconfig::gamelog_showKillMsgs != 0 && $startup != 1 )
		{
			my $ircChannelCode = ( $brconfig::gamelog_showKillMsgs == 1 ) ? "A" : "";
			brIRC::ircmsg ( "" . $color . "$killed->{name} didn't last too long in the Tiberium field.", $ircChannelCode );
		}

		playerData::incrementKeyValue ( $killed->{'name'}, "stats_deaths" );
	}
	or modules::display_error($@);
}

sub killed_vehicle
{
	my $killer = shift;
	my $killed = shift;
	my $weapon = shift;

	eval
	{
		my $team;
		my $driver_name;
		if ($killer ne 0)
		{
			$team = $killer->{team};
		}
		else
		{
			if (exists $gameobjects{$killed->{last_driver}})
			{
				$team		= $gameobjects{$killed->{last_driver}}->{team};
				$driver_name = $gameobjects{$killed->{last_driver}}->{name};
				if ($team == 0) {$team = 1;}
				if ($team == 1) {$team = 0;}
			}
			else
			{
				return;
			}
		}


		my $color = brTeams::get_colour($team);
		my $killedpreset = 0;
		my $killerpreset = 0;

		if ( $killer ne 0 )
		{
			if ($killer->{type} eq "SOLDIER")
			{
				if ( $brconfig::gamelog_showVehicleKillMsgs != 0 && $startup != 1 )
				{
					$killerpreset = translatePreset ( $killer->{preset} );

					if ($killer->{vehicle} ne 0)
					{
						if (exists $gameobjects{ $killer->{vehicle} })
						{
							my $killerVehicle = $gameobjects{ $killer->{vehicle} };

							$weapon = translatePreset ( $killerVehicle->{preset} );
						}
						else
						{
							$weapon = "error";
						}
					}
					else
					{
						$weapon = translateWeaponPreset ( $weapon );
					}

					$killedpreset = translatePreset ( $killed->{preset} );

					my $ircChannelCode = ( $brconfig::gamelog_showVehicleKillMsgs == 1 ) ? "A" : "";
					brIRC::ircmsg ( "" . $color . "$killer->{name} destroyed a $killedpreset ($killerpreset/$weapon" . $color . ")", $ircChannelCode );
				}
			}
		}
		elsif ( $brconfig::gamelog_showVehicleKillMsgs == 1 && $startup != 1 )
		{
			$killedpreset = translatePreset ( $killed->{preset} );
			my $ircChannelCode = ( $brconfig::gamelog_showVehicleKillMsgs == 1 ) ? "A" : "";
			brIRC::ircmsg ( "" . $color . "$driver_name destroyed his own $killedpreset by driving too close to the airstrip/wf/cliffs.", $ircChannelCode );
		}
	}
	or modules::display_error($@);
}

# Clear all stats ready for the next map
sub clear
{
	# Clear $gameobjects
	foreach my $objectID ( keys %gameobjects )
	{
		foreach my $k ( keys %{$gameobjects{$objectID}} )
		{ delete $gameobjects{$objectID}->{$k}; }
		delete $gameobjects{$objectID};
	}


	# Clear $curplayers
	foreach my $player ( keys %curplayers )
	{ delete $curplayers{$player}; }


  # Clear stats for all players
  my %playerlist = playerData::getPlayerList();
  while ( my ( $id, $player ) = each ( %playerlist ) )
  {
    playerData::deleteKeyValue ( $id, "stats_kills" );
    playerData::deleteKeyValue ( $id, "stats_deaths" );
    playerData::deleteKeyValue ( $id, "stats_buildingKills" );
    playerData::deleteKeyValue ( $id, "stats_buildingKills_buildingA" );
    playerData::deleteKeyValue ( $id, "stats_buildingRepair" );
    playerData::deleteKeyValue ( $id, "stats_vehicleKills" );
    playerData::deleteKeyValue ( $id, "stats_vehicleRepair" );
  }

  # Clear last purchases
  $last_purchase_nod = "";
  $last_purchase_gdi = "";
}


# Returns true(1) if the player has loaded, false(0) otherwise. If the Enable_Gamelog_Loaded_Checks
# option is disable this will always return true(1).
sub isPlayerLoaded
{
  my $name = lc(shift);
  return 1 if ( $brconfig::enable_gamelog_loaded_check == 0 || exists ( $curplayers{$name} ) );
  return 0;
}

sub display_buildings
{
	my $ircChannelCode = shift;

	eval
	{
		my $gdi;
		my $nod;
		my $building=0;
		my $buidingPreset;

		foreach my $object (keys %gameobjects)
		{
			if ($gameobjects{$object}->{type} eq "BUILDING" &&
				$gameobjects{$object}->{preset} ne "GDI_AGT" &&
				$gameobjects{$object}->{preset} ne "GDI_Ceiling_Gun_AGT" &&
				$gameobjects{$object}->{preset} ne "Nod_Obelisk")
			{
				$building++;
				$buidingPreset = translatePreset ( $gameobjects{$object}->{preset} );

				if ($gameobjects{$object}->{team} eq "1")
				{
					if ($gameobjects{$object}->{health} <= 0)
					{
						$gdi .= "15" . $buidingPreset . " (" . int($gameobjects{$object}->{health}) . "/" . int($gameobjects{$object}->{max_health}) . ") * ";
					}
					else
					{
						$gdi .= brTeams::colourise(1,$buidingPreset)." (" . int($gameobjects{$object}->{health}) . "/" . int($gameobjects{$object}->{max_health}) . ") * ";
					}
				}

				if ($gameobjects{$object}->{team} eq 0)
				{
					if ($gameobjects{$object}->{health} <= 0)
					{
						$nod .= "15" . $buidingPreset . " (" . int($gameobjects{$object}->{health}) . "/" . int($gameobjects{$object}->{max_health}) . ") * ";
					}
					else
					{
						$nod .= brTeams::colourise(0,$buidingPreset)." (" . int($gameobjects{$object}->{health}) . "/" . int($gameobjects{$object}->{max_health}) . ") * ";
					}
				}
			}
		}

		$gdi =~ s/ \* $//;
		$nod =~ s/ \* $//;

		POE::Session->create
		( inline_states =>
			{
				_start => sub
				{
					if ($building == 0)
					{
						brIRC::ircmsg ( "No known buildings for this map.", $ircChannelCode );
					}
					else
					{
						brIRC::ircmsg ( $gdi, $ircChannelCode );
						brIRC::ircmsg ( $nod, $ircChannelCode );
					}
				}
			}
		);
	}
	or modules::display_error($@);

}

# Really need to update this sometime to use the list of vehicle presets and then count
# the number of those in the game...
sub display_vehicles
{
  my $ircChannelCode = shift;
  my %currentVehicles_gdi;
  my %currentVehicles_nod;
  my %currentVehicles_neutral;
  my $objecthash;

  eval
  {
    foreach my $object (keys %gameobjects)
    {
      $objecthash = $gameobjects{$object};

      if ( ($objecthash->{type} eq "VEHICLE") && ($objecthash->{destroyed} == 0) )
      {
        my $translatedPreset = translatePreset ( $objecthash->{preset} );

        if ( $objecthash->{team} == 1 )
        {
          if ( $currentVehicles_gdi{$translatedPreset} )
          { $currentVehicles_gdi{$translatedPreset}++; }
          else
          { $currentVehicles_gdi{$translatedPreset} = 1 }
        }
        elsif ( $objecthash->{team} == 0 )
        {
          if ( $currentVehicles_nod{$translatedPreset} )
          { $currentVehicles_nod{$translatedPreset}++; }
          else
          { $currentVehicles_nod{$translatedPreset} = 1 }
        }
        else
        {
          if ( $currentVehicles_neutral{$translatedPreset} )
          { $currentVehicles_neutral{$translatedPreset}++; }
          else
          { $currentVehicles_neutral{$translatedPreset} = 1 }
        }
      }
    }

    brIRC::ircmsg ( brIRC::bold('Current Vehicles:'),$ircChannelCode );
    display_vehicles_printTeam(1,\%currentVehicles_gdi,$ircChannelCode);
    display_vehicles_printTeam(0,\%currentVehicles_nod,$ircChannelCode);
    
    # Only print neutral vehicles if there are some in the list, otherwise omit it
    if ( scalar keys %currentVehicles_neutral > 0 )
    {
      display_vehicles_printTeam(2,\%currentVehicles_neutral,$ircChannelCode);
    }
  }
  or modules::display_error($@);
}

sub display_vehicles_printTeam
{
  my $teamid = shift;
  my $teamvehicles = shift;
  my $ircChannelCode = shift;

  my $message = "";
  foreach (keys %{$teamvehicles})
  {
    $message .= " $teamvehicles->{$_} $_,";
  }

  # If there are no vehicles then use "None" for the message string
  $message = "None" if ( $message eq "" );
  brIRC::ircmsg(brTeams::colourise($teamid,brTeams::get_name($teamid).' Vehicles: '.$message), $ircChannelCode);
}

sub show_stats
{
	my $name = shift;
	my $ircChannelCode = shift;

	eval
	{
		if (exists $curplayers{lc($name)})
		{
			my $objectid = $curplayers{lc($name)};
			if (exists $gameobjects{$objectid})
			{
				my $object = $gameobjects{$objectid};
				POE::Session->create

				( inline_states =>
				{ _start => sub
					{
						my ( $result, %player ) = playerData::getPlayerData ( $name );
						return if ( $result != 1 );

						my $health = int($object->{health});
						my $max_health = int($object->{max_health});
						my $armor = int($object->{armor});
						my $max_armor = int($object->{max_armor});

						my $team = $object->{team};
						my $color = brTeams::get_colour($team);

						brIRC::ircmsg ( "" . $color . "$player{name}: Character: " . translatePreset( $object->{preset} ) . " Health: $health/$max_health Armor: $armor/$max_armor", $ircChannelCode );
						brIRC::ircmsg ( "" . $color . "Kills: $player{stats_kills} Vehicle Kills: $player{stats_vehicleKills} Building Kills: $player{stats_buildingKills} Deaths: $player{stats_deaths}", $ircChannelCode );

						if ($object->{vehicle})
						{
							if (exists $gameobjects{$object->{vehicle}})
							{
								my $vehicle		= $gameobjects{$object->{vehicle}};

								my $v_health	 = int($vehicle->{health});
								my $v_max_health = int($vehicle->{max_health});

								my $v_armor		= int($vehicle->{armor});
								my $v_max_armor	= int($vehicle->{max_armor});

								brIRC::ircmsg ( "" . $color . "Vehicle: " . translatePreset( $vehicle->{preset} ) . " Health: $v_health/$v_max_health Armor: $v_armor/$v_max_armor", $ircChannelCode );
							}
						}
					}
				}
				);
			}
		}
	}
	or modules::display_error($@);
}

sub vehicle_purchase_renlog
{
	my $playername = shift;

	my $side;

	eval
	{
		my ( $result, %player ) = playerData::getPlayerData($playername);
		if ( $result == 1 )
		{
			$side = $player{side};
			if ($side eq "NOD" || $side eq "Sov") #nod
			{
				$last_purchase_nod = $playername;
			}
			else #gdi
			{
				$last_purchase_gdi = $playername;
			}
		}
	}
	or modules::display_error($@);
}

sub vehicle_created_gamelog
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];

	eval
	{
		if ( $brconfig::gamelog_show_vehicle_purchase != 1 || $startup == 1 )
		{ return; }

		my $vehicle_object = $heap->{veh_object};
		my $side = $vehicle_object->{team};
		my $irc_message;
		my $translated_preset = translatePreset( $vehicle_object->{preset} );

		if ($side == 0) #nod
		{
			if ($last_purchase_nod)
			{
				$irc_message = "04" . $last_purchase_nod . " purchased a " . $translated_preset;
				undef $last_purchase_nod;
			}
		}
		else #gdi
		{
			if ($last_purchase_gdi)
			{
				$irc_message = "08" . $last_purchase_gdi . " purchased a " . $translated_preset;
				undef $last_purchase_gdi;
			}
		}

		if ( $irc_message )
		{
			brIRC::ircmsg( "3[Vehicle Purchase] " . $irc_message, "A" );
		}
	}
	or modules::display_error($@);
}




# Loads a list of preset translations and settings from presets.brf
sub loadPresets
{
	my $currentSection = 0;
	%presets = ();
	%weapons = ();
	%vehicles = ();
	%wreckages = ();

	eval
	{
		if ( -e $brconfig::config_presetsfile )
		{
			open ( PRESETS, $brconfig::config_presetsfile );
			while ( <PRESETS> )
			{
				if ( $_ !~ m/^\#/ && $_ !~ m/^\s+$/ )		# If the line starts with a hash or is blank ignore it
				{
					if ( $_ =~ m/\[(PRESETS|WEAPONS|VEHICLES|LIGHT_VEHICLES|HEAVY_VEHICLES|WREAKAGES)\]/i )
					{
						$currentSection = uc($1);
					}
					elsif ( $currentSection )
					{
						if ( $_ =~ m/(\S+)\s+=\s+(.+)/ )
						{
							if ( $currentSection eq "PRESETS" ) { $presets{$1} = $2; }
							elsif ( $currentSection eq "WEAPONS" ) { $weapons{$1} = $2; }
							elsif ( $currentSection eq "VEHICLES" ) { $vehicles{$1} = $2; }
							elsif ( $currentSection eq "WREAKAGES" ) { $wreckages{$1} = $2; }
						}
					}
				}
			}
			close ( PRESETS );
		}
		else
		{
			modules::console_output ( "Warning: Unable to load presets from ".$brconfig::config_presetsfile );
		}
	}
	or modules::display_error($@);
}



# Takes a preset name and returns the translated name loaded from presets.brf,
# or the original preset name if there is no translation found
sub translatePreset
{
	my $preset = shift;

	if ( $presets{$preset} )
	{
		return $presets{$preset};
	}
	return $preset;
}



# Takes a weapon preset name and returns the translated name loaded from presets.brf,
# or the original preset name if there is no translation found
sub translateWeaponPreset
{
	my $preset = shift;

	if ( $weapons{$preset} )
	{
		return $weapons{$preset};
	}
	return $preset;
}


# Can be used by plugins and any other modules which need it, looks up a
# gamelog object ID of a player and returns the players name
sub getPlayerFromObjectID
{
	my $object = shift;
	my $player = $gameobjects{$object};

	if ( $player )
	{
		return $player->{name};
	};

	return undef;
}







###################################################
####
## Code for the area management system
####
###################################################

# Loads area data into BRenBot
sub loadAreaData
{
	$areaData = XMLin( "mapareas.xml", ForceArray => [ qw(map area) ] );

	# Under Win32 replace all &amp; with & in map names
	while ( my ($mapname, $data) = each %{$areaData->{'map'}} )
	{
		my $mapname_new = $mapname;
		$mapname_new =~ s/&amp;/&/gi;
		if ( $mapname_new ne $mapname )
		{
			$areaData->{'map'}->{$mapname_new} = $data;
			delete $areaData->{'map'}->{$mapname};
		}
	}
}


# Outputs the data back to XML after any changes we might have made
sub updateXMLFile
{
	XMLout( $areaData, NoSort => 1, OutputFile => "mapareas.xml", rootName => "mapareas", XMLDecl => 1 );
}


# Converts an area name to it's ID within the array. Returns -1 if the area was
# not found
sub areaNameToID
{
	my $areaName = lc(shift);
	my $areaID = 0;
	my $map = serverStatus::getMap();

	foreach my $area ( @{$areaData->{'map'}->{$map}->{'area'}} )
	{
		if ( lc($area->{'area'}) eq $areaName )
			{ return $areaID; }
		$areaID++;
	}

	return -1;
}


# Work out what area an object is in
sub getPlayerArea
{
	my $name = shift;
	my $map = serverStatus::getMap();

	if ( exists $areaData->{'map'}->{$map} )
	{
		if ( exists $curplayers{lc($name)} )
		{
			my $objectid = $curplayers{lc($name)};
			if ( exists $gameobjects{$objectid} )
			{
				my $object = $gameobjects{$objectid};

				foreach my $area ( @{$areaData->{'map'}->{$map}->{'area'}} )
				{
					if ( $object->{x} <= $area->{'topright'}->{x} && $object->{x} >= $area->{'bottomleft'}->{x}
						&& $object->{y} <= $area->{'topright'}->{y} && $object->{y} >= $area->{'bottomleft'}->{y} )
					{
						#return $name, $object->{x}, $object->{y};
						# TEMPORARY EXTRA PARAMETERS until playerData is up and running
						return $area->{'area'}, $object->{x}, $object->{y}, translatePreset( $object->{preset} ), translatePreset ( $gameobjects{$object->{vehicle}}->{preset} );
					}
				}
				return "Unknown", $object->{x}, $object->{y}, translatePreset( $object->{preset} ), translatePreset ( $gameobjects{$object->{vehicle}}->{preset} );
			}
		}
	}

	return "Unknown", 0, 0, "N/A";
}


# Creates a new 1x1 area at the players location, if it does not already exist.
# If it does exist will use expandArea() to expand the existing area to cover the
# new position. Returns 0 on fail, 1 on success, 2 on zone already existing
sub createArea
{
	my $areaName = shift;
	my $areaSide = shift;
	my $playerName = shift;
	my $map = serverStatus::getMap();

	if ( exists $curplayers{lc($playerName)} )
	{
		my $objectid = $curplayers{lc($playerName)};
		if ( exists $gameobjects{$objectid} )
		{
			my $object = $gameobjects{$objectid};

			my $areaID = areaNameToID ( $areaName );
			if ( $areaID == -1 )
			{
				# Area does not exist, create it
				my $topRightX = ceil($object->{x});
				my $topRightY = ceil($object->{y});

				my %newArea = (
					'area' => $areaName,
					'side' => $areaSide,
					'topright' => {
						'x' => $topRightX,
						'y' => $topRightY
					},
					'bottomleft' => {
						'x' => ($topRightX-1),
						'y' => ($topRightY-1)
					}
				);

				push ( @{$areaData->{'map'}->{$map}->{'area'}}, \%newArea );
				updateXMLFile();
				return 1;
			}
			else
			{
				# Area already exists, expand it to cover their current location
				expandArea ( $areaName, $playerName );
				return 2;
			}
		}
	}

	return 0;
}


# Expands an existing area to cover the players current location
sub expandArea
{
	my $areaName = shift;
	my $playerName = shift;
	my $map = serverStatus::getMap();

	my $areaID = areaNameToID ( $areaName );
	if ( $areaID != -1 )
	{
		if ( exists $curplayers{lc($playerName)} )
		{
			my $objectid = $curplayers{lc($playerName)};
			if ( exists $gameobjects{$objectid} )
			{
				my $object = $gameobjects{$objectid};

				# Expand area to cover their present position
				if ( $object->{x} > $areaData->{'map'}->{$map}->{'area'}[$areaID]->{'topright'}->{x} )
					{ $areaData->{'map'}->{$map}->{'area'}[$areaID]->{'topright'}->{x} = ceil( $object->{x} ) }

				elsif ( $object->{x} < $areaData->{'map'}->{$map}->{'area'}[$areaID]->{'bottomleft'}->{x} )
					{ $areaData->{'map'}->{$map}->{'area'}[$areaID]->{'bottomleft'}->{x} = floor( $object->{x} ) }

				if ( $object->{y} > $areaData->{'map'}->{$map}->{'area'}[$areaID]->{'topright'}->{y} )
					{ $areaData->{'map'}->{$map}->{'area'}[$areaID]->{'topright'}->{y} = ceil( $object->{y} ) }

				elsif ( $object->{y} < $areaData->{'map'}->{$map}->{'area'}[$areaID]->{'bottomleft'}->{y} )
					{ $areaData->{'map'}->{$map}->{'area'}[$areaID]->{'bottomleft'}->{y} = floor( $object->{y} ) }

				updateXMLFile();
				return 1;
			}
		}
	}

	return 0;
}


1;