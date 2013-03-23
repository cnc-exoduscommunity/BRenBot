#!/usr/bin/perl

package commands;
use strict;

use POE;
use XML::Simple;
use XML::Parser;

use gamelog;
use brconfig;
use modules;
use brIRC;
use gamespy;		# Used by !set command
use brAuth;
use RenRem;


# Datastore for commands.xml data
my $xml_config;		# Data from commands.xml
our @commands;		# Holds a list of all commands and aliases from commands.xml


#### Variables for voting system
my $teamsinprogress = 0;
my $voteinprogress = 0;
my %voters;					# Holds a list of playernames and their vote (1 = yes, 0 = no)


#### Other variables
my @changers;


# When this file is included immediatly read the XML data file
readXMLData();


# Read commands.xml
sub readXMLData
{
	my $xmlOld = $xml_config;
	$xml_config = "";
	my $error;

  eval
  {
    no warnings 'deprecated';  # Suppress XML::Parser::Expat warning about tied handles...
    $xml_config = XMLin("commands.xml", ForceArray => [ 'group' ] );

		# DEBUGGING
	#	use Data::Dumper;
	#	open ( DATA_DUMP, '>xmldatadump2.txt' );
	#	print DATA_DUMP Dumper($xml_config);
	#	close DATA_DUMP;

		# Under Win32 replace all &gt; with > and all &lt; with <
		while ( my ($k, $v) = each %{$xml_config->{command}} )
		{
			$v->{syntax}->{value} =~ s/&gt;/>/gi;
			$v->{syntax}->{value} =~ s/&lt;/</gi;
		}

		# Read the commands into @commands
		read_commands();
	}
	or $error = $@;
	if ( $error )
	{
		modules::console_output ( "The following error occured reading commands.xml: $error" );

		if ( $xmlOld )
		{
			modules::console_output ( "Restoring old XML data" );
			$xml_config = $xmlOld;
			read_commands();
		}
		else
		{
			modules::console_output ( "Unable to continue, shutting down..." );
			sleep(2);
			exit(1);
		}
	}
}






# Gets a list of allowed usergroups for the specified command level
sub get_permission_level
{
	my $CommandLevel = shift;

	my $permissions = $xml_config->{level}->{permission};

	foreach ( @{$permissions} )
	{
		return @{$_->{usergroup}} if ( $CommandLevel eq $_->{level});
	}
}


# Get status for the given user, either IRC or ingame.
sub check_permissions
{
	my $nickname		= shift;
	my $ircChannelCode	= shift;

	if ( $nickname =~ "\@IRC" )		# IRC user, check their permission level
	{
		return brIRC::getUserPermissions ( $nickname, $ircChannelCode );
	}
	else
	{
		# Check if they have admin or mod status ingame
		if ( modules::IsAdmin($nickname) ) { return "ingame_admin"; }
		if ( modules::IsFullMod($nickname) ) { return "ingame_full_mod"; }
		if ( modules::IsHalfMod($nickname) ) { return "ingame_half_mod"; }
		if ( modules::IsTempMod($nickname) ) { return "ingame_temp_mod"; }

		return "ingame_normal";
	}
}


# Reads the commands from the XML datastore ($xml_config) and returns a list
# of command names and aliases.
sub read_commands
{
	# If there's any data already in the array destroy it
	@commands = ();

	# Start looping through the xml data
	while ( my ($key, $value) = each %{$xml_config->{command}} )
	{
		my %command = ( 'name' => $key );
		push ( @commands, \%command );

		if ( $value->{alias} )
		{
			# Is the alias element an array? If so there are multiple aliases
			if ( ref($value->{alias}) eq "ARRAY" )
			{
				my $numAliases = scalar($value->{alias});
				foreach ( @{$value->{alias}} )
				{
					my %alias = ( 'name' => $_, 'alias' => $key );
					push ( @commands, \%alias );
				}
			}

			# Else only one alias
			else
			{
				my %alias = ( 'name' => $value->{alias}, 'alias' => $key );
				push ( @commands, \%alias );
			}
		}
	}
}

#** \function private find_command ( $command_name )
# \brief Attempts to find the command with the specified name or alias
#
# \returns $command_name The full name of the commmand, or undef if none was found
# \returns $command_config Configuration settings for the command, or undef if none was found
#*
sub find_command
{
  my $command_name = shift;
  
  my $found = 0;
  foreach ( @commands )
  {
    if ( $command_name eq $_->{'name'} )
    {
      # If this is an alias then change to the full command name
      if ( $_->{'alias'} ) { $command_name = $_->{'alias'}; }
      return ($command_name, $xml_config->{'command'}->{$command_name});
    }
  }

  return (undef,undef);
}

sub parse_command_settings
{
  my $configuration = shift;

  my @commandgroups;
  my @modules;

  # Get list of groups ( where this command can be used )
  if ( $configuration->{group} )
  {
    # Is the group element an array? If so there are multiple groups
    if ( ref($configuration->{group}) eq "ARRAY" )
    {
      foreach ( @{$configuration->{group}} )
        { push (@commandgroups, $_); }
    }

    # Else only one group
    else
    {
      push (@commandgroups, $configuration->{group});
    }
  }


  # Get list of required modules
  if ( $configuration->{module} )
  {
    # Is the module element an array? If so there are multiple modules
    if ( ref($configuration->{module}) eq "ARRAY" )
    {
      foreach ( @{$configuration->{module}} )
        { push (@modules, $_); }
    }

    # Else only one module
    else
    {
      push (@modules, $configuration->{module});
    }
  }

  return (\@commandgroups, \@modules);
}


# Parse a command line
sub parsearg
{
  my $arg             = shift;
  my $playername      = shift;
  my $plugin          = shift;
  my $ircChannelCode  = shift;

  return if ( $playername =~ /^Host:/ );

#	$arg =~ s/\*/\\*/g;

  if ($arg =~ m/\!(\w+)\s*(\S*)\s*(\S*)\s*(\S*)\s*(\S*)\s*(\S*)/i)
  {
    my $command = "\L$1";
    
    my %args = (
      'arg'   => $arg,
      'arg1'  => $2,
      'arg2'  => $3,
      'arg3'  => $4,
      'arg4'  => $5,
      'arg5'  => $6
    );
    
    if ( $plugin eq "N" )
    {
      if ($playername =~ m/\@IRC/)
      {
        $args{'nick'}     = $playername;
        $args{'nicktype'} = 1;
      }
      else
      {
        $args{'nick'}     = $playername;
        $args{'nicktype'} = 0;
      }
    }
    else
    {
      $args{'nick'}     = $playername;
      $args{'nicktype'} = 2;
    }


    # Check if the player has been shunned..
    if ( playerData::getKeyValue( $args{'nick'}, "isShunned" ) )
    {
      modules::console_output ( $args{'nick'}.=' is being shunned, ignoring their commands...' );
      return;
    }
    
    
    # Search for a definition of this command in the main commands list or in any loaded plugins,
    # with plugin commands checked first to allow plugins to override built-ins
    my ($plugin_name, $command_name, $command_config) = plugin::find_command($command);
    if ( !defined $command_name or $command_config->{'enabled'}->{'value'} == 0 )
      { ($plugin_name,$command_name,$command_config) = find_command($command); }
    
    # No (enabled) command found? Guess we'll have to give up then...
    return if ( !defined $command_name or $command_config->{'enabled'}->{'value'} == 0 );
    
    # OK, got a command, parse its configuration...
    my ($commandgroups, $modules) = parse_command_settings($command_config);

    
    
    # Work out which command group the command came from
    my $current_commandgroup;
    if ($args{'nicktype'} == 1)
    {
      if ( $ircChannelCode eq "A" ) { $current_commandgroup = "irc_admin"; }
      else                          { $current_commandgroup = "irc_public"; }
    }
    elsif ($args{'nicktype'} == 0)  { $current_commandgroup = "ingame"; }
    else                            { $current_commandgroup = "plugin"; }



    # Check if we can execute the command (Not applicable for plugins)
    if ( $current_commandgroup ne "plugin" )
    {
      my $found = 0;

      # See if this command can be run from our location ( irc_admin, irc_public or ingame )
      foreach ( @{$commandgroups} )
      {
        if ( $_ eq $current_commandgroup || ( $_ eq "irc" && $args{nicktype} == 1 ) )
        {
          $found = 1;
          last;
        }
      }

      # If we didn't match any of the allowed groups then exit
      if ( $found != 1 )
      {
        modules::console_output ( "$command can not be executed in $current_commandgroup." );
        return;
      }
    }



    # Ok, we can now actually run the command
    $args{'command'}        = $command_name;
    $args{'settings'}       = $command_config;
    $args{'ircChannelCode'} = $ircChannelCode;

    
		POE::Session->create
		( inline_states =>
		{ _start =>
				sub
				{
					if ( $current_commandgroup ne "plugin" )
					{
						my $permission = check_permissions( $args{nick}, $ircChannelCode );
						# permission level of playername
						modules::console_output ( "$args{nick} 's permission: $permission" );

						my $level = $command_config->{permission}->{level};

						# level of command
						my @allowed_groups = get_permission_level($level);
						# included commands for that level
						my $found=0;

						foreach (@allowed_groups)
						{
							$found = 1 if ($permission eq $_);
						}

						if ( $found == 0 )
						{
							my $permission_name;

 							if ( $permission eq "irc_normal" ) { $permission_name = "normal IRC Users"; }
							elsif ( $permission eq "irc_voice" ) { $permission_name = "Voiced IRC Users"; }
							elsif ( $permission eq "irc_halfop" ) { $permission_name = "IRC Half Operators"; }
							elsif ( $permission eq "irc_op" ) { $permission_name = "IRC Operators"; }
							elsif ( $permission eq "irc_founder" ) { $permission_name = "IRC Founder"; }
							elsif ( $permission eq "irc_protected" ) { $permission_name = "Protected IRC Users"; }

							elsif ( $permission eq "ingame_normal" ) { $permission_name = "normal Ingame Users"; }
							elsif ( $permission eq "ingame_temp_mod" ) { $permission_name = "Temporary Moderators"; }
							elsif ( $permission eq "ingame_half_mod" ) { $permission_name = "Half Moderators"; }
							elsif ( $permission eq "ingame_full_mod" ) { $permission_name = "Full Moderators"; }
							elsif ( $permission eq "ingame_admin" ) { $permission_name = "Administrators"; }


							if ($args{nicktype} == 1)
							{
								brIRC::ircmsg ( "$command is not available for $permission_name", $ircChannelCode );
							}
							else
							{
								RenRem::RenRemCMD( "msg [BR] $command is not available for $permission_name" )
							}
							return;
						}
					}

					#execute command

					my $found=1;
					my $missing_modules;
					foreach (@{$modules})
					{
						if (modules::get_module($_) == 1)
						{
							$found=1;
							last;
						}
						else
						{
							$missing_modules .=  "$_ ";
							$found=0;
						}
					}

					if ( $found==0 )
					{
						if ($args{nicktype} == 1)
						{
							brIRC::ircmsg ( "$command requires these modules to be enabled: $missing_modules", $ircChannelCode );
						}
						else
						{
							RenRem::RenRemCMD("msg [BR] $command requires these modules to be enabled: $missing_modules")
						}
						return;
					}

          modules::console_output ( "Executing $command" );
          if ( $plugin_name ) { $_[KERNEL]->post("plugin_" . $plugin_name => "command" => \%args); }
          else                { $_[KERNEL]->yield($command_name => \%args); }
				},

			teams => \&teams,
			gameover => \&gameover,
			minelimit => \&minelimit,
			vehiclelimit => \&vehiclelimit,
			restart => \&restart,
			reboot => \&reboot,
			shutdown => \&shutdown,
			letmein => \&letmein,
			players => \&players,
			playerinfo => \&playerinfo,
			gameinfo => \&gameinfo,
			addtempmod => \&addtempmod,
			deltempmod => \&deltempmod,
			scripts => \&scripts,
			ids => \&ids,
			teamplayers => \&teamplayers,
			shown00bs => \&teamplayers,
			hostmsg => \&hostmsg,
			auth => \&auth,
			kicklog => \&kicklog,
			banlog => \&banlog,
			rules => \&rules,
			delban => \&delban,
			kick => \&kick,
			qkick => \&kick,
			ban => \&ban,
			banip => \&banip,
			allow => \&allow,
			setnextmap => \&setnextmap,
			forcetc => \&forcetc,
			page => \&page,
			pamsg => \&pamsg,
			ppage => \&ppage,
			tpage => \&tpage,
			snda  => \&snda,
			sndt  => \&sndt,
			sndp  => \&sndp,
			autoannounce => \&autoannounce,
			postmsg => \&postmsg,
			vote => \&vote,
			voting => \&voting,
			recommend => \&recommend,
			n00b => \&n00b,
			setjoin => \&setjoin,
			rotation => \&rotation,
			maplist => \&maplist,
			version => \&version,
			uptime => \&uptime,
			nextmap => \&nextmap,
			moderatorlist => \&moderatorlist,
			modules => \&modules,
			set => \&set,
			showmods => \&showmods,
			rehash => \&rehash,
			die => \&die,
			help => \&help,
			donate => \&donate,
			showmsgs => \&showmsgs,
			buildings => \&buildings,
			vehicles => \&vehicles,
			stats => \&stats,
			statsme => \&statsme,
			stop => \&stop,
			getbw => \&getbw,
			setbw => \&setbw,
			recignore => \&recignore,
			recallow => \&recallow,
			wpage => \&wpage,
			viewjoin => \&viewjoin,
			delregister => \&delregister,
			logsearch => \&LogSearch,
			kill => \&kill,
			killme => \&killme,
			admin_message => \&admin_message,
			fds => \&fds,
			about => \&about,
			shun => \&shun,
			unshun => \&unshun,
			dumplogs => \&dumpLogs,
			cmsg => \&cmsg,
			cmsgt => \&cmsg,
			cmsgp => \&cmsg,
			#getlocation => \&getLocation,
			#locate => \&locate,
			#addarea => \&addArea,
			#openarea => \&openArea,
			#updatearea => \&updateArea,
			#closearea => \&closeArea,
			recommendations => \&recommendations,
      plugins => \&plugins,
      plugin_load => \&plugin_load,
      plugin_unload => \&plugin_unload
		}
		);


	}
} # end of parsearg

############ MEMBER EVENTS UNDER HERE ################

# Searches in the log's for a specific string
#
# PARAM		String		Search Value
#
sub LogSearch
{
	my %args = %{$_[ ARG0 ]};

	$args{arg} =~ m/\!logsearch\s(.+)/i;
	my $search = $1;

	eval
	{
		if (!($search))
		{
			my $syntaxvalue = $args{settings}->{syntax}->{value};

			if ($args{nicktype} == 1)
			{
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
			{
				RenRem::RenRemCMD( "[BR] Usage: $syntaxvalue" );
			}

			return;
		}

		# Retrieve logs from the database
		my @logsArray = brdatabase::findLogs ( $search, 8 );
		if ( scalar(@logsArray) == 0 )
		{
			brIRC::ircmsg ( "No logs were found containing the string $search.", $args{'ircChannelCode'} );
			return;
		}

		else
		{
			brIRC::ircmsg ( "Results of your search (Maximum of 8 will be shown)", $args{'ircChannelCode'} );

			foreach ( @logsArray )
			{
				# Put the search string in bold, and output to IRC
				$_->{'log'} =~ s/($search)/$1/ig;
				$_->{'timestamp'} = modules::get_past_date_time ( "[DD/MM/YY - hh:mm]", $_->{'timestamp'} );
				brIRC::ircmsg ( "$_->{'timestamp'} $_->{'log'}", $args{'ircChannelCode'} );
			}
		}
	}
	or modules::display_error($@);

	return;
}


sub statsme
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		my ( $result, %player ) = playerData::getPlayerData ( $args{nick} );
		if ( $result == 1 )
		{
			modules::pagePlayer ( $player{'id'}, "BRenBot", "Stats for $player{name}: Kills $player{stats_kills}, Deaths $player{stats_deaths}, Vehicle Repair $player{stats_vehicleRepair}, Building Repair $player{stats_buildingRepair}, Buildings destroyed $player{stats_buildingKills}" );
		}
	}
	or modules::display_error($@);
}

sub stats
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		if (!$args{arg1})
		{
			my $syntaxvalue = $args{settings}->{syntax}->{value};
			brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			return;
		}

		my ( $result, %player ) = playerData::getPlayerData ( $args{arg1} );
		if ( $result == 1 )
		{
			gamelog::show_stats( $player{'name'}, $args{'ircChannelCode'} );
		}
	}
	or modules::display_error($@);
}

sub vehicles
{
	my %args = %{$_[ ARG0 ]};
	gamelog::display_vehicles( $args{'ircChannelCode'} );
}

sub buildings
{
	my %args = %{$_[ ARG0 ]};
	gamelog::display_buildings( $args{'ircChannelCode'} );
}

sub showmsgs
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		my $linenum=1;
		foreach (@brconfig::messages) {
			brIRC::ircmsg ( "$linenum:$_", $args{'ircChannelCode'} );
			$linenum++;
		}
	}
	or modules::display_error($@);
}



# Function for the !help command, shows a user the commands they can use.
sub help
{
  my %args = %{$_[ ARG0 ]};

  eval
  {
    if ( $args{'arg1'} )
    {
      my $command = $args{'arg1'};
      
      my ($plugin_name, $command_name, $command_config);
      ($command_name,$command_config) = find_command($command);
      if ( !defined $command_name or $command_config->{'enabled'}->{'value'} == 0 )
        { ($plugin_name,$command_name,$command_config) = plugin::find_command($command); }
        
    
      # No (enabled) command found? Report failure...
      if ( !defined $command_name or $command_config->{'enabled'}->{'value'} == 0 )
      {
        if ($args{'nicktype'} == 1) { brIRC::ircmsg ( "$command is unknown.", $args{'ircChannelCode'} ); }
        else { RenRem::RenRemCMD("msg [BR] $command is unknown."); }
        return;
      }
      
      
      # OK, got a command, print its help data, if any exists
      if ($command_config->{'help'}->{'value'} and $command_config->{'syntax'}->{'value'})
      {
        if ($args{'nicktype'} == 1)
        {
          brIRC::ircmsg ( "$command: $command_config->{help}->{value}", $args{'ircChannelCode'} );
          brIRC::ircmsg ( "Usage: $command_config->{syntax}->{value}", $args{'ircChannelCode'} );
        }
        else
        {
          RenRem::RenRemCMD("msg [BR] $command: $command_config->{help}->{value}");
          RenRem::RenRemCMD("msg [BR] Usage: $command_config->{syntax}->{value}");
        }
        return;
      }
      
      
      # No help data.. oh dear...
      if ($args{'nicktype'} == 1) { brIRC::ircmsg ( "No help for $command!", $args{'ircChannelCode'} ); }
      else { RenRem::RenRemCMD("msg [BR] No help for $command!"); }
      return;
    } # end of command specific help
    
    
    # OK, no command specified so find all commands available to this user at their permission level...
    my $permission = check_permissions( $args{'nick'}, $args{'ircChannelCode'} );
    modules::console_output ( $args{'nick'}."'s permission: $permission" );

    my $c = $xml_config->{command};
    my @found_commands;

    my $current_commandgroup;
    if ($args{nicktype} == 1)
    {
      if ( $args{'ircChannelCode'} eq "A" )
        { $current_commandgroup = "irc_admin"; }
      else
        { $current_commandgroup = "irc_public"; }
    }
    else
      { $current_commandgroup = "ingame" }


    my @plugins = plugin::get_plugin_event("command");



    # Loop through built in commands
    foreach (@commands)
    {
      my $command_name = $_->{'name'} if ($_->{'name'});

      # Don't list aliases
      next if ( !defined $command_name or exists($_->{'alias'}) );

      # Get config for this command
      my $command_config = $xml_config->{'command'}->{$command_name};
      
      # Ignore hidden commands
      next if ( exists($command_config->{'hideInHelp'}->{'value'}) && $command_config->{'hideInHelp'}->{'value'} != 0 );
      
      # Get command groups for this users permission level
      my ($commandgroups, undef) = parse_command_settings($command_config);
      my @allowed_groups = get_permission_level($command_config->{'permission'}->{'level'});

      # Find which command groups are permitted for this level
      my $found=0;
      foreach (@allowed_groups)
      {
        $found = 1 if ( $permission eq $_  );
      }

      if ($found == 1)
      {
        $found=0;
        foreach (@{$commandgroups})
        {
          if ( $_ eq $current_commandgroup || ( $_ eq "irc" && $args{'nicktype'} == 1 ) )
          {
            $found=1;
            last;
          }
        }


        if ( $found == 1 )
          { push ( @found_commands, "!$command_name" ); }
      }
    }

    
    # Loop through plugins
    while ( my($command_name, $data) = each %plugin::commands )
    {
      # Ignore aliases and hidden commands
      next if ( $data->{'alias_for'} );
      
      # Ignore hidden commands
      my $command_config = $data->{'configuration'};
      next if (exists($command_config->{'hideInHelp'}->{'value'}) && $command_config->{'hideInHelp'}->{'value'} != 0);
      
      # Get command groups for this users permission level
      my ($commandgroups, undef) = parse_command_settings($command_config);
      my @allowed_groups = get_permission_level($command_config->{'permission'}->{'level'});

      # Find which command groups are permitted for this level
      my $found=0;
      foreach (@allowed_groups)
      {
        $found = 1 if ($permission eq $_);
      }

      if ($found == 1)
      {
        $found=0;

        foreach (@{$commandgroups})
        {
          if ($_ eq $current_commandgroup)
          {
            $found=1;
            last;
          }
        }
      }


      if ( $found == 1 )
       { push ( @found_commands, "!$command_name" ); }

    }   # end of plugins while loop

    my $line;
    my @array;
    for (my $i=0; $i <= scalar(@found_commands)-1; $i = $i+10 )
    {
      $line = $found_commands[$i];
      for ( my $j = 1; $j < 10 && $i+$j < scalar(@found_commands)-1; $j++ )
      {
        $line .= " " . $found_commands[$i+$j];
      }
      push (@array, $line);
    }

    if ($args{nicktype} == 1)
    {
      $args{nick} =~ /(.+)\@.+/;
      my $nick = $1;

      brIRC::ircnotice ( $nick, "[BR] Available commands for $args{nick}" );
      foreach (@array) { brIRC::ircnotice ( $nick, "$_" ); print $_."\n"; }
    }
    else
    {
      my ( $result, %player ) = playerData::getPlayerData ( $args{nick} );
      if ( $result == 1 )
      {
        modules::pagePlayer ( $player{'id'}, "BRenBot", "Available commands for $player{name}:" );
        foreach ( @array ) { modules::pagePlayer ( $player{'id'}, "BRenBot", $_ ); }
      }
    }
  }
  or modules::display_error($@);
}


# !die command - Shuts down BRenBot
sub die
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		my $arg = $args{arg};

		if (!($arg eq "!die NOW"))
		{
			if ( $args{nicktype} != 1 )
			{
				RenRem::RenRemCMD( "msg [BR] Usage: !die NOW -CASE SENSITIVE! TO AVOID ACCIDENTAL TRIGGERING" );
			}
			else
			{
				brIRC::ircmsg ( "Usage: !die NOW -CASE SENSITIVE! TO AVOID ACCIDENTAL TRIGGERING", $args{'ircChannelCode'} );
			}
		}
		else { exit(0); }
	}
	or modules::display_error($@);
}


# !rehash command - Reloads most settings for BRenBot
sub rehash
{
	eval
	{
		brconfig::init();
		gamelog::loadPresets();

		# Reload XML settings
		readXMLData();

		RenRem::RenRemCMD( "msg [BR] BRenBot Configuration Files Rehashed By Admin" );
	}
	or modules::display_error($@);
}


# Shows which ingame players are moderators, and what level they are.
#
sub showmods
{
	eval
	{
		my $mods = 0;
		my $modslist;

		my %playerlist = playerData::getPlayerList();
		while ( my ( $id, $player ) = each ( %playerlist ) )
		{
			if (modules::IsAdmin($player->{'name'}))
			{
				$mods++;
				$modslist .= $brconfig::config_admin_symbol . "$player->{'name'} ";
			}

			elsif (modules::IsFullMod($player->{'name'}))
			{
				$mods++;
				$modslist .= $brconfig::config_full_mod_symbol . "$player->{'name'} ";
			}

			elsif (modules::IsHalfMod($player->{'name'}))
			{
				$mods++;
				$modslist .= $brconfig::config_half_mod_symbol . "$player->{'name'} ";
			}

			elsif (modules::IsTempMod($player->{'name'}))
			{
				$mods++;
				$modslist .= $brconfig::config_temp_mod_symbol . "$player->{'name'} ";
			}
		}
		if (!($mods))
		{
			RenRem::RenRemCMD( "msg [BR] No known moderators are currently in the server." );
		}
		else
		{
			RenRem::RenRemCMD( "msg [BR] InGame Moderators: $modslist" );
		}
	}
	or modules::display_error($@);
}


# Used to turn modules on or off.
#
# PARAM		String		Module Name
# PARAM		String		Status ( On / Off )
#
sub set
{
	my $kernel = $_[KERNEL];
	my %args = %{$_[ ARG0 ]};

	eval
	{
		if (!$args{arg1})
		{
			my $syntaxvalue = $args{settings}->{syntax}->{value};

			if ($args{nicktype} == 1)
			{
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
			{
				RenRem::RenRemCMD("[BR] Usage: $syntaxvalue");
			}

			return;
		}

		my $module_name = $args{arg1};
		my $status = $args{arg2};

		if ( (!$module_name) && (!$status) )
		{
			brIRC::ircmsg ( "Usage: !set <modulename> on/off", $args{'ircChannelCode'} );
			return;
		}

		my @modules = modules::get_modules();
		my $found=0;

		foreach (@modules)
		{
			if ($_->{'name'} eq $module_name)
			{
				$found = 1;
				if ($_->{'locked'} eq 1)
				{
					brIRC::ircmsg ( "Module $module_name is locked and cannot be changed.", $args{'ircChannelCode'} );
					return;
				}
			}
		}

		if ( $found == 0 )
		{
			brIRC::ircmsg ( "Unknown module $module_name. Use !modules to list known modules.", $args{'ircChannelCode'} );
			return;
		}

		if ( ($status ne "on") && ($status ne "off") )
		{
			brIRC::ircmsg ( "Status must be either on or off!", $args{'ircChannelCode'} );
			return;
		}

		if ( lc($module_name) eq "brenbot_dll" || lc($module_name) eq "bhs" )
		{
			brIRC::ircmsg ( "State of module $module_name cannot be altered using this command, to enable or disable the module please install or delete the relevent dll files from the server.", $args{'ircChannelCode'} );
			return;
		}

		if ( $status eq "on" )
		{
			brIRC::ircmsg ( "Activated module $module_name.", $args{'ircChannelCode'} );
			modules::set_module( $module_name, 1 );

			if ( $module_name eq "gamelog" )
			{
				gamelog::init(1);
				if ( $brconfig::gamelog_in_ssgm == 1 )
					{ brIRC::ircmsg ( "Gamelog may not work fully until the next map loads.", $args{'ircChannelCode'} ); }
			}

			if ( $module_name eq "ssgmlog" )
			{
				ssgm::start();
			}

			if ( $module_name eq "gamespy_players" )
			{
				gamespy::init();
			}
		}
		if ( $status eq "off" )
		{
			brIRC::ircmsg ( "Deactivated module $module_name.", $args{'ircChannelCode'} );
			modules::set_module( $module_name, 0 );

			if ( $module_name eq "gamelog" )
			{
				if ( $brconfig::gamelog_in_ssgm != 1 )
					{ $kernel->post( "gamelog_tail" => "stop_gamelog" ); }
			}

			if ( $module_name eq "ssgmlog" )
			{
				$kernel->post( "ssgm_tail" => "stop_ssgmlog" );
			}

			if ( $module_name eq "gamespy_players" )
			{
				gamespy::shutdown();
			}
		}

	}
	or modules::display_error($@);

}


# Lists all current modules, showing them in green if they are active, or red otherwise.
sub modules
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		my @modules = modules::get_modules();

		if ($args{nicktype} != 1)
		{
			RenRem::RenRemCMD("msg [BR] This command can only be executed from IRC.");
			return;
		}

		$args{nick} =~ m/(.+)\@.+/i;
		my $nick = $1;

		brIRC::ircnotice ( $nick, "1Current module statuses. Type !about <module> to get a description of that module." );

		my @modulesList;

		foreach (@modules)
		{
			my $module = ( $_->{'status'} == 1 )
				? '09' . $_->{'name'} . ''
				: ( $_->{'status'} == -1 )
					? '07' . $_->{'name'} . ''
					: '04' . $_->{'name'} . '';
			push ( @modulesList, $module );
		}

		for ( my $i =0; $i <= scalar(@modulesList)-1; $i +=4 )
		{
			my $module1 = modules::padd_string ( 20, $modulesList[$i] );
			my $module2 = modules::padd_string ( 20, $modulesList[$i+1] );
			my $module3 = modules::padd_string ( 20, $modulesList[$i+2] );

			# Fourth one does not need padding, it comes at the end of the line
			brIRC::ircnotice ( $nick, "$module1 $module2 $module3 $modulesList[$i+3]" );
		}
	}
	or modules::display_error($@);
}

# Returns a description for the specified module
#
# PARAM		String		Module Name
#
sub about
{
	my %args = %{$_[ ARG0 ]};

	if ( $args{arg1} )
	{
		my ( $result, $description ) = modules::get_module_description($args{arg1});

		if ( $result == 1 )
		{
			brIRC::ircmsg ( "Module $args{arg1}: $description", $args{'ircChannelCode'} );
		}
		else
		{
			brIRC::ircmsg ( "$args{arg1} is not a valid module.", $args{'ircChannelCode'} );
		}
	}
	else
	{
		my $syntaxvalue = $args{settings}->{syntax}->{value};
		brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
	}
}



# Prints a list of all current server admins and mods to the IRC
#
sub moderatorlist
{
	my %args = %{$_[ ARG0 ]};

	my $adminlist = "Administrators:";
	my $fmodlist = "Full Moderators:";
	my $hmodlist = "Half Moderators:";

	my $key;
	foreach $key ( keys %brconfig::admins )
	{
		$adminlist .= ' ' . $brconfig::admins{$key};
	}

	foreach $key ( keys %brconfig::fullMods )
	{
		$fmodlist .= ' ' . $brconfig::fullMods{$key};
	}

	foreach $key ( keys %brconfig::halfMods )
	{
		$hmodlist .= ' ' . $brconfig::halfMods{$key};
	}

	brIRC::ircmsg ( $adminlist, $args{'ircChannelCode'} );
	brIRC::ircmsg ( $fmodlist, $args{'ircChannelCode'} );
	brIRC::ircmsg ( $hmodlist, $args{'ircChannelCode'} );
}



# Shows the next map in the rotation
#
sub nextmap
{
	eval
	{
		RenRem::RenRemCMD( "game_info" );

		my $nextmap = modules::GetNextMap( serverStatus::getMap() );

		if ( $nextmap->{'mapname'} )
		{
			RenRem::RenRemCMD( "msg The next map will be: $nextmap->{'mapname'}" );
		}
		else
		{
			modules::console_output ( "Unable to work out next map!" );
			RenRem::RenRemCMD( "msg The next map will be: Unknown!" );
		}
	}
	or modules::display_error($@);
}

sub uptime
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		my $uptime = modules::get_uptime( $main::start_time );

		if ( $args{nicktype} == 1 ) { brIRC::ircmsg ( "I\'ve been running for $uptime.", $args{'ircChannelCode'} ); }
		else { RenRem::RenRemCMD ( "msg [BR] I\'ve been running for $uptime." ); }
	}
	or modules::display_error($@);
}


# Shows the current version of BRenBot running on the server.
#
sub version
{
	my %args = %{$_[ ARG0 ]};

	if ($args{'nicktype'} == 1)
	{
		brIRC::ircmsg ( "I\'m running BRenBot ".main::BR_VERSION." (build ".main::BR_BUILD.").", $args{'ircChannelCode'} );
		brIRC::ircmsg ( "BRenBot is Copyright ".main::BR_COPYRIGHT_YEAR." by Tiberian Technologies. All rights reserved.", $args{'ircChannelCode'} );
	}
	else
	{
		RenRem::RenRemCMD ( "msg [BR] I\'m running BRenBot ".main::BR_VERSION." (build ".main::BR_BUILD.")." );
		RenRem::RenRemCMD ( "msg [BR] BRenBot is Copyright ".main::BR_COPYRIGHT_YEAR." by Tiberian Technologies. All rights reserved." );
	}
}

sub maplist
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		my @array = modules::GetInstalledMaps();

		foreach (@array)
		{
			brIRC::ircmsg ( $_, $args{'ircChannelCode'} );
		}
	}
	or modules::display_error($@);
}

sub rotation
{
	eval
	{
		my @array = modules::GetRotation();

		foreach (@array)
		{
			RenRem::RenRemCMD ( "msg $_" );
		}
	}
	or modules::display_error($@);
}



###################################################
####
## Commands related to join messages (module join_messages)
####
###################################################

# !setjoin command - Sets a users join message
sub setjoin
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		return if ( $args{'nicktype'} == 1 );

		if (!$args{arg1})
		{
			my $syntaxvalue = $args{settings}->{syntax}->{value};
			modules::pagePlayer( $args{'nick'}, 'BRenBot', "Usage: $syntaxvalue" );
			return;
		}

		if ($args{arg} =~ /^\!setjoin\s((.+))/i)  #set joinmessage
	 	{
			my $setjoin_msg = substr( $1, 0, 249 ); # Limit length to prevent FDS crash
			modules::set_joinmessage( $args{'nick'}, $setjoin_msg );
			modules::pagePlayer( $args{'nick'}, 'BRenBot', "Your join message has been set." );
			return;
		}

	}
	or modules::display_error($@);
}

# !viewjoin command - Shows a user their current join message
sub viewjoin
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		return if ( $args{'nicktype'} == 1 );

		my $jointext = modules::get_joinmessage( $args{'nick'} );

		if ( $jointext )
		{
			$jointext=substr($jointext,0,249); # Limit length to prevent FDS crash
			modules::pagePlayer( $args{'nick'}, 'BRenBot', "Your joinmessage is '$jointext'" );
		}
		else
		{
			modules::pagePlayer( $args{'nick'}, 'BRenBot', "You do not have a join message set. Set one with !setjoin <jointext>." );
		}
	}
	or modules::display_error($@);
}









sub teams
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	if ( $args{arg1} eq "has" && $args{arg2} eq "been" )
	{
		return;
	}

	if ( $teamsinprogress == 1 )
	{
		RenRem::RenRemCMD( "msg Team Regulator is already in progress. Please wait until it finishes." );
		return;
	}

	my $difference=0;
#	print "Players GDI: $gameinfo{'gdi_players'}\n";
#	print "Players NOD: $gameinfo{'nod_players'}\n";
	my $superior_team;
	my $players_gdi = serverStatus::getPlayers_GDI();
	my $players_nod = serverStatus::getPlayers_Nod();
	if ( ( $players_gdi - $players_nod ) > 0 )
	{
		$difference = $players_gdi - $players_nod;
		$superior_team = "GDI";
#		print "DEBUG: GDI has more players\n";
	}

	if ( ( $players_nod - $players_gdi ) > 0)
	{
		$difference = $players_nod - $players_gdi;
		$superior_team = "NOD";
#		print "DEBUG: Nod has more players\n";
	}

#	print "DEBUG: Difference is $difference\n";

	undef $players_gdi;
	undef $players_nod;

	if ($difference == 0)
	{
		if ($args{nicktype} == 1)
		{
			brIRC::ircmsg ( "Teams are even!", $args{'ircChannelCode'} );
		}
		else
		{
			RenRem::RenRemCMD("msg [BR] Teams are even!");
		}

	}

	if ($difference == 1)
	{
		if ($args{nicktype} == 1)
		{
			brIRC::ircmsg ( "$superior_team has one more player. There is nothing I can do about it.", $args{'ircChannelCode'} );
		}
		else
		{
			RenRem::RenRemCMD("msg [BR] $superior_team has one more player. There is nothing I can do about it.");
		}
	}

	if ($difference > 1 )
	{
#		print "DEBUG: Starting Team Purge\n";
		my $count;
		@changers = ();
		my $nicknames;

		foreach (reverse(@renlog::team_changers))
		{
			if ($_->{'side'} eq $superior_team)
			{
				if ( (time() - $_->{'time'} ) <= 300 )
				{
					my ( $result, %player ) = playerData::getPlayerData ( $_->{'name'} );
					if ( $result == 1 )
					{
						push (@changers, $_);
						$nicknames .= "$player{'name'} ";
						$count++;
#						print "DEBUG: $playerData{'name'} has changed to $_->{'side'}\n";
						last if ($count >= $difference);
					}
				}
			}
		}

		#@renlog::team_changers = ();
		if ($nicknames)
		{

			if (modules::get_module("bhs") )
			{

				foreach (@changers)
				{
					my ( $result, %player ) = playerData::getPlayerData ( $_->{name} );
					if ( $result == 1 )
					{
						my $team=0;
						$team = 0 if ($player{side} eq "GDI" || $player{side} eq "All");
						$team = 1 if ($player{side} eq "NOD" || $player{side} eq "Sov");
						RenRem::RenRemCMD( "msg $player{name} has been changed by [BR]." );
						RenRem::RenRemCMD( "team2 $player{id} $team" );
						modules::pagePlayer( $player{'id'}, "BRenBot", "TeamRegulator has changed your team, because you did not even teams." );

					}
				}
			} # end of bhs
			else
			{
				RenRem::RenRemCMD("msg [BR] Teams are uneven! These players will be kicked in 1 minute: $nicknames");
				$teamsinprogress = 1;

				POE::Session->create
				( inline_states =>
					{ _start =>	sub {
								$_[HEAP]->{next_alarm_time} = int( time() ) + 30;
								$_[KERNEL]->alarm( warning => $_[HEAP]->{next_alarm_time} );
								$_[KERNEL]->alias_set( "teams" );
							},
					warning =>	sub {
#								print "tick at ", time(), "\n";
								warn_teamchangers();
								$_[HEAP]->{next_alarm_time} = int( time() ) + 30;
								$_[KERNEL]->alarm( tick => $_[HEAP]->{next_alarm_time} );
							},
					tick =>		sub {
#								print "tick at ", time(), "\n";
								check_team_status();
								$teamsinprogress=0;
								$_[KERNEL]->alarm( tick => undef );
								$_[KERNEL]->alias_remove( "teams" );
							},
					cancel =>	sub {
								$_[KERNEL]->alarm( tick => undef );
								$_[KERNEL]->alias_remove( "teams" );
							}
					}
				);
			} # end of non bhs
		} # end of nicknames
		else
		{
			RenRem::RenRemCMD("msg [BR] Teams are uneven! Please even the teams!");
			$teamsinprogress=0;
		}

	} # end of difference
	else
	{
		$teamsinprogress=0;
	}
}



sub warn_teamchangers
{
	my $difference;
	my $players_gdi = serverStatus::getPlayers_GDI();
	my $players_nod = serverStatus::getPlayers_Nod();

	if ( $teamsinprogress eq 0 )
	{
		return;
	}

	if ( ( $players_gdi - $players_nod ) > 0 )
	{
		$difference = $players_gdi - $players_nod;
	}
	if ( ( $players_nod - $players_gdi ) > 0 )
	{
		$difference = $players_nod - $players_gdi;
	}

	undef $players_gdi;
	undef $players_nod;


	if ($difference > 1)
	{
		my $nicknames;
		foreach (@changers)
		{
			my $found=0;
			my $otherside;
			$otherside = "NOD" if $_->{'side'} eq "GDI";
			$otherside = "GDI" if $_->{'side'} eq "NOD";
			my $name = $_->{'name'};
			my $old_name;
			foreach (reverse(@renlog::team_changers))
			{
				if ($_->{'name'} eq $name)
				{
					$found=1;
					$old_name = $_;
					last;
				}
			}

			if ($found==1)
			{
				if ($old_name->{'side'} eq $otherside)
				{
					#RenRemCMD("msg $old_name->{'name'} will be no longer kicked.");
				} else
				{
					#print "DEBUG: $old_name->{'name'} is still $old_name->{'side'}\n";
					#RenRemCMD("msg [BR] $old_name->{'name'} is being kicked by BlazeRegulator for:  making teams uneven");
					#sleep(1);
					$nicknames .= $old_name->{'name'} . " ";
					#RenRemCMD("kick $old_name->{'id'}");
				}
			}
		}
		RenRem::RenRemCMD("msg [BR] Even Teams! The following players will be kicked in 30 seconds: $nicknames");
	} # end of difference

} #end of function



sub check_team_status
{
	my $difference;
	my $players_gdi = serverStatus::getPlayers_GDI();
	my $players_nod = serverStatus::getPlayers_Nod();

	if ( $teamsinprogress eq 0 )
	{
		return;
	}

	if ( ( $players_gdi - $players_nod ) > 0 )
	{
		$difference = $players_gdi - $players_nod;
	}
	if ( ( $players_nod - $players_gdi ) > 0 )
	{
		$difference = $players_nod - $players_gdi;
	}

	undef $players_gdi;
	undef $players_nod;

	if ($difference > 1)
	{
		foreach (@changers)
		{
			my $found=0;
			my $otherside;
			$otherside = "NOD" if $_->{'side'} eq "GDI";
			$otherside = "GDI" if $_->{'side'} eq "NOD";
			my $name = $_->{'name'};
			my $old_name;
			foreach (reverse(@renlog::team_changers))
			{
				if ($_->{'name'} eq $name)
				{
					$found=1;
					$old_name = $_;
					last;
				}
			}

			if ($found==1)
			{
				# If they have changed back to their original team let them off the hook
				if ($old_name->{'side'} eq $otherside)
				{
					RenRem::RenRemCMD("msg $old_name->{'name'} will be no longer kicked.");
				}
				else	# Otherwise kick them
				{
					modules::kick_player ( $old_name->{'name'}, 'BRenBot', 'Making the teams uneven' );
				} # end of else
			}
		}
	}
} #end of function





sub postmsg
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		if (!$args{arg1})
		{
			my $syntaxvalue = $args{settings}->{syntax}->{value};

			if ($args{nicktype} == 1)
			{
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
			{
				RenRem::RenRemCMD("msg [BR] Usage: $syntaxvalue");
			}

			return;
		}

		my $msgnum  = $args{arg1};

		postrule( $msgnum, $args{'ircChannelCode'} );
	}
	or modules::display_error($@);
}

sub postrule
{
	my $msgnum			= shift;
	my $ircChannelCode	= shift;

	eval
	{
		my $linenum = 1;
		my @msg	 = @brconfig::messages;

		foreach (@msg)
		{
			if ($msgnum eq $linenum)
			{
				my $message = $brconfig::messages[$linenum-1];

				if ($brconfig::config_botmode eq "WIN32")
				{
					$message=substr($message,0,228); #limit length to <249 chars to prevent fds crash
				}

				RenRem::RenRemCMD("msg $message");
				return;
			}

			$linenum++;
		}

		brIRC::ircmsg( "That message number does not exist. Try the !showmsgs command.", $ircChannelCode );
	}
	or modules::display_error($@);
}

sub autoannounce
{
	eval
	{
		brconfig::ReadAutoAnnounce();
		modules::AutoAnnounce_DoAnnoucement();
	}
	or modules::display_error($@);
}

sub donate
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		my $user;
		my $money;

		# Cannot be used from IRC
		if ( $args{'nicktype'} == 1 )
		{
			brIRC::ircmsg ( "You need to be ingame to use this command.", $args{'ircChannelCode'} );
			return;
		}

		# Check syntax, get arguments
		if ( $args{arg} =~ m/^\!\S+\s(.+)\s(\d+)$/i )
		{
			$user = $1;
			$money = $2;
		}
		else
		{
			my $syntaxvalue = $args{settings}->{syntax}->{value};
			RenRem::RenRemCMD( "msg [BR] Usage: $syntaxvalue" );
			return;
		}

		# Check BHS.dll is enabled
		if ( modules::get_module( "bhs" ) == 1 )
		{
			my ( $result, %player ) = playerData::getPlayerData ( $args{'nick'}, 1 );
			if ( $result == 1 )
			{
				# Check if gamelog is enabled (required for donations)
				if ( modules::get_module( "gamelog" ) != 1 && $brconfig::config_seperate_donate != 1 )
				{
					modules::pagePlayer( $player{'id'}, "BRenBot", "Donations are not enabled on this server. Ask your admin to turn gamelog on." );
					return;
				}

				# Check if donate module is enabled
				if ( modules::get_module( "donate" ) != 1 )
				{
					modules::pagePlayer( $player{'id'}, "BRenBot", "Donations have been disabled by the administration." );
					return;
				}

				my ( $result2, %player2 ) = playerData::getPlayerData ( $user );
				if ( $result2 == 1 )
				{
					if ( $player2{'name'} eq $player{'name'} )
					{
						modules::pagePlayer( $player{'id'}, "BRenBot", "You can't donate money to yourself!" );
						return;
					}

					if ( $player2{'side'} eq $player{'side'} )
					{
						if ( $money <= 0 )
						{
							modules::pagePlayer( $player{'id'}, "BRenBot", "You can't donate negative money!" );
							return;
						}

						if ( gamelog::isPlayerLoaded( $player2{'name'} ) )
						{
							my $donatelimit = $modules::donatelimit *60;

							if ( ($donatelimit != 0) && ( serverStatus::getMapStartTime() != 0) )
							{
								my $running_time = time() - serverStatus::getMapStartTime();

								if ($running_time < $donatelimit)
								{
									my $remaining = $donatelimit - $running_time;
									$remaining = sprintf("%.0f", $remaining);
									modules::pagePlayer( $player{'id'}, "BRenBot", "Donations are not allowed on ".serverStatus::getMap()." in the first $donatelimit seconds. You have to wait $remaining seconds!" );
									return;
								}
							}

							modules::pagePlayer( $player{'id'}, "BRenBot", "You have donated $money credits to $player2{name}!" );
							modules::pagePlayer( $player2{'id'}, "BRenBot", "$player{name} has donated $money to you!" );
							RenRem::RenRemCMD( "donate $player{id} $player2{id} $money" );
						}
						else
						{
							modules::pagePlayer( $player{'id'}, "BRenBot", "$player2{name} has not done with loading this map yet.");
						}
						return;
					} # end of same team
					else
					{
						modules::pagePlayer( $player{'id'}, "BRenBot", "$player2{name} is not on your team. ");
						return;
					}

				} # end of user result=1
				else
				{
					modules::pagePlayer( $player{'id'}, "BRenBot", "$user was not found ingame, or is not unique." );
					return;
				}
			} # end of result=1
		} # end of module bhs
	}
	or modules::display_error($@);
}

sub ppage
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		if (!$args{arg1})
		{
			my $syntaxvalue = $args{settings}->{syntax}->{value};

			if ($args{nicktype} == 1)
			{
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
			{
				RenRem::RenRemCMD("msg [BR] Usage: $syntaxvalue");
			}

			return;
		}
		if ($args{arg} =~ /^\!ppage\s(.+?)\s(.+)/i)
		{ #pamsg

			if (modules::get_module("bhs") )
			{
				my $pager = $args{nick};

				my $user = $1;
				my $text = $2;
				if (! ($user)) { brIRC::ircmsg ( "Usage: !ppage <user> <text>", $args{'ircChannelCode'} ); }
				else
				{

					my ( $result, %player ) = playerData::getPlayerData( $user );
					if ( $result == 1 )
					{
						RenRem::RenRemCMD("ppage $player{id} ($pager) $text");
						brIRC::ircmsg ( "9ppage Sent to $player{name} --> \($pager): $text", $args{'ircChannelCode'} );
					}
					else
					{
						brIRC::ircmsg ( "Error: $user was not found ingame, or is not unique.", $args{'ircChannelCode'} );
					}
				}
	 		}
			else
			{
				brIRC::ircmsg ( "You need to enable module bhs and install the bhs library to use this command.", $args{'ircChannelCode'} );
			}
		}
	}
	or modules::display_error($@);
}

sub sndp
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		if (!$args{arg1})
		{
			my $syntaxvalue = $args{settings}->{syntax}->{value};

			if ($args{nicktype} == 1)
			{
				brIRC::ircmsg ( "[BR] Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
			{
				RenRem::RenRemCMD("msg [BR] Usage: $syntaxvalue");
			}

			return;
		}

		if (modules::get_module("bhs") )
		{
			my $pager = $args{nick};

			my $user = $1;
			my $snd = $2;

			my ( $result, %player ) = playerData::getPlayerData( $args{'arg1'} );
			if ( $result == 1 )
			{
				RenRem::RenRemCMD("sndp $player{id} $args{arg2}");
				brIRC::ircmsg ( "9PrivateSound sent to $player{name} --> \($pager): $args{arg2}", $args{'ircChannelCode'} );
			}
			else
			{
				brIRC::ircmsg ( "Error: $args{arg1} was not found ingame, or is not unique.", $args{'ircChannelCode'} );
			}
		}
		else
		{
			brIRC::ircmsg ( "You need to enable module bhs and install the bhs library to use this command.", $args{'ircChannelCode'} );
		}
	}
	or modules::display_error($@);
}


sub tpage
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	eval
	{
		if (!$args{arg1})
		{
			my $syntaxvalue = $args{settings}->{syntax}->{value};

			if ($args{nicktype} == 1)
			{
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
			{
				RenRem::RenRemCMD("msg [BR] Usage: $syntaxvalue");
			}

			return;
		}
		if ($args{arg} =~ /^\!tpage\s(gdi|all|1|nod|sov|0)\s(.+)/i)
		{

			if (modules::get_module("bhs") )
			{
				my $team = $1;
				my $text = $2;
				if ( $team =~ m/nod/i || $team =~ m/sov/i ) { $team = "0" }
				if ( $team =~ m/gdi/i || $team =~ m/all/i ) { $team = "1" }
				if (! ($text)) { brIRC::ircmsg ( "Usage: !tpage <team> <text>", $args{'ircChannelCode'} ); }
				else
				{
					RenRem::RenRemCMD( "cmsgt $team 0,255,0 \($args{nick} to team $team): $text" );
					RenRem::RenRemCMD( "sndt $team yo1.wav" );
					#RenRem::RenRemCMD("tpage $team ($args{nick}) $text");
					brIRC::ircmsg ( "9TeamPage Sent to Team $team --> \($args{nick}): $text", $args{'ircChannelCode'} );
				}
	 		}
			else
			{
				brIRC::ircmsg ( "You need to enable module bhs and install the bhs library to use this command.", $args{'ircChannelCode'} );
			}
		}
	}
	or modules::display_error($@);
}


sub snda
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	eval
	{
		if (!$args{arg1})
		{
			if ($args{nicktype} == 1)
			{
				my $syntaxvalue = $args{settings}->{syntax}->{value};
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
			{
				RenRem::RenRemCMD("msg [BR] Usage: $args{settings}->{syntax}->{value}");
			}
			return;
		}

		if (modules::get_module("bhs") )
		{
			my $pager = $args{nick};
			my $snd   = $args{arg1};

			RenRem::RenRemCMD("snda $args{arg1}");
			brIRC::ircmsg ( "9Global Sound --> \($pager): $args{arg1}", $args{'ircChannelCode'} );
		}
		else
		{
			brIRC::ircmsg ( "You need to enable module bhs and install the bhs library to use this command.", $args{'ircChannelCode'} );
		}
	}
	or modules::display_error($@);
}

sub sndt
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	eval
	{
		if (!$args{arg1} || !$args{arg2})
		{
			if ($args{nicktype} == 1)
			{
				my $syntaxvalue = $args{settings}->{syntax}->{value};
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
			{
				RenRem::RenRemCMD("msg [BR] Usage: $args{settings}->{syntax}->{value}");
			}
			return;
		}

		if (modules::get_module("bhs") )
		{
			my $pager = $args{nick};

			my $team = $args{arg1};
			my $snd  = $args{arg2};
			if ($team =~ /nod/i) {$team = "0"} #support user specifying NOD instead of 0
			if ($team =~ /gdi/i) {$team = "1"} #support user specifying GDI instead of 1
			RenRem::RenRemCMD("sndt $team $args{arg2}");
			brIRC::ircmsg ( "9TeamSound Sent to Team $team --> \($pager): $args{arg2}", $args{'ircChannelCode'} );
		}
		else
		{
			brIRC::ircmsg ( "You need to enable module bhs and install the bhs library to use this command.", $args{'ircChannelCode'} );
		}
	}
	or modules::display_error($@);
}


sub pamsg
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	eval
	{
		if (!$args{arg1})
		{
			if ($args{nicktype} == 1)
			{
				my $syntaxvalue = $args{settings}->{syntax}->{value};
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
			{
				RenRem::RenRemCMD("msg [BR] Usage: $args{settings}->{syntax}->{value}");
			}
			return;
		}

		if ($args{arg} =~ /^\!pamsg\s(.+?)\s(.+)/i)
		{ #pamsg

			if (modules::get_module("bhs") )
			{
				my $pager = $args{nick};

				my $user = $1;
				my $text = $2;
				if (! ($user)) { brIRC::ircmsg ( "Usage: !pamsg <user> <text>", $args{'ircChannelCode'} ); }
				else
				{

					my ($result, %player) = playerData::getPlayerData($user);
					if ($result == 1)
					{
						RenRem::RenRemCMD("pamsg $player{id} ($pager) $text");
						brIRC::ircmsg ( "9Pamsg Sent to $player{name} --> \($pager): $text", $args{'ircChannelCode'} );
					}
					else
					{
						brIRC::ircmsg ( "Error: $user was not found ingame, or is not unique.", $args{'ircChannelCode'} );
					}
				}
			}
			else
			{
				brIRC::ircmsg ( "You need to enable module bhs and install the bhs library to use this command.", $args{'ircChannelCode'} );
			}
		}
	}
	or modules::display_error($@);
}

sub page
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		if (!$args{arg1})
		{
			my $syntaxvalue = $args{settings}->{syntax}->{value};
			brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			return;
		}
		else
		{
			my $user = $args{arg1};

			$args{arg} =~ m/\!\S+\s*(\S+)\s*(.*)/i;
			my $text = $2;


			if ( modules::get_module( "bhs" ) )
			{
				if ( !($user) )
				{
					brIRC::ircmsg ( "Usage: !page <user> <text>", $args{'ircChannelCode'} );
				}
				else
				{
					my ( $result, %player ) = playerData::getPlayerData ( $user );
					if ( $result == 1 )
					{
						modules::pagePlayer( $player{'id'}, $args{'nick'}, $text );
						brIRC::ircmsg ( "9Page Sent to $player{name} --> \($args{nick}): $text", $args{'ircChannelCode'} );
					}
					else
					{
						brIRC::ircmsg ( "$user was not found in the player list, or is not unique. To page a player on WOL use !wpage instead.", $args{'ircChannelCode'} );
					}
				}
			}
			else
			{
				brIRC::ircmsg ( "You need to enable module bhs and install the bhs library to use this command.", $args{'ircChannelCode'} );
			}
		}
	}
	or modules::display_error($@);
}

sub wpage
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		if (!$args{arg1} || !$args{arg2})
		{
			if ($args{nicktype} == 1)
			{
				my $syntaxvalue = $args{settings}->{syntax}->{value};
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
			{
				RenRem::RenRemCMD("msg [BR] Usage: $args{settings}->{syntax}->{value}");
			}
			return;
		}
		else
		{ #Page

			my $user = $args{arg1};

			$args{arg} =~ m/\!(\w+)\s*(\S*)\s*(.*)/i;
			my $text = $3;

			RenRem::RenRemCMD("page $user \($args{nick}): $text");
			brIRC::ircmsg ( "9Page Sent to $user --> \($args{nick}): $text", $args{'ircChannelCode'} );
		}
	}
	or modules::display_error($@);
}

sub forcetc
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	eval
	{
		if (!$args{arg1})
		{
			if ($args{nicktype} == 1)
			{
				my $syntaxvalue = $args{settings}->{syntax}->{value};
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
			{
				RenRem::RenRemCMD("msg [BR] Usage: $args{settings}->{syntax}->{value}");
			}
			return;
		}
		my $user = $args{arg1};

		if ( modules::get_module("bhs") )
		{

			my $admin = $args{nick};

			my ( $result, %player ) = playerData::getPlayerData( $user );
			if ( $result == 1 )
			{

				if (!modules::get_module("gamelog") )
				{
					RenRem::RenRemCMD("msg [BR] Gamelog must be enabled to be able to use forcetc");
					return;
				}

				if ( gamelog::isPlayerLoaded( $player{'name'} ) )
				{
					my $team = 0;
					$team = 0 if ($player{'side'} eq "GDI" || $player{'side'} eq "All");
					$team = 1 if ($player{'side'} eq "NOD" || $player{'side'} eq "Sov");
					RenRem::RenRemCMD( "msg $player{name} has changed teams." );
					RenRem::RenRemCMD( "team2 $player{id} $team" );
					modules::pagePlayer ( $player{'id'}, "BRenBot", "$admin has changed your team by force." );
				}
				else
				{
					if ( $args{'nicktype'} == 1 ) { brIRC::ircmsg ( "Player is not finished with loading yet.", $args{'ircChannelCode'} ); }
					else { modules::pagePlayer ( $args{'nick'}, "BRenBot", "Player is not finished with loading yet." ); }
				}
			}
		}
		else
		{
			brIRC::ircmsg ( "You need to enable module bhs and install the bhs library to use this command.", $args{'ircChannelCode'} );
		}
	}
	or modules::display_error($@);
}

sub kill
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	eval
	{
		if (!$args{arg1})
		{
			if ($args{nicktype} == 1)
			{
				my $syntaxvalue = $args{settings}->{syntax}->{value};
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
			{
				RenRem::RenRemCMD("msg [BR] Usage: $args{settings}->{syntax}->{value}");
			}
			return;
		}
		my $user = $args{arg1};

		if ( modules::get_module("bhs") )
		{

			my $admin = $args{nick};

			my ( $result, %player ) = playerData::getPlayerData( $user );
			if ( $result == 1 )
			{
				if ( !modules::get_module("gamelog") )
				{
					if ($args{nicktype} == 1)
					{
						brIRC::ircmsg ( "Gamelog must be enabled to be able to use kill", $args{'ircChannelCode'} );
					}
					else
					{
						RenRem::RenRemCMD("msg [BR] Gamelog must be enabled to be able to use kill" );
					}
					return;
				}

				# If we dont have BRenBot.dll we need to swap their team twice to kill them, check this would not
				# end the game before doing so
				if ( !modules::get_module("BRenBot_dll")
					&& ( ( ( $player{side} eq "GDI" || $player{side} eq "All" ) && ( serverStatus::getPlayers_GDI() == 1 ) )
					|| ( ( $player{side} eq "NOD" || $player{side} eq "Sov" ) && ( serverStatus::getPlayers_Nod() == 1 ) ) ) )
				{
					if ($args{nicktype} == 1)
					{
						brIRC::ircmsg ( "Killing $player{name} at this time would end the game.", $args{'ircChannelCode'} );
					}
					else
					{
						RenRem::RenRemCMD("msg [BR] Killing $player{name} at this time would end the game." );
					}
					return;
				}


				# Check they are actually loaded into the game before trying to kill them
				if ( gamelog::isPlayerLoaded( $player{'name'} ) )
				{
					RenRem::RenRemCMD( "msg $player{name} has been killed by $admin." );

					# Use kill console command if BRenBot.dll is installed, otherwise use team2 twice
					if ( modules::get_module("BRenBot_dll") )
					{
						RenRem::RenRemCMD ( "eject $player{id}" );
						RenRem::RenRemCMD ( "kill $player{id}" );
					}
					else
					{
						my $team = ( $player{side} eq "GDI" || $player{side} eq "All" ) ? 0 : 1;
						RenRem::RenRemCMD( "team2 $player{id} $team" );

						$team = ( $team == 0 ) ? 1 : 0;
						RenRem::RenRemCMD( "team2 $player{id} $team" );
					}

					modules::pagePlayer ( $player{'id'}, "BRenBot", "$admin has killed you." );
				}
				else
				{
					if ($args{nicktype} == 1)
					{
						brIRC::ircmsg ( "Player is not finished with loading yet.", $args{'ircChannelCode'} );
					}
					else
					{
						RenRem::RenRemCMD ("msg [BR] Player is not finished with loading yet.");
					}
				}
			}
		}
		else
		{
			brIRC::ircmsg ( "You need to install the bhs.dll library to use this command.", $args{'ircChannelCode'} );
		}
	}
	or modules::display_error($@);
}


# Allows a player to kill themselves.
sub killme
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	eval
	{
		if ( $args{nicktype} == 1 )
		{
			brIRC::ircmsg ( "!killme cannot be used from IRC!", $args{'ircChannelCode'} );
			return;
		}

		my $user = $args{nick};

		if ( modules::get_module("bhs") )
		{
			my $admin = $args{nick};

			my ($result, %player) = playerData::getPlayerData($user);
			if ($result == 1)
			{
				if ( !modules::get_module("gamelog") )
				{
					RenRem::RenRemCMD("msg [BR] Gamelog must be enabled to be able to use killme" );
					return;
				}

				# If we dont have BRenBot.dll we need to swap their team twice to kill them, check this would not
				# end the game before doing so
				if ( !modules::get_module("BRenBot_dll")
					&& ( ( ( $player{side} eq "GDI" || $player{side} eq "All" ) && ( serverStatus::getPlayers_GDI() == 1 ) )
					|| ( ( $player{side} eq "NOD" || $player{side} eq "Sov" ) && ( serverStatus::getPlayers_Nod() == 1 ) ) ) )
				{
					modules::pagePlayer ( $player{'id'}, "BRenBot", "Killing yourself now would end the game!" );
					return;
				}


				if ( gamelog::isPlayerLoaded( $player{'name'} ) )
				{
					# Use kill console command if BRenBot.dll is installed, otherwise use team2 twice
					if ( modules::get_module("BRenBot_dll") )
					{
						RenRem::RenRemCMD ( "eject $player{id}" );
						RenRem::RenRemCMD ( "kill $player{id}" );
					}
					else
					{
						my $team = ( $player{side} eq "GDI" || $player{side} eq "All" ) ? 0 : 1;
						RenRem::RenRemCMD( "team2 $player{id} $team" );

						$team = ( $team == 0 ) ? 1 : 0;
						RenRem::RenRemCMD( "team2 $player{id} $team" );
					}
				}
				else
				{
					RenRem::RenRemCMD ("msg [BR] Player has not finished loading yet.");
				}
			}
		}
		else
		{
			brIRC::ircmsg ( "You need to install the bhs.dll library to use this command.", $args{'ircChannelCode'} );
		}
	}
	or modules::display_error($@);
}


# Changes the next map in the rotation to the one specified
#
# PARAM		String		Map name (partial or full)
#
sub setnextmap
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		if (!$args{arg1})
		{
			if ($args{nicktype} == 1)
			{
				my $syntaxvalue = $args{settings}->{syntax}->{value};
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
			{
				RenRem::RenRemCMD("msg [BR] Usage: $args{settings}->{syntax}->{value}");
			}
			return;
		}

		my ($result,$mapname) = modules::SetNextMap ( $args{'arg1'} );
		if ($result == 1)
			{ RenRem::RenRemCMD( "msg [BR] Setting next map to $mapname ..." ); }
		elsif ($result == 0)
			{ RenRem::RenRemCMD( "msg [BR] ERROR: $args{arg1} not found." ); }
		elsif ($result == 2)
			{ RenRem::RenRemCMD( "msg [BR] ERROR: $args{arg1} is not unique." ); }
		else
			{ RenRem::RenRemCMD ( "msg [BR] Error setting next map to $mapname." ); }
	}	# End of eval
	or modules::display_error($@);
}

sub allow
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		if (!$args{arg1})
		{
			if ($args{nicktype} == 1)
			{
				my $syntaxvalue = $args{settings}->{syntax}->{value};
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
			{
				RenRem::RenRemCMD("msg [BR] Usage: $args{settings}->{syntax}->{value}");
			}
			return;
		}

		my $allow = $args{arg1};
		RenRem::RenRemCMD( "allow $allow" ) if ( $brconfig::ssgm_version < 4 );

		if ( modules::remove_kick ( $allow ) )
		{
			if ( $args{'nicktype'} == 1 ) { brIRC::ircmsg ( "$allow is now allowed to return to the server.", $args{'ircChannelCode'} ); }
			else { RenRem::RenRemCMD( "msg [BR] $allow is now allowed to return to the server." ); }
		}
		else
		{
			if ( $args{'nicktype'} == 1 ) { brIRC::ircmsg ( "No kick record found for $allow. Sending WOL allow command anyway...", $args{'ircChannelCode'} ); }
			else { modules::pagePlayer ( $args{'nick'}, "BRenBot", "No kick record found for $allow. Sending WOL allow command anyway..." ); }
		}
	}
	or modules::display_error($@);
}


# Bans a player from the server
#
# PARAM		String		Player Name
# PARAM		String		Reason
#
sub ban
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		# Check the correct command syntax was used
		if ( !$args{'arg1'} || !$args{'arg2'} )
		{
			my $syntaxvalue = $args{'settings'}->{'syntax'}->{'value'};
			if ( $args{'nicktype'} == 1 )
				{ brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} ); }
			else
				{ RenRem::RenRemCMD("msg [BR] Usage: $syntaxvalue"); }
			return;
		}


		# Get the ban target and the reason for the ban
		my $target = $args{'arg1'};
		my $banner = $args{'nick'};
		my $reason = "";
		if ($args{'arg'} =~ /^.+?\s.+?\s(.+)$/i)
			{ $reason = $1; }


		# Find the player data for the ban target
		my ( $result, %player ) = playerData::getPlayerData( $target );
		if ( $result == 1 )
		{
			modules::ban_player ( $player{'id'}, $banner, $reason );
		}

		# Player data not found? Create a ban record for the nickname then
		else
		{
			modules::record_ban ( $target, $args{'nick'}, $reason, '', '' );

			if ($args{nicktype} == 1)
				{ brIRC::ircmsg ( "The nickname $target has been banned from the server.", $args{'ircChannelCode'} ); }
			else
				{ modules::pagePlayer ( $args{'nick'}, "BRenBot", "The nickname $target has been banned from the server." ); }
		}
	}
	or modules::display_error($@);


} # end of ban


# !banIP command -> used to ban IP's of players not ingame, or an IP range
sub banip
{
	my %args = %{$_[ ARG0 ]};

	my $message = "";
	if ( $args{'arg'} =~ m/^\!\S+\s*(\d+\.\d+\.\d+\.*\d*)\s+(.+)$/ )
	{
		my $ip = $1;
		my $reason = $2;

		if ( $ip =~ m/^(\d+\.\d+\.\d+)(\.)?$/ )
			{ $ip = $1.".*"; }

		modules::record_ban ( '', $args{'nick'}, $reason, '', $ip );


		if ( $ip =~ m/\.\*/ )
			{ $message = "IP range $ip has been banned from the server."; }
		else
			{ $message = "IP address $ip has been banned from the server."; }
	}
	else
		{ $message = "Usage: !banip <address/range> <reason>. Range format: 123.123.123"; }

	if ( $args{'nicktype'} == 1 )
		{ brIRC::ircmsg ( $message, $args{'ircChannelCode'} ); }
	else
		{ modules::pagePlayer ( $args{'nick'}, "BRenBot", $message ); }
}


sub delban
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		if ( $args{arg} !~ m/^\!\S+\s*\d+$/  )
		{
			if ($args{nicktype} == 1)
			{
				my $syntaxvalue = $args{settings}->{syntax}->{value};
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
				{ modules::pagePlayer( $args{'nick'}, "BRenBot", "Usage: $args{settings}->{syntax}->{value}" ); }
			return;
		}

		if (modules::del_ban($args{arg1}) == 1)
		{
			brIRC::ircmsg ( "Ban ID $args{arg1} removed.", $args{'ircChannelCode'} );
		}
		else
		{
			brIRC::ircmsg ( "There is no existing ban with ID $args{arg1}.", $args{'ircChannelCode'} );
		}
	}
	or modules::display_error($@);
}

sub rules
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		postrule( 1, $args{'ircChannelCode'} );
		if ( $modules::maprules && modules::get_module ( "map_settings" ) )
			{ RenRem::RenRemCMD ( "msg [BR] Special rules for ".serverStatus::getMap().": ".$modules::maprules ); }
	}
	or modules::display_error($@);
}

sub banlog
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		if ( length( $args{arg1} ) > 0 )
		{
			# Get matches for our search string, always use lower case
			my $search = lc( $args{arg1} );
			$search =~ s/"/""/g;
			my @banlist = brdatabase::execute_query( "SELECT * FROM bans WHERE LOWER(name) LIKE \"%$search%\" OR ip LIKE \"%$search%\" OR LOWER(reason) LIKE \"%$search%\" ORDER BY timestamp DESC" );

			if ( scalar(@banlist) > 0 )
			{
				# If there are more than 8 results bail out
				my $count = scalar(@banlist);
				if ( $count > 8 )
				{
					brIRC::ircmsg ( "More than 8 bans, refusing to show all $count bans. Showing first 8 matches...", $args{'ircChannelCode'} );
				}

				# Show first 8 results, and then return
				my $shownCount = 0;
				foreach ( @banlist )
				{
					if ( $shownCount++ >= 8 )
						{ return; }

					my %hash = %$_;
					my ( $year, $month, $day, $hour, $min, $sec) = modules::BRTime_To_Date( $hash{'timestamp'} );

					my $string = "($hash{'id'})07 $hash{'name'} ($hash{'ip'}) banned by $hash{'banner'} on $day.$month.$year $hour:$min:$sec for '$hash{'reason'}'";

					if ($search)
					{
						my $bold = "";
						$string =~ s/$search/$bold$search$bold/gi;
					}

					brIRC::ircmsg ( $string, $args{'ircChannelCode'} );
				}
			}
			else
			{
				# No bans found...
				brIRC::ircmsg ( "No bans were found matching your search.", $args{'ircChannelCode'} );
			}
		}
		else
		{
			# No search string specified...
			brIRC::ircmsg ( "Please specify a name or ip to search for.", $args{'ircChannelCode'} );
		}
	}
	or modules::display_error($@);
}

sub kicklog
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		my $searchValue = "";
		if ( $args{arg} =~ m/\!kicklog\s(.+)/i )
		{
			$searchValue = $1;
		}

		# Retrieve logs from the database
		my @logsArray = brdatabase::findLogs_Type ( $searchValue, 1 );
		if ( scalar(@logsArray) == 0 )
		{
			brIRC::ircmsg ( "No logs were found matching containing the string $searchValue.", $args{'ircChannelCode'} );
			return;
		}

		else
		{
			brIRC::ircmsg ( "Results of your search (Maximum of 8 will be shown)", $args{'ircChannelCode'} );

			foreach ( @logsArray )
			{
				# Put the search string in bold, and output to IRC
				$_->{'log'} =~ s/($searchValue)/$1/ig;
				$_->{'timestamp'} = modules::get_past_date_time ( "[DD/MM/YY - hh:mm]", $_->{'timestamp'} );
				brIRC::ircmsg ( "$_->{'timestamp'} $_->{'log'}", $args{'ircChannelCode'} );
			}
		}
	}
	or modules::display_error($@);
}

sub auth
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		if (!$args{arg1})
		{
			if ($args{nicktype} == 1)
			{
				my $syntaxvalue = $args{settings}->{syntax}->{value};
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
				{ modules::pagePlayer( $args{'nick'}, "BRenBot", "Usage: $args{settings}->{syntax}->{value}" ); }
			return;
		}

		brAuth::Authenticate ( $args{'arg1'} );
	}
	or modules::display_error($@);
}

sub hostmsg
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		if (!$args{arg1})
		{
			if ($args{nicktype} == 1)
			{
				my $syntaxvalue = $args{settings}->{syntax}->{value};
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
				{ modules::pagePlayer( $args{'nick'}, "BRenBot", "Usage: $args{settings}->{syntax}->{value}" ); }
			return;
		}
		else
		{
			if ( $args{arg} =~ /^\!.+?\s(.+)$/ )
			{
				my $msg = $1;

				# Put dots in bye or connect to prevent the
				# server from filtering them
				$msg =~ s/bye/by\.e/gi;
				$msg =~ s/connect/conn\.ect/gi;

				# Limit message length to <249 chars to prevent fds crash
				$msg = substr ( $msg, 0, 228 );

				RenRem::RenRemCMD("msg \($args{nick}): $msg");
			}
		}
	}
	or modules::display_error($@);
}

sub admin_message
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		if (!$args{arg1})
		{
			if ($args{nicktype} == 1)
			{
				my $syntaxvalue = $args{settings}->{syntax}->{value};
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
				{ modules::pagePlayer( $args{'nick'}, "BRenBot", "Usage: $args{settings}->{syntax}->{value}" ); }
			return;
		}
		else
		{
			if ( $args{arg} =~ /^\!.+?\s(.+)$/ )
			{
				my $msg = $1;
				$msg = substr($msg,0,228); #limit length to <249 chars to prevent fds crash
				RenRem::RenRemCMD("admin_message \($args{nick}): $msg");
			}
		}
	}
	or modules::display_error($@);
}


sub ids
{
	my %args = %{$_[ ARG0 ]};

	# IRC only
	if ( $args{nicktype} != 1 )
		{ return; }

	eval
	{
		my @noddies;
		my @gdiguys;

		if ( serverStatus::getCurrentPlayers() == 0 )
		{
			brIRC::ircmsg ( "There are no players ingame at this time.", $args{'ircChannelCode'} );
			return;
		}

		my %playerlist = playerData::getPlayerList();
		while ( my ( $id, $player ) = each ( %playerlist ) )
		{
			my $pname = modules::parseModName ( $player->{'name'}, 1 );

			# Append id to name
			$pname .= " ($player->{'id'})";

			# Pad name length to 28 characters
			my $minlength = 28;
			for ( my $i = 1; $i <= $minlength - length($pname); $i++ )
				{ $pname .= " "; }

			push (@noddies, $pname) if ($player->{'side'} eq "NOD" || $player->{'side'} eq "Sov");
			push (@gdiguys, $pname) if ($player->{'side'} eq "GDI" || $player->{'side'} eq "All");

		}

		for ( my $i=0; $i <= scalar(@gdiguys)-1; $i = $i+4 )
		{
			if ( $main::currentMod eq "APB" )
				{ brIRC::ircmsg ( "12Allies: $gdiguys[$i] $gdiguys[$i+1] $gdiguys[$i+2] $gdiguys[$i+3]", $args{'ircChannelCode'} ); }
			else
				{ brIRC::ircmsg ( "08GDI: $gdiguys[$i] $gdiguys[$i+1] $gdiguys[$i+2] $gdiguys[$i+3]", $args{'ircChannelCode'}); }
		}
		for ( my $i = 0; $i <= scalar(@noddies)-1; $i = $i+5 )
		{
			if ( $main::currentMod eq "APB" )
				{ brIRC::ircmsg ( "04Soviet: $noddies[$i] $noddies[$i+1] $noddies[$i+2] $noddies[$i+3]", $args{'ircChannelCode'} ); }
			else
				{ brIRC::ircmsg ( "04Nod: $noddies[$i] $noddies[$i+1] $noddies[$i+2] $noddies[$i+3]", $args{'ircChannelCode'}); }
		}
	}
	or modules::display_error($@);
}



# Shows the bhs.dll version of each player ingame
sub scripts
{
	my %args = %{$_[ ARG0 ]};

	# IRC only
	if ( $args{nicktype} != 1 )
		{ return; }

	eval
	{
		if ( modules::get_module("bhs") )
		{
			my @noddies;
			my @gdiguys;

			if ( serverStatus::getCurrentPlayers() == 0 )
			{
				brIRC::ircmsg ( "There are no players ingame at this time.", $args{'ircChannelCode'} );
				return;
			}

			my %playerlist = playerData::getPlayerList();
			while ( my ( $id, $player ) = each ( %playerlist ) )
			{
				my $pname = modules::parseModName ( $player->{'name'}, 1 );

				# Append scripts version to name
				$pname .= " (".sprintf("%.2f", $player->{'scriptsVersion'} ).")";

				# Pad name length to 28 characters
				my $minlength = 28;
				for ( my $i = 1; $i <= $minlength - length($pname); $i++ )
					{ $pname .= " "; }

				push (@noddies, $pname) if ($player->{'side'} eq "NOD" || $player->{'side'} eq "Sov");
				push (@gdiguys, $pname) if ($player->{'side'} eq "GDI" || $player->{'side'} eq "All");

			}

			for ( my $i=0; $i <= scalar(@gdiguys)-1; $i = $i+4 )
			{
				if ( $main::currentMod eq "APB" )
					{ brIRC::ircmsg ( "12Allies: $gdiguys[$i] $gdiguys[$i+1] $gdiguys[$i+2] $gdiguys[$i+3]", $args{'ircChannelCode'} ); }
				else
					{ brIRC::ircmsg ( "08GDI: $gdiguys[$i] $gdiguys[$i+1] $gdiguys[$i+2] $gdiguys[$i+3]", $args{'ircChannelCode'}); }
			}
			for ( my $i = 0; $i <= scalar(@noddies)-1; $i = $i+5 )
			{
				if ( $main::currentMod eq "APB" )
					{ brIRC::ircmsg ( "04Soviet: $noddies[$i] $noddies[$i+1] $noddies[$i+2] $noddies[$i+3]", $args{'ircChannelCode'} ); }
				else
					{ brIRC::ircmsg ( "04Nod: $noddies[$i] $noddies[$i+1] $noddies[$i+2] $noddies[$i+3]", $args{'ircChannelCode'}); }
			}
		}
		else
		{
			brIRC::ircmsg ( "You need to enable module bhs and install the bhs library to use this command.", $args{'ircChannelCode'} );
		}
	}
	or modules::display_error($@);
}

sub setbw
{
	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
	my %args = %{$args};

	eval
	{
		if ( modules::get_module("bhs") )
		{
			if ( $args{arg1} && $args{arg2} && ( $args{arg2} =~ m/^\d+$/ ) )
			{
				my ( $result, %player ) = playerData::getPlayerData( $args{'arg1'} );
				if ( $result == 1 )
				{
					my $bandwidth = $args{arg2};

					RenRem::RenRemCMD( "SETBW $player{id} $bandwidth" );
					modules::pagePlayer ( $player{'id'}, "BRenBot", "Your bandwidth has been set to $bandwidth by $args{nick}." );
					brIRC::ircmsg ( "Setting the bandwidth of $player{name} to $bandwidth..", $args{'ircChannelCode'} );
				}
				else
				{
					brIRC::ircmsg ( "Error: $args{arg1} was not found ingame, or is not unique.", $args{'ircChannelCode'} );
					return
				}
			}
			else
			{
				if ($args{nicktype} == 1)
				{
					my $syntaxvalue = $args{settings}->{syntax}->{value};
					brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
				}
				else
					{ modules::pagePlayer( $args{'nick'}, "BRenBot", "Usage: $args{settings}->{syntax}->{value}" ); }
			}
		}
		else
		{
			brIRC::ircmsg ( "You need to enable module bhs and install the bhs library to use this command.", $args{'ircChannelCode'} );
		}
	}
	or modules::display_error($@);
}

sub getbw
{
	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
	my %args = %{$args};

	my $pname;
	my $pid = 0;
	my $pside;

	eval
	{
		if ( modules::get_module("bhs") )
		{
			if ( $args{'arg1'} )
			{
				my ( $result, %player ) = playerData::getPlayerData($args{'arg1'});
				if ( $result == 1 )
				{
					$pname = $player{'name'};
					$pid   = $player{'id'};
					$pside = $player{'side'};
				}
				else
				{
					if ( $args{nicktype} == 1 )
					{
						brIRC::ircmsg ( "Error: $args{arg1} was not found ingame, or is not unique.", $args{'ircChannelCode'} );
					}
					else
					{
						RenRem::RenRemCMD ( "msg [BR] Error - $args{arg1} was not found ingame, or is not unique." );
					}
					return;
				}
			}

			elsif ( $args{nicktype} != 1 )
			{
				RenRem::RenRemCMD ( "msg [BR] You cannot use !getbw ingame. Please use !getbw <player>" );
				return;
			}

			if ( serverStatus::getCurrentPlayers() == 0 )
			{
				brIRC::ircmsg ( "No Players", $args{'ircChannelCode'} );
				return;
			}

			modules::get_bandwidth($pid);
			my $outputType = ( $args{nicktype} == 1 ) ? 'irc' : 'ingame';

			POE::Session->create
			( inline_states =>
				{
					_start => sub
					{
						$_[HEAP]->{next_alarm_time} = int( time() ) + 2;
						$_[KERNEL]->alarm( tick => $_[HEAP]->{next_alarm_time} => \%args );
						#$_[KERNEL]->alias_set("getbw");

						$_[HEAP]->{name} = $pname;
						$_[HEAP]->{id}   = $pid;
						$_[HEAP]->{side} = $pside;
						$_[HEAP]->{outputType} = $outputType;
					},
					tick => \&showbw
				}
			);
		}
		else
		{
			brIRC::ircmsg ( "You need to enable module bhs and install the bhs library to use this command.", $args{'ircChannelCode'} );
		}
	}
	or modules::display_error($@);
}

sub showbw
{
	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
	my %args = %{$args};

	if ( $heap->{'name'} )		# Name specified, look up their bandwidth
	{
		my ( $result, %player ) = playerData::getPlayerData ( $heap->{'name'} );
		if ( $result == 1 )
		{
			my $id	= $player{'id'};
			my $side  = $player{'side'};

			my $pname = modules::parseModName ( $player{'name'}, 1 );

			if ( $heap->{outputType} eq 'irc' )
			{
				$pname = "04" . $pname . "" if ( $side eq "NOD" || $side eq "Sov" );
				$pname = "08" . $pname . "" if ( $side eq "GDI" );
				$pname = "12" . $pname . "" if ( $side eq "All" );

				brIRC::ircmsg ( "$pname has their bandwidth set to $player{'bandwidth'}", $args{'ircChannelCode'} );
			}
			else
			{
				RenRem::RenRemCMD ( "msg [BR] $pname has their bandwidth set to $player{'bandwidth'}" );
			}
		}
	}
	else					# No name specified, list all players
	{
		brIRC::ircmsg ( "Bandwidth settings:", $args{'ircChannelCode'} );
		my @bwoutput;

		my %playerlist = playerData::getPlayerList();
		while ( my ( $id, $player ) = each ( %playerlist ) )
		{
			my $id	= $player->{'id'};
			my $side  = $player->{'side'};

			my $pname = modules::parseModName ( $player->{'name'}, 1 );
			$pname = "04" . $pname if ( $side eq "NOD" || $side eq "Sov" );
			$pname = "08" . $pname if ( $side eq "GDI" );
			$pname = "12" . $pname if ( $side eq "All" );

			push ( @bwoutput, "$pname: $player->{bandwidth}" );		# Store player in the array
		}

		# Output players in groups of 4 to the IRC
		for ( my $i=0; $i<=scalar(@bwoutput)-1;$ i+=4 )
		{
			brIRC::ircmsg ( "$bwoutput[$i]   $bwoutput[$i+1]   $bwoutput[$i+2]   $bwoutput[$i+3]", $args{'ircChannelCode'} );
		}
	}
}


sub deltempmod
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	eval
	{
		if ( !($args{arg1}) )
		{
			my $syntaxvalue = $args{settings}->{syntax}->{value};

			if ( $args{nicktype} == 1 )
			{
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
				{ modules::pagePlayer( $args{'nick'}, "BRenBot", "Usage: $syntaxvalue" ); }

			return;
		}

#		if ( modules::IsTempMod( $args{nick} ) && $args{nick} != $player{name}
#			&& !modules::IsFullMod( $args{nick} ) && !modules::IsAdmin( $args{nick} ) )
		if ( modules::IsTempMod( $args{nick} ) )
		{
			# Dont let temp admins remove other temp admins
			RenRem::RenRemCMD( "msg [BR] TEMP moderators cannot delete other TEMP moderators." );
		}
		else
		{
			modules::DelTempModerator( $args{arg1} );
		}
	}
	or modules::display_error($@);
}


sub addtempmod
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	eval
	{
		if ( !($args{arg1}) )
		{
			if ( $args{nicktype} == 1 )
			{
				my $syntaxvalue = $args{settings}->{syntax}->{value};
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
				{ modules::pagePlayer( $args{'nick'}, "BRenBot", "Usage: $args{settings}->{syntax}->{value}" ); }
			return;
		}
		# Dont let temp admins give temp admin to others
		if ( modules::IsTempMod ( $args{nick} ) )
		{
			RenRem::RenRemCMD( "msg [BR] TEMP moderators cannot add other TEMP moderators." );
		}
		else
		{
			#print "atm $args{arg1}..\n";
			modules::AddTempModerator ( $args{arg1} );
		}
	}
	or modules::display_error($@);
}

sub gameinfo
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	eval
	{
		#RenRem::RenRemCMD("game_info");
		my ( $serverMode, $currentMap, $gdiPlayers, $gdiPoints, $nodPlayers, $nodPoints, $currentPlayers, $maxPlayers, $timeRemaining, $sfps ) = serverStatus::getGameStatus();

		if (modules::get_module("new_gi") )		# Use new style GI
		{
			if ( $main::currentMod eq "APB" )
				{ brIRC::ircmsg ( "15Gameinfo: (11$serverMode15) 15Map: $currentMap 12Allies: $gdiPlayers/$maxPlayers players  $gdiPoints points 04Soviet: $nodPlayers/$maxPlayers players  $nodPoints points15 $timeRemaining mins left SFPS: $sfps", $args{'ircChannelCode'} ); }
			else
				{ brIRC::ircmsg ( "15Gameinfo: (11$serverMode15) 15Map: $currentMap 08GDI: $gdiPlayers/$maxPlayers players  $gdiPoints points 04Nod: $nodPlayers/$maxPlayers players  $nodPoints points15 $timeRemaining mins left SFPS: $sfps", $args{'ircChannelCode'} ); }
		}
		else
		{
			# Use old style GI
			brIRC::ircmsg ( "      Map : $currentMap", $args{'ircChannelCode'} );
			brIRC::ircmsg ( "     Time : $timeRemaining", $args{'ircChannelCode'} );
			brIRC::ircmsg ( "  Players : $currentPlayers / $maxPlayers", $args{'ircChannelCode'} );
			if ( $main::currentMod eq "APB" )
			{
				brIRC::ircmsg ( "12   Allies : $gdiPlayers players          $gdiPoints points", $args{'ircChannelCode'} );
				brIRC::ircmsg ( "04   Soviet : $nodPlayers players          $nodPoints points", $args{'ircChannelCode'} );
			}
			else
			{
				brIRC::ircmsg ( "08      GDI : $gdiPlayers players          $gdiPoints points", $args{'ircChannelCode'} );
				brIRC::ircmsg ( "04      Nod : $nodPlayers players          $nodPoints points", $args{'ircChannelCode'} );
			}
			brIRC::ircmsg ( "     SFPS : $sfps", $args{'ircChannelCode'} );
		}
	}
	or modules::display_error($@);

}

sub playerinfo
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	eval
	{
		# Setup if we are searching for specific players, either by team, ip or name
		my $searchTeam = 0;			my $team;
		my $searchIP = 0;			my $ip;
		my $searchName = 0;			my $name;

		if ( $args{arg1} )	# Check if we have a search condition specified
		{
			if ( $args{arg1} =~ m/^(Nod|GDI|Sov|All)$/i )	# Check if condition is GDI or Nod
			{
				$searchTeam = 1;
				$team = $1;
			}
			elsif ( $args{arg1} =~ m/^(\d+)\.(\d+)(\.\d+)?(\.\d+)?$/i )	# Check for IP search
			{
				$searchIP = 1;
				$ip = $1 . '.' . $2;
				if ( $3 ) { $ip .= $3 }
				if ( $4 ) { $ip .= $4 }
			}
			else	# Not a team or IP search, so assume we are searching for a username
			{
				$searchName = 1;
				$name = quotemeta ( $args{arg1} );
			}
		}

		# Send player_info command to trigger update of playerlist array
		RenRem::RenRemCMD( "player_info" );

		if ( serverStatus::getCurrentPlayers() == 0 )
		{
			brIRC::ircmsg ( "There are no players ingame at this time.", $args{'ircChannelCode'} );
			return;
		}



		# Loop through the names to find the longest one, and if we have search
		# conditions see if anything matches them
		my %playerlist = playerData::getPlayerList();
		my $longestName = 12;		# Default to 12, otherwise the line will look very short
		my $found = 0;

		# Get longest name, and check for any search conditions matches
		while ( my ( $id, $player ) = each ( %playerlist ) )
		{
			#my %hash	= %{$_};
			my $namelen	= length( $player->{'name'} );

			if ( $namelen > $longestName )
				{ $longestName = $namelen; }

			if ( $searchTeam )
			{
				if ( $player->{'side'} =~ m/^$team$/i ) { $found = 1; }
			}

			elsif ( $searchIP )
			{
				if ( $player->{'ip'} =~ m/$ip/i ) { $found = 1; }
			}

			elsif ( $searchName )
			{
				if ( $player->{'name'} =~ m/$name/i ) { $found = 1; }
			}
		}

		# If we have search conditions and found == 0 then nothing matches the search
		if ( $searchTeam || $searchIP || $searchName )
		{
			if ( $found == 0 )
			{
				brIRC::ircmsg ( "No players were found matching your search criteria.", $args{'ircChannelCode'} );
				return;
			}
		}


		# Ok, if we got to here that means there are players in the list, and they
		# match any search criteria we had. Print out the list.
		my $format = "%-5s %-" . ($longestName +2) . "s %-6s %-5s %-5s %-16s %-5s %-10s";
		my $line = sprintf ( $format, 'Id', 'Name', 'Score', 'Side', 'Ping', 'Address', 'Kb/s', 'Time' );

		# Print out header line
		brIRC::ircmsg ( "01,14 " . $line, $args{'ircChannelCode'} );


		# And finally, loop through the playerlist and output those which match our
		# search conditions, or all of them.
		while ( my ( $id, $player ) = each ( %playerlist ) )
		{
			# Check the line matches any search criteria
			if ( ( $searchTeam == 0 && $searchIP == 0 && $searchName == 0 )
				|| ( $searchTeam && $player->{'side'} =~ m/^$team$/i )
				|| ( $searchIP && $player->{'ip'} =~ m/$ip/i )
				|| ( $searchName && $player->{'name'} =~ m/$name/i ) )
			{
				# Setup bold / underlined text for admins or temp mods
				my $pname = modules::parseModName ( $player->{'name'}, 1 );

				# Output lines using the same format we created earlier
				$line = sprintf( $format, $player->{'id'}, $pname, $player->{'score'}, $player->{'side'}, $player->{'ping'}, $player->{'ip'}, $player->{'kbps'}, $player->{'time'} );

				# Add colouring for teams
				if ( $player->{'side'} =~ /(NOD|Sov)/i ) { $line = "04,14 $line"; }
				if ( $player->{'side'} =~ /GDI/i ) { $line = "08,14 $line"; }
				if ( $player->{'side'} =~ /All/i ) { $line = "12,14 $line"; }

				# Finally output to IRC
				brIRC::ircmsg ( $line, $args{'ircChannelCode'} );

			} # End of searching IF
		} # end of foreach playerlist
	}
	or modules::display_error($@);
} # end of playerinfo


sub players
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	eval
	{
		my @noddies;
		my @gdiguys;
		my @gdi;
		my @nod;

		if ( serverStatus::getCurrentPlayers() == 0 )
		{
			brIRC::ircmsg ( "There are no players ingame at this time.", $args{'ircChannelCode'} );
			return;
		}

		my %playerlist = playerData::getPlayerList();
		while ( my ( $id, $player ) = each ( %playerlist ) )
		{
			#my $pname = $_->{'name'};
			my $side = $player->{'side'};

			my $pname = modules::parseModName ( $player->{'name'}, 1 );

			my $maxlength = 22;
			for (my $i=1;$i<=$maxlength - length($pname);$i++)
			{
				$pname .= " ";
			}
			push (@noddies, $pname) if ($side eq "NOD" || $side eq "Sov");
			push (@gdiguys, $pname) if ($side eq "GDI" || $side eq "All");

		} # end of playerlist
	#		$gdiguys =~ s/ / /g; #replace spaces with alt-255's
	#		$noddies =~ s/ / /g; #replace spaces with alt-255's

		for (my $i=0;$i<=scalar(@gdiguys)-1;$i=$i+5)
		{
			push (@gdi, "$gdiguys[$i] $gdiguys[$i+1] $gdiguys[$i+2] $gdiguys[$i+3] $gdiguys[$i+4]");
		}
		for (my $i=0;$i<=scalar(@noddies)-1;$i=$i+5)
		{
			push (@nod, "$noddies[$i] $noddies[$i+1] $noddies[$i+2] $noddies[$i+3] $noddies[$i+4]");
		}

		foreach (@gdi)
		{
			if ( $main::currentMod eq "APB" )
			{ brIRC::ircmsg ( "12Allies: $_", $args{'ircChannelCode'} ); }
			else
			{ brIRC::ircmsg ( "08GDI: $_", $args{'ircChannelCode'}); }
		}
		foreach (@nod)
		{
			if ( $main::currentMod eq "APB" )
			{ brIRC::ircmsg ( "04Soviet: $_", $args{'ircChannelCode'} ); }
			else
			{ brIRC::ircmsg ( "04Nod: $_", $args{'ircChannelCode'} ); }
		}
		return;
	}
	or modules::display_error($@);

}


sub letmein
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my %args = %{$args};
	my $kernel = $_[KERNEL];

	eval
	{
		if ($brconfig::config_reserved == 1)
		{
			my $gdi_players = serverStatus::getPlayers_GDI();
			my $nod_players = serverStatus::getPlayers_Nod();
			my $max_players = serverStatus::getMaxPlayers();

			if ( ( $gdi_players + $nod_players ) < ( $max_players - $brconfig::config_reserved_slots) )
			{
				my $slots = ( $max_players - $brconfig::config_reserved_slots) - ( $gdi_players + $nod_players );
				brIRC::ircmsg ( "There are $slots more open slots available. No need for !letmein.", $args{'ircChannelCode'} );
				undef $slots;
				return;
			}


			if ( ( $gdi_players + $nod_players ) >= $max_players )
			{
				my $num_players = ( $gdi_players + $nod_players );
				brIRC::ircmsg ( "There are already $num_players out of $max_players players. Limit has been reached.", $args{'ircChannelCode'} );
				undef $num_players;
				return;
			}
			if ( $renlog::used_slots > $brconfig::config_reserved_slots )
			{
				brIRC::ircmsg ( "There are already $brconfig::config_reserved_slots Slots open.", $args{'ircChannelCode'} );
				return;
			}
			else
			{
				$renlog::used_slots++;
				brIRC::ircmsg ( "One additional Slot has been opened. You need to join NOW to reclaim your opened slot!!", $args{'ircChannelCode'} );
			}

			undef $gdi_players;
			undef $nod_players;
			undef $max_players;
		}
		else
		{
			brIRC::ircmsg ( "Reserved slots are disabled.", $args{'ircChannelCode'} );
		}
	 }
	 or modules::display_error($@);
}


sub restart
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	eval
	{
		RenRem::RenRemCMD("msg [BR] Server RESTART initiated by admin.");
		RenRem::RenRemCMD("restart");
		return;
	}
	or modules::display_error($@);
}

sub shutdown
{
	eval
	{
		RenRem::RenRemCMD( "msg [BR] Server SHUTDOWN initiated by admin." );
		RenRem::RenRemCMD( "quit" );
		return;
	}
}


# Restarts BRenBot using restart.exe, only compatible with windows
sub reboot
{

	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	eval
	{
		my $arg = $args{arg};

		if (!($arg eq "!reboot NOW"))
		{
			if ( $args{nicktype} != 1 )
			{
				RenRem::RenRemCMD( "msg Usage: !reboot NOW -CASE SENSITIVE! TO AVOID ACCIDENTAL TRIGGERING" );
			}
			else
			{
				brIRC::ircmsg ( "Usage: !reboot NOW -CASE SENSITIVE! TO AVOID ACCIDENTAL TRIGGERING", $args{'ircChannelCode'} );
			}
		}
		elsif ( $brconfig::config_botmode ne "WIN32" )
		{
			if ( $args{nicktype} != 1 )
			{
				RenRem::RenRemCMD( "msg Sorry, The reboot command is only available on Win32 servers." );
			}
			else
			{
				brIRC::ircmsg ( "Sorry, The reboot command is only available on Win32 servers.", $args{'ircChannelCode'} );
			}
		}
		else
		{
			my @args;
			@args = ( "restart.exe" );
			system(@args) == 0 or CORE::die "system '@args' failed: $?";
			exit(0);
		}
	}
	or modules::display_error($@);
}


sub minelimit
{
	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
	my %args = %{$args};

	eval
	{
		if (modules::get_module("bhs") )
		{
			if ( $args{arg1} =~ m/^\d+$/ &&
				( ( $args{'nicktype'} == 0 && ( modules::IsHalfMod( $args{'nick'} ) || modules::IsFullMod($args{'nick'} ) || modules::IsAdmin ( $args{'nick'} ) ) )
				|| ( $args{'nicktype'} == 1 && brIRC::getUserPermissions ( $args{'nick'} ) ne 'irc_normal' && brIRC::getUserPermissions ( $args{'nick'} ) ne 'irc_voice' ) ) )
			{
				$modules::minelimit = $args{arg1};
				RenRem::RenRemCMD ( "mlimit $args{arg1}" );
				RenRem::RenRemCMD( "msg [BR] The mine limit has been set to ".$modules::minelimit." mines." );
			}
			else
			{
				RenRem::RenRemCMD( "msg [BR] The mine limit for ".serverStatus::getMap()." is ".$modules::minelimit." mines." );
			}
		}
		else
		{
			RenRem::RenRemCMD( "msg [BR] Configurable mine limits are not available on this server." );
		}
		return;
	}
	or modules::display_error($@);
}

sub vehiclelimit
{
	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
	my %args = %{$args};

	eval
	{
		if ( modules::get_module("bhs") )
		{
			if ( $args{arg1} =~ m/^\d+$/ &&
				( ( $args{'nicktype'} == 0 && ( modules::IsHalfMod( $args{'nick'} ) || modules::IsFullMod($args{'nick'} ) || modules::IsAdmin ( $args{'nick'} ) ) )
				|| ( $args{'nicktype'} == 1 && brIRC::getUserPermissions ( $args{'nick'} ) ne 'irc_normal' && brIRC::getUserPermissions ( $args{'nick'} ) ne 'irc_voice' ) ) )
			{
				$modules::vehiclelimit = $args{arg1};
				RenRem::RenRemCMD ( "vlimit $$args{arg1}" );
				RenRem::RenRemCMD( "msg [BR] The vehicle limit has been set to ".$modules::vehiclelimit." vehicles." );
			}
			else
			{
				RenRem::RenRemCMD( "msg [BR] The vehicle limit for ".serverStatus::getMap()." is ".$modules::vehiclelimit." vehicles." );
			}
		}
		else
		{
			RenRem::RenRemCMD( "msg [BR] Configurable vehicle limits are not available on this server." );
		}
		return;
	}
	or modules::display_error($@);
}


# Function for the !gameover command
sub gameover
{
	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
	my %args = %{$args};

	eval
	{
		if ( $args{'arg'} eq "!gameover NOW" )
		{
			RenRem::RenRemCMD( "gameover" );
			brIRC::ircmsg ( "GameOver CMD Sent.", "A" );
		}
		else
		{
			if ( $args{'nicktype'} == 1 ) { brIRC::ircmsg ( "Usage: !gameover NOW     - CASE SENSITIVE to avoid accidental triggering.", $args{'ircChannelCode'} ); }
			else { RenRem::RenRemCMD( "msg Usage: !gameover NOW     - CASE SENSITIVE to avoid accidental triggering." ); }
		}
	}
}



# Function for the !kick and !qkick commands
sub kick
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		if ( $args{'arg'} =~ m/^\!\S+\s(\S*)\s*(.*)/i )
		{
			my $target = $1;
			my $reason = $2;
			my $temporary_ban = ($args{'command'} eq "kick") ? 1 : 0;

			# Check they have entered a person to kick and the reason for kicking them
		   if ( !$reason || !$target )
		   {
				my $syntaxvalue = $args{settings}->{syntax}->{value};

				if ( $args{'nicktype'} == 1 ) { brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} ); }
				else { modules::pagePlayer ( $args{'nick'}, "BRenBot", "Usage: $syntaxvalue" ); }
				return;
			}


			# Get player details (Works for both ID and name). Return if they are not found.
			my ( $result, %player ) = playerData::getPlayerData ( $target );
			if ( $result != 1 )
			{
				if ( $args{'nicktype'} == 1 ) { brIRC::ircmsg ( "KICK ERROR: $target was not found ingame, or is not unique.", $args{'ircChannelCode'} ); }
				else { RenRem::RenRemCMD ( "msg [BR] KICK ERROR: $target was not found ingame, or is not unique." ); }
				return;
			}


			# Otherwise proceed to kick them from the server
			modules::kick_player ( $player{'id'}, $args{'nick'}, $reason, $temporary_ban );

		}
	}# End of eval
	or modules::display_error($@);
} # End of kick function





# Function for the !fds command - sends commands directly to the server
sub fds
{
	my %args = %{$_[ ARG0 ]};

	if ( $args{arg1} )
	{
		$args{arg} =~ m/\!fds\s(.+)/i;
		my $message = substr ( $1, 0, 228 );		# Limit length to prevent crashing the FDS
		RenRem::RenRemCMD ( $message );
	}
}


# !shun prevents the specified player using any BR commands
sub shun
{
	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
	my %args = %{$args};

	eval
	{
		my $message;
		if ( $args{arg1} )
		{
			my ( $result, %player ) = playerData::getPlayerData( $args{arg1} );
			if ( $result == 1 )
			{
				my $name = lc( $player{name} );		# Use lower case names
				#if ( $main::shunnedPlayers{$name} )
				if ( playerData::getKeyValue ( $name, "isShunned" ) )
				{
					$message = "$player{name} is already shunned.";
				}
				else
				{
					if ( modules::IsHalfMod($player{name}) || modules::IsFullMod($player{name}) || modules::IsAdmin($player{name}) )
					{
						$message = "You may not shun server administators or permanent moderators";
					}
					elsif ( modules::IsTempMod($player{name}) && modules::IsTempMod($args{nick}) )
					{
						$message = "Temporary moderators may not shun other temporary moderators!";
					}
					else
					{
						#$main::shunnedPlayers{$name} = 1;
						playerData::setKeyValue ( $name, "isShunned", 1 );
						RenRem::RenRemCMD( "msg [BR] $player{name} has been shunned by $args{nick}, and will not be allowed to use any of BRenBots commands." );

						# Write the shunning to the logs table
						brdatabase::writeLog ( 3, "[MISC] $player{name} was shunned by $args{nick}." );

						return;
					}
				}
			}
			elsif ( $result == 2 )
			{
				$message = "$args{arg1} is not unique, please be more specific.";
			}
			else
			{
				$message = "$args{arg1} was not found in the game.";
			}
		}
		else
		{
			my $syntaxvalue = $args{settings}->{syntax}->{value};
			$message = "[BR] Usage: $syntaxvalue";
		}

		if ( $message )
		{
			if ( $args{nicktype} == 1 )
				{ brIRC::ircmsg ( $message, $args{'ircChannelCode'} ); }
			else
				{ modules::pagePlayer( $args{'nick'}, "BRenBot", "$message" ); }
		}
	}	# End of eval
	or modules::display_error($@);
}


# !unshun allows the specified player to use BR commands again
sub unshun
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	eval
	{
		my $message;
		if ( $args{arg1} )
		{
			my ( $result, %player ) = playerData::getPlayerData( $args{arg1} );
			if ( $result == 1 )
			{
				my $name = lc( $player{name} );		# Use lower case names
				#if ( $main::shunnedPlayers{$name} )
				if ( playerData::getKeyValue ( $name, "isShunned" ) )
				{
					#delete $main::shunnedPlayers{$name};
					playerData::setKeyValue ( $name, "isShunned", 0 );
					RenRem::RenRemCMD( "msg [BR] $player{name} has been unshunned by $args{nick}, and can now use BRenBots commands normally again." );
					return;
				}
				else
				{
					$message = "$player{name} was not shunned to begin with...";
				}
			}
			elsif ( $result == 2 )
			{
				$message = "$args{arg1} is not unique, please be more specific.";
			}
			else
			{
				$message = "$args{arg1} was not found in the game.";
			}
		}
		else
		{
			my $syntaxvalue = $args{settings}->{syntax}->{value};
			$message = "Usage: $syntaxvalue";
		}

		if ( $args{nicktype} == 1 )
		{
			brIRC::ircmsg ( $message, $args{'ircChannelCode'} );
		}
		else
		{
			modules::pagePlayer( $args{'nick'}, "BRenBot", $message );
		}
	}	# End of eval
	or modules::display_error($@);
}




## dumpLogs command
sub dumpLogs
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	brdatabase::dumpLogs ( 1, $brconfig::config_kicklogfile );
	brdatabase::dumpLogs ( 2, $brconfig::config_banlogfile );
	brdatabase::dumpLogs ( 3, $brconfig::config_misclogfile );

	brIRC::ircmsg ( "Log dump complete.", $args{'ircChannelCode'} );
}


###################################################
####
## Functions related to the voting system
####
###################################################

# Used to enable and disable voting, and can also be used to stop votes in progress
sub voting
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	eval
	{
		# Check syntax first...
		if ($args{arg} =~ /^\!voting\s(on|off|stop)/i)
		{
			my $vcmd=$1;

			if ($vcmd =~ /off/i)			# Disabling voting
			{
				$brconfig::config_votingenabled=0;
				RenRem::RenRemCMD( "msg [BR] Voting has been temporarily DISABLED by the administration.");
				return;
			}
			elsif ($vcmd =~ /on/i)			# Enable voting
			{
				$brconfig::config_votingenabled=1;
				RenRem::RenRemCMD( "msg [BR] Voting has been re-ENABLED by the administration.");
				return;
			}
			elsif ($vcmd =~ /stop/i)		# Stop votes in progress
			{

				if ( $voteinprogress == 1 )
				{
					RenRem::RenRemCMD( "msg [BR] Stopping vote in progress." );
					$kernel->post( "voteThread" => "cancel" );
					$voteinprogress = 0;
				}
				elsif ( $teamsinprogress == 1 )
				{
					RenRem::RenRemCMD("msg [BR] Stopping team regulator..");
					$kernel->post( "teams" => "cancel" );
					$teamsinprogress = 0;
				}
		 		else
				{
					brIRC::ircmsg ( "Nothing to stop.", $args{'ircChannelCode'} );
				}
	 		}
		}
		else
		{
			my $syntaxvalue = $args{settings}->{syntax}->{value};

			if ($args{nicktype} == 1)
			{
				brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
			}
			else
				{ modules::pagePlayer( $args{'nick'}, "BRenBot", "Usage: $syntaxvalue" ); }

			return;
		}
	} # End of eval
	or modules::display_error($@);
} # End of voting




# Stops any running votes
sub stop
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	if ($voteinprogress == 1)
	{
		RenRem::RenRemCMD ("msg [BR] Stopping vote in progress..");

		$kernel->post("voteThread" => "cancel");
		$voteinprogress = 0;
	}
	elsif ($teamsinprogress == 1)
	{
		RenRem::RenRemCMD ("msg [BR] Stopping team regulator..");

		$kernel->post("teams" => "cancel");
		$teamsinprogress = 0;
	}
	else
	{
		if ($args{nicktype} == 1)
		{
			brIRC::ircmsg ( "Nothing to stop.", $args{'ircChannelCode'} );
		}
		else
		{
			RenRem::RenRemCMD ("msg [BR] Nothing to stop.");
		}
	}
} # End of stop




# Function for the !vote command, starts a new vote.
sub vote
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	eval
	{
		# First check the syntax
		if ( !$args{arg1} )
		{
			my $syntaxvalue = $args{settings}->{syntax}->{value};

			if ( $args{nicktype} == 1 )
				{ brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} ); }
			else
				{ modules::pagePlayer( $args{'nick'}, "BRenBot", "Usage: $syntaxvalue" ); }
			return;
		}

		# Now check that voting is enabled
		if ( $brconfig::config_votingenabled eq "0" )
		{
			RenRem::RenRemCMD( "msg [BR] Sorry, Voting has been temporarily disabled by the administration.");
			return;
		}

		# Check they are not trying to use the voting system from IRC
		if ($args{nicktype} eq 1)
		{
			brIRC::ircmsg ( "Voting is for ingame users only.", $args{'ircChannelCode'} );
			return;
		}


		# Are we trying to start a new vote?
		my $vote = lc ( $args{arg1} );
		if ( $vote eq "kick" || $vote eq "map" || $vote eq "nextmap"
			|| $vote eq "cyclemap" || $vote eq "gameover" )
		{
			# Is there already a vote running?
			if ( $voteinprogress == 1 )
			{
				RenRem::RenRemCMD( "msg [BR] Only 1 vote is allowed at a time.  Please wait for the current voting period to end." );
				return;
			}

			# Start the new vote
			startVote(\%args)
		}


		elsif ($args{arg} =~ /^\!vote\s(yes|no|y|n)/i)
		{
			# Vote yes or no
			if ( !$voteinprogress )
			{
				RenRem::RenRemCMD("msg [BR] Error: A vote is not in progress!");
				return;
			}

			if ( !AlreadyVoted($args{nick}) )
			{
				my $vote=$1;
				if ($vote =~ /y(es)?/i) {CastVote(1, $args{nick})}
				if ($vote =~ /n(o)?/i)  {CastVote(0, $args{nick})}
				return;
			}
			#$kernel->post( IRC => privmsg => CHANNEL, "Duplicate Vote Cast by $args{nick}...discarding.");
			RenRem::RenRemCMD( "msg [BR] Vote Error: $args{nick}, you are not allowed to vote multiple times!" );
		}
	} # End of eval
	or modules::display_error($@);
} # End of vote




# Starts a new vote. Vote types are as follows;
#
# 1 = Change the next map
# 2 = Kick a player
# 3 = Switch to the next map
#
sub startVote
{
	my %args = %{$_[0]};
	$args{arg1} = lc ( $args{arg1} );
	my $voteType;
	my %voteHeap;

	# Pre-process map votes
	if ( $args{'arg1'} eq "map" || $args{'arg1'} eq "nextmap" )
	{
		$voteType = 1;

		# Check this type of vote is allowed
		if ( $brconfig::config_voting_allow_nextmap != 1 )
		{
			RenRem::RenRemCMD( "msg [BR] Voting to change the nextmap has been disabled." );
			return;
		}

		# Check the next map has been specified
		if ( !$args{'arg2'} )
		{
			RenRem::RenRemCMD( "msg [BR] Vote Map Error: You must specify the map to vote for. Vote Map Syntax: !vote map mapname" );
			return;
		}

		# Now check the map exists in the data folder
		my ($result, $vote_mapname) = modules::FindInstalledMap( $args{'arg2'} );

		if ( $result == 2 )
		{
			RenRem::RenRemCMD( "msg [BR] Vote Map Error: $args{arg2} is not unique, please be more specific." );
			return;
		}
		elsif ( $result == 0 )
		{
			RenRem::RenRemCMD( "msg [BR] Vote Map Error: $args{arg2} was not found in the servers data folder." );
			return;
		}

		# If neither of the two checks stopped the sub, the map must be ok to use
		$voteHeap{'map'} = $vote_mapname;
		RenRem::RenRemCMD ( "msg [BR] $args{nick} has initiated a vote to change the next map to $vote_mapname. You have " . $brconfig::config_votingperiod . " seconds to vote using !vote yes or !vote no." );
	}


	# Pre-process kick votes
	elsif ( $args{arg1} eq "kick" )
	{
		$voteType = 2;

		# Check this type of vote is allowed
		if ( $brconfig::config_voting_allow_kick != 1 )
		{
			RenRem::RenRemCMD( "msg [BR] Voting to kick another player has been disabled." );
			return;
		}

		# Check they have specified who to kick and why
		if ( !$args{arg2} )
		{
			RenRem::RenRemCMD( "msg [BR] You must specify the player to vote-kick, and give a reason. Vote Kick Syntax: !vote kick playername reason" );
			return;
		}

		# Check the target of the vote is in the game..
		my ( $result, %player ) = playerData::getPlayerData( $args{arg2} );
		if ( $result == 2 )
		{
			RenRem::RenRemCMD( "msg [BR] Error: $args{arg2} is not unique, please be more specific!" );
			return;
		}
		elsif ( $result != 1 )
		{
			RenRem::RenRemCMD( "msg [BR] Error: $args{arg2} was not found in the game!" );
			return;
		}

		# If neither of the two checks stopped the sub, the playername must have been found
		$voteHeap{'kick_target'} = $player{'name'};
		$args{arg} =~ m/^\!vote\skick\s\S+\s(.+)/i;
		$voteHeap{'kick_reason'} = $1;

		# Check they are not trying to kick a moderator or administator
		if ( ( modules::IsHalfMod($player{'name'} ) ) || ( modules::IsFullMod($player{'name'} ) ) || ( modules::IsAdmin($player{'name'} ) ) )
		{
			RenRem::RenRemCMD( "msg [BR] $args{nick} tried to vote-kick a server moderator or administator. They are now the target of the vote." );
			$voteHeap{'kick_target'} = $args{'nick'};
			$voteHeap{'kick_reason'} = "trying To VOTE-KICK a server moderator or server administator.";
			$args{'nick'} = "BRenBot";
		}
		# Check a temp mod is not trying to vote-kick another temp mod
		elsif ( ( modules::IsTempMod( $args{'nick'} ) ) && ( modules::IsTempMod( $player{'name'} ) ) )
		{
			RenRem::RenRemCMD( "msg [BR] $args{nick} tried to vote-kick another Temporary Moderator. They are now the target of the vote." );
			$voteHeap{'kick_target'} = $args{'nick'};
			$voteHeap{'kick_reason'} = "trying to VOTE-KICK another Temporary Moderator";
			$args{'nick'} = "BRenBot";
		}

		RenRem::RenRemCMD ( "msg [BR] $args{nick} has initiated a vote to kick $voteHeap{kick_target} for $voteHeap{kick_reason}. You have " . $brconfig::config_votingperiod . " seconds to vote using !vote yes or !vote no." );
	}


	# Pre-process cyclemap votes
	elsif ( $args{arg1} eq "cyclemap" || $args{arg1} eq "gameover" )
	{
		$voteType = 3;

		# Check this type of vote is allowed
		if ( $brconfig::config_voting_allow_gameover != 1 )
		{
			RenRem::RenRemCMD( "msg [BR] Voting to end the current map has been disabled." );
			return;
		}

		RenRem::RenRemCMD ( "msg [BR] $args{nick} has initiated a vote to change to the next map. You have " . $brconfig::config_votingperiod . " seconds to vote using !vote yes or !vote no." );
	}




	# Ok, pre-processing is done, lets get the main heap data for votes and set off
	# the vote thread.
	$voteHeap{'votestarter'} = $args{nick};
	$voteinprogress = 1;
	%voters = ();

	POE::Session->create
	( inline_states =>
		{
			_start => sub
			{
				$_[HEAP]->{next_alarm_time} = int( time() ) + ($brconfig::config_votingperiod /2);
				$_[KERNEL]->alarm( tick1 => $_[HEAP]->{next_alarm_time} );
				$_[KERNEL]->alias_set( "voteThread" );

				$_[HEAP]->{voteHeap} = \%voteHeap;
				$_[HEAP]->{voteType} = $voteType;

				modules::console_output ( "Vote thread has started." );
			},
			tick1 => sub
			{
				$_[HEAP]->{next_alarm_time} = int( time() ) + ($brconfig::config_votingperiod /2);
				$_[KERNEL]->alarm( tick2 => $_[HEAP]->{next_alarm_time} );

				my $message;
				my $voteHeap = %{$_[HEAP]->{voteHeap}};

				if ( $_[HEAP]->{voteType} == 1 )
				{ $message = " change the next map to $voteHeap{map}"; }
				elsif ( $_[HEAP]->{voteType} == 2 )
				{ $message = " kick $voteHeap{kick_target} for $voteHeap{kick_reason}"; }
				elsif ( $_[HEAP]->{voteType} == 3 )
				{ $message = " change to the next map in the rotation"; }

				RenRem::RenRemCMD ( "msg [BR] A vote is in progress to $message. You have " . ($brconfig::config_votingperiod /2) . " seconds left to vote using !vote yes and !vote no." );
			},
			tick2 => \&endVote,
			cancel => sub
			{
				$_[KERNEL]->alarm( tick => undef );
				$_[KERNEL]->alarm( tick2 => undef );
				$_[KERNEL]->alias_remove( "voteThread" );
				modules::console_output ( "Vote cancelled!" );
			},
			clearAlias => sub
			{
				$_[KERNEL]->alias_remove( "voteThread" );
			},
			_stop => sub
			{
				modules::console_output ( "Vote thread has terminated." );
			}
		}
	);
} # End of startVote




# Votes which have finished load this subroutine
sub endVote
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %voteHeap = %{$heap->{voteHeap}};

	# First thing we should do is clear the alias for the
	# vote thread so that it can close properly.
	$kernel->post( "voteThread" => "clearAlias" );

	my $gdi_yes_votes = ( $voters{'GDI_yes'} ) ? $voters{'GDI_yes'} : 0;
	my $gdi_no_votes = ( $voters{'GDI_no'} ) ? $voters{'GDI_no'} : 0;
	my $nod_yes_votes = ( $voters{'NOD_yes'} ) ? $voters{'NOD_yes'} : 0;
	my $nod_no_votes = ( $voters{'NOD_no'} ) ? $voters{'NOD_no'} : 0;

	RenRem::RenRemCMD ( "msg [BR] Voting period over, tallying votes...   GDI; $gdi_yes_votes Yes, $gdi_no_votes No   Nod; $nod_yes_votes Yes, $nod_no_votes No" );

	my $totalVoters = $gdi_yes_votes + $gdi_no_votes + $nod_yes_votes + $nod_no_votes;
	my $totalPlayers = serverStatus::getCurrentPlayers();

	if ( $totalVoters < ( $totalPlayers / 3 ) )
	{
		RenRem::RenRemCMD ( "msg [BR] Only $totalVoters out of $totalPlayers voted, at least a third of players must vote for the vote to pass. VOTE FAILED." );
	}

	elsif ( ( $gdi_yes_votes + $nod_yes_votes ) <= ( $gdi_no_votes + $nod_no_votes ) )
	{
		RenRem::RenRemCMD ( "msg [BR] More no votes than yes votes. VOTE FAILED." );
	}

	else
	{
		RenRem::RenRemCMD ( "msg [BR] More yes votes than no votes. VOTE PASSED." );


		# Vote nextmap
		if ( $heap->{voteType} == 1 )
		{
			my ($result,$mapname) = modules::SetNextMap($voteHeap{'map'});
			if ( $result != 1 )
			{
				RenRem::RenRemCMD ( "msg [BR] Error setting next map to $voteHeap{map}." );
			}
			else
			{
				RenRem::RenRemCMD( "msg [BR] Setting next map to $mapname." );
			}
		}


		# Vote kick
		elsif ( $heap->{voteType} == 2 )
		{
			my ( $result, %player ) = playerData::getPlayerData( $voteHeap{'kick_target'} );
			if ( $result == 1 )
			{
				my $ip = $player{'ip'};
				my $id = $player{'id'};

				modules::kick_player ( $id, 'Server Vote (started by '.$voteHeap{'votestarter'}.')', $voteHeap{'kick_reason'} );
			}
			else
			{
				RenRem::RenRemCMD( "msg [BR] $voteHeap{kick_target} ran away from the server before the vote ended..." );
			}
		}


		# Vote cyclemap / gameover
		elsif ( $heap->{voteType} == 3 )
		{
			RenRem::RenRemCMD( "msg [BR] Switching to next map in rotation in 3 seconds." );
			RenRem::RenRemCMDtimed( "gameover", 3 );
		}
	}


	# And finally clear the voteinprogress flag so new votes can be started.
	$voteinprogress = 0;
	%voters = ();
}




# When a user votes yes or no it gets passed here
sub CastVote
{
	my $vote	= shift;
	my $voter	= shift;

	$voters{$voter} = $vote;

	# Get hash of voter so we can check their team
	my ( $result, %player ) = playerData::getPlayerData ( $voter );
	if ( $result == 1 )
	{
		my $voteText = ( $vote == 1 ) ? 'yes' : 'no';
		$voters{"$player{'side'}_$voteText"}++;				# EG gdi_yes, nod_no
	}
}




# Returns 1 if the user has already voted, 0 otherwise
sub AlreadyVoted
{
	my $voter	= shift;

	if ( defined ( $voters{$voter} ) )
	{
		return 1;
	}
	return 0;
}





###################################################
####
## Recommendation functions
####
###################################################

# Function for the !recommand command - Recommend another player for any reason
sub recommend
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		# Prevent this command being used from IRC...
		if ( $args{nicktype} == 1 )
		{
			brIRC::ircmsg ( "This command cannot be used from IRC.", $args{'ircChannelCode'} );
			return;
		}

		# Check recommendations are enabled
		if ( !modules::get_module( "recommend" ) )
		{
			modules::pagePlayer( $args{'nick'}, 'BRenBot', "Recommendations have been disabled by the Administration." );
			return;
		}

		# Check if this user is rec ignored
		if ( modules::is_rec_ignored ( $args{'nick'} ) == 1 )
		{
			modules::pagePlayer( $args{'nick'}, 'BRenBot', "Sorry, Recommendations have been disabled for you by the Administration." );
			return;
		}

		# Check syntax
		if ( ($args{arg} =~ /^\!\S+\s(.+?)\s(.+)/i) )
		{
			my $target = $1;
			my $reason = $2;

			my ( $result, %player ) = playerData::getPlayerData ( $target );
			if ( $result == 1 )
			{
				if ( $player{'name'} eq $args{'nick'} )
				{
					modules::pagePlayer( $args{'nick'}, 'BRenBot', "You can\'t recommend yourself.");
					return;
				}

				my $can_recommend = modules::can_recommend ( $args{'nick'}, $player{'name'}, 0 );
				if ( $can_recommend == 1 )
				{
					modules::recommend_player( $player{'name'}, $args{'nick'}, $reason );
				}
				elsif ( $can_recommend == 2 )
				{
					modules::pagePlayer( $args{'nick'}, 'BRenBot', "You have reached your daily limits for this command." );
				}
				else
				{
					modules::pagePlayer( $args{'nick'}, 'BRenBot', "You have already recommended $player{'name'} today." );
				}
			}
			else
			{
		 		modules::pagePlayer( $args{'nick'}, 'BRenBot', "Player $target was not found ingame, or is not unique." );
			}
		}

		# Bad syntax
		else
		{
			my $syntaxvalue = $args{settings}->{syntax}->{value};
			modules::pagePlayer( $args{'nick'}, 'BRenBot', "Usage: $syntaxvalue" );
			return;
		}
	}
	or modules::display_error($@);
}


# Function for the !n00b command - n00b another player for any reason
sub n00b
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		# Prevent this command being used from IRC...
		if ( $args{nicktype} == 1 )
		{
			brIRC::ircmsg ( "This command cannot be used from IRC.", $args{'ircChannelCode'} );
			return;
		}

		# Check recommendations are enabled
		if ( !modules::get_module( "recommend" ) )
		{
			modules::pagePlayer( $args{'nick'}, 'BRenBot', "Recommendations have been disabled by the Administration." );
			return;
		}

		# Check if this user is rec ignored
		if ( modules::is_rec_ignored ( $args{'nick'} ) == 1 )
		{
			modules::pagePlayer( $args{'nick'}, 'BRenBot', "Sorry, Recommendations have been disabled for you by the Administration." );
			return;
		}

		# Check syntax
		if ( ($args{arg} =~ /^\!\S+\s(\S+)\s(.+)/i) )
		{
			my $target = $1;
			my $reason = $2;

			my ( $result, %player ) = playerData::getPlayerData ( $target );
			if ( $result == 1 )
			{
				if ( $player{'name'} eq $args{nick} )
				{
					modules::pagePlayer( $args{'nick'}, 'BRenBot', "n00bing yourself? Well, if your sure... n00b!." );
				}

				my $can_n00b = modules::can_recommend( $args{'nick'}, $player{'name'}, 1 );
				if ( $can_n00b == 1 )
				{
					modules::n00b_player( $player{'name'}, $args{'nick'}, $reason );
				}
				elsif ( $can_n00b == 2)
				{
					modules::pagePlayer( $args{'nick'}, 'BRenBot', "You have reached your daily limits for this command.");
				}
				else
				{
					modules::pagePlayer( $args{'nick'}, 'BRenBot', "You have already n00bed $player{'name'} today.");
				}
			}
			else
			{
		 		modules::pagePlayer( $args{'nick'}, 'BRenBot', "Player $target was not found ingame, or is not unique." );
			}
		}

		# Bad syntax
		else
		{
			my $syntaxvalue = $args{settings}->{syntax}->{value};
			modules::pagePlayer( $args{'nick'}, 'BRenBot', "Usage: $syntaxvalue" );
			return;
		}
	}
	or modules::display_error($@);
}


# Function for the !recommendations command (!recs)
sub recommendations
{
	my %args = %{$_[ ARG0 ]};

	# Check they are not trying to use this command from IRC
	if ( $args{'nicktype'} eq '1' )
	{
		brIRC::ircmsg ( "The !recommendations command can only be used from ingame.", $args{'ircChannelCode'} );
		return;
	}

	if ( !modules::get_module( "recommend" ) )
	{
		RenRem::RenRemCMD( "msg [BR] Recommendations have been disabled by the Administration." );
		return;
	}

	# Get recommendations and n00bs for $args{nick}
	my $recommendations = modules::get_recommendation ( $args{'nick'} );
	my $n00bs = modules::get_n00b ( $args{'nick'} );

	modules::pagePlayer ( $args{'nick'}, "BRenBot", "You currently have ".($recommendations-$n00bs)." recommendations. ( $recommendations recs, $n00bs n00bs )" );
}


# Function for the !recallow command
sub recallow
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		if (!$args{arg1})
		{
			my $syntaxvalue = $args{settings}->{syntax}->{value};

			if ( $args{'nicktype'} == 1 ) { brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} ); }
			else { RenRem::RenRemCMD( "msg [BR] Usage: $syntaxvalue" ); }
			return;
		}

		my ( $result, %player ) = playerData::getPlayerData( $args{'arg1'} );
		if ( $result == 1 )
		{
			RenRem::RenRemCMD( "msg [BR] Recommendations have been enabled for $player{name}." );
			modules::rec_allow( $player{'name'} );
		}
		else
		{
			if ( $args{'nicktype'} == 1 ) { brIRC::ircmsg ( "$args{arg1} is not ingame, or the name is not unique.", $args{'ircChannelCode'} ); }
			else { RenRem::RenRemCMD( "msg [BR] $args{arg1} is not ingame, or the name is not unique." ); }

			# Write the rec-allow to the logs table
			brdatabase::writeLog ( 3, "[MISC] $player{name} was rec allowed by $args{nick}." );
		}
	}	# End eval
	or modules::display_error($@);
}


# Function for the !recignore command
sub recignore
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		if (!$args{arg1})
		{
			my $syntaxvalue = $args{settings}->{syntax}->{value};

			if ( $args{'nicktype'} == 1 ) { brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} ); }
			else { RenRem::RenRemCMD( "msg [BR] Usage: $syntaxvalue" ); }
			return;
		}

		my ( $result, %player ) = playerData::getPlayerData( $args{'arg1'} );
		if ( $result == 1 )
		{
			RenRem::RenRemCMD("msg [BR] Recommendations have been disabled for $player{name}.");
			modules::rec_ignore( $player{'name'} );

			# Write the rec-ignore to the logs table
			brdatabase::writeLog ( 3, "[MISC] $player{name} was rec ignored by $args{nick}." );
		}
		else
		{
			if ( $args{'nicktype'} == 1 ) { brIRC::ircmsg ( "$args{arg1} is not ingame, or the name is not unique.", $args{'ircChannelCode'} ); }
			else { RenRem::RenRemCMD( "msg [BR] $args{arg1} is not ingame, or the name is not unique." ); }
		}
	}
	or modules::display_error($@);
}


# Function for the !teamplayers / !shown00bs command
my $tpLastUsed = 0;			# Global variable used to track last used time
sub teamplayers
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		# Any players ingame?
		if ( serverStatus::getCurrentPlayers() == 0 ) {
			brIRC::ircmsg ( "No Players", $args{'ircChannelCode'} );
			return;
		}


		# Too recently used?
		if ( time() - $tpLastUsed < 120 )
		{
			if ( $args{'nicktype'} == 1 ) { brIRC::ircmsg ( "The !teamplayers/!shown00bs commands can only be used once every 2 minutes!" ); }
			else { RenRem::RenRemCMD ( "msg [BR] The !teamplayers/!shown00bs command can only be used once every 2 minutes! Use !recs to see your own recommendations." ); }
			return;
		}
		else { $tpLastUsed = time(); }


		# Create data arrays
		my @gdiPlayers;
		my @nodPlayers;


		# Loop through each player
		my %playerlist = playerData::getPlayerList();
		while ( my ( $id, $player ) = each ( %playerlist ) )
		{
			# Get total recommendations / n00bs for this player
			my $count;
			if ( $args{'command'} eq "teamplayers" ) { $count = modules::get_recommendation ( $player->{'name'} ); }
			else { $count = modules::get_n00b ( $player->{'name'} ); }

			# If they have more than 0 put them in the appropriate list
			if ( $player->{'side'} eq "NOD" || $player->{'side'} eq "Sov" )
				{ push ( @nodPlayers, modules::parseModName ( $player->{'name'}, $args{'nicktype'} ) . " ($count)" ); }
			else
				{ push ( @gdiPlayers, modules::parseModName ( $player->{'name'}, $args{'nicktype'} ) . " ($count)" ); }
		}


		# Were there any players found?
		if (scalar(@gdiPlayers) + scalar(@nodPlayers) == 0)
		{
			my $message;
			if ( $args{command} eq "teamplayers" )
				{ $message = "Nobody in the game has any recommendations"; }
			else
				{ $message = "Nobody in the game has been n00bed"; }

			if ( $args{'nicktype'} == 1 )
				{ brIRC::ircmsg ( $message, $args{'ircChannelCode'} ); }
			else
				{ RenRem::RenRemCMD( "msg [BR] $message" ); }

			return;
		}


		# We have found results, so output the header lines
		my $message;
		if ( $args{command} eq "teamplayers" )
			{ $message = "Teamplayers based on recommendations:"; }
		else
			{ $message = "n00bs based on in-game complaints:"; }

		if ( $args{'nicktype'} == 1 )
			{ brIRC::ircmsg ( $message, $args{'ircChannelCode'} ); }
		else
			{ RenRem::RenRemCMD( "msg [BR] $message" ); }


		# Output GDI players, 5 per line
		for ( my $i = 0; $i <= scalar(@gdiPlayers) - 1; $i = $i + 5 )
		{
			$message = $gdiPlayers[$i];
			for ( my $j = 1; $j < 5 && $i+$j < scalar(@gdiPlayers) - 1; $j++ )
			{
				$message .= " " .  $gdiPlayers[$i+$j];
			}

			if ( $args{'nicktype'} == 1 )
				{ brIRC::ircmsg ( "8GDI: $message", $args{'ircChannelCode'} ); }
			else
				{ RenRem::RenRemCMD( "msg [BR] GDI:  $message" ); }
		}


		# Output Nod players, 5 per line
		for ( my $i = 0; $i <= scalar(@nodPlayers) - 1; $i = $i + 5 )
		{
			$message = $nodPlayers[$i];
			for ( my $j = 1; $j < 5 && $i+$j < scalar(@nodPlayers) - 1; $j++ )
			{
				$message .= " " .  $nodPlayers[$i+$j];
			}

			if ( $args{'nicktype'} == 1 )
				{ brIRC::ircmsg ( "4Nod: $message", $args{'ircChannelCode'} ); }
			else
				{ RenRem::RenRemCMD( "msg [BR] Nod:  $message" ); }
		}
	}
	or modules::display_error($@);
}




###################################################
####
## CMSG functions, for showing colours messages ingame
####
###################################################


sub cmsg
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	if ( !modules::get_module( "bhs" ) )
	{
		brIRC::ircmsg ( "You need to enable module bhs and install the bhs library to use this command.", $args{'ircChannelCode'} );
		return;
	}

	my $rgbcolor;
	my $message;
	my $sendTo;

	if ( $args{command} eq "cmsg" )			# Send to all
	{
		$args{arg} =~ /^\!cmsg\s(\S*)\s(.*)/i;
		$rgbcolor = $1;
		$message = $2;
	}
	elsif ( $args{command} eq "cmsgp" )		# Send to player
	{
		$args{arg} =~ /^\!cmsgp\s(\S*)\s(\S+)\s(.*)/i;
		$rgbcolor = $1;
		$sendTo = $2;
		$message = $3;
	}
	elsif ( $args{command} eq "cmsgt" )		# Send to team
	{
		$args{arg} =~ /^\!cmsgt\s(\S*)\s(gdi|all|1|nod|sov|0)\s(.*)/i;
		$rgbcolor = $1;
		$sendTo = $2;
		$message = $3;
	}
	else
	{
		return;
	}

	if ( $rgbcolor && $message && ( $args{command} eq "cmsg" || $sendTo ) )
	{
		eval
		{
			my $red;
			my $green;
			my $blue;

			if ( $rgbcolor =~ m/^(\d{1,3}),(\d{1,3}),(\d{1,3})$/ )
			{
				if ( $1 > 255 || $2 > 255 || $3 > 255 )
				{
					brIRC::ircmsg ( "Error: Colour values cannot exceed 255.", $args{'ircChannelCode'} );
					return;
				}
				else
				{
					$red = $1;
					$green = $2;
					$blue = $3;
				}
			}
			else
			{
				if ( $rgbcolor =~ m/^red$/i )
				{
					$red = 255; $green = 0; $blue = 0;
				}
				elsif ( $rgbcolor =~ m/^blue$/i )
				{
					$red = 30; $green = 144; $blue = 255;
				}
				elsif ( $rgbcolor =~ m/^green$/i )
				{
					$red = 112; $green = 219; $blue = 147;
				}
				elsif ( $rgbcolor =~ m/^purple$/i )
				{
					$red = 138; $green = 43; $blue = 226;
				}
				elsif ( $rgbcolor =~ m/^orange$/i )
				{
					$red = 255; $green = 127; $blue = 0;
				}
				elsif ( $rgbcolor =~ m/^white$/i )
				{
					$red = 255; $green = 255; $blue = 255;
				}
				elsif ( $rgbcolor =~ m/^black$/i )
				{
					$red = 0; $green = 0; $blue = 0;
				}
				else
				{
					brIRC::ircmsg ( "Error: Unknown colour $rgbcolor. Valid colours: Red, Green, Blue, Purple, Orange, White, Black", $args{'ircChannelCode'} );
					return;
				}
			}

			if ( $args{command} eq "cmsg" )
			{
				RenRem::RenRemCMD( "cmsg $red,$green,$blue \($args{nick}): $message" );
				brIRC::ircmsg ( "14CMSG: ($args{nick}): $message", $args{'ircChannelCode'} );
			}
			elsif ( $args{command} eq "cmsgp" )
			{
				my ($result, %player) = playerData::getPlayerData( $sendTo );
				if ($result == 1)
				{
					RenRem::RenRemCMD( "cmsgp $player{id} $red,$green,$blue \($args{nick} to $player{name}): $message" );
					RenRem::RenRemCMD ( "sndp $player{id} yo1.wav" );
					brIRC::ircmsg ( "09CMSG sent to $player{name} --> ($args{nick}): $message", $args{'ircChannelCode'} );
				}
				else
				{
					brIRC::ircmsg ( "$sendTo was not found in the player list, or is not unique.", $args{'ircChannelCode'} );
				}
			}
			elsif ( $args{command} eq "cmsgt" )
			{
				my $team;
				if ( lc($sendTo) eq "gdi" || lc($sendTo) eq "all" || $sendTo eq "1" )
				{ $team = 1;}

				elsif ( lc($sendTo) eq "nod" || lc($sendTo) eq "sov" || $sendTo eq "0" )
				{ $team = 0;}

				else
				{ return; }

				RenRem::RenRemCMD( "cmsgt $team $red,$green,$blue \($args{nick} to team $team): $message" );
				RenRem::RenRemCMD( "sndt $team yo1.wav" );
				brIRC::ircmsg ( "09CMSG sent to team $team --> ($args{nick}): $message", $args{'ircChannelCode'}  );
			}
		}
		or modules::display_error($@);
	}
	else
	{
		my $syntaxvalue = $args{settings}->{syntax}->{value};
		brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
	}
}





###################################################
####
## Area system functions
####
###################################################

# Gets the current zone for a player
# sub getLocation
# {
# 	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
# 	my %args = %{$args};
#
# 	return if ( $args{nicktype} == 1 || modules::get_module ( "gamelog" ) != 1 );
#
# 	my ( $result, %player ) = playerData::getPlayerData( $args{nick} );
# 	if ( $result == 1 )
# 	{
# 		my ( $area, $xcoord, $ycoord ) = gamelog::getPlayerArea ( $player{name} );
#
# 		#RenRem::RenRemCMD ( "cmsgp $player{id} 30,144,255 You are currently in the area $area. Your coordinates are $xcoord, $ycoord." );
# 		RenRem::RenRemCMD ( "ppage $player{id} You are currently in the area $area. Your coordinates are $xcoord, $ycoord." );
# 		brIRC::ircmsg ( "09Page sent to $player{name} --> You are currently in the area $area. Your coordinates are $xcoord, $ycoord.", $args{'ircChannelCode'} );
# 	}
# }

# Locates a players teammate, and reports their character and vehicle
# sub locate
# {
# 	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
# 	my %args = %{$args};
#
# 	return if ( $args{nicktype} == 1 || modules::get_module ( "gamelog" ) != 1 );
#
# 	my ( $result, %player ) = playerData::getPlayerData( $args{nick} );
# 	if ( $result == 1 )
# 	{
# 		my ( $result2, %player2 ) = playerData::getPlayerData( $args{arg1} );
# 		if ( $result2 == 1 )
# 		{
# 			if ( $player{'side'} eq $player2{'side'} )
# 			{
# 				my ( $area, $xcoord, $ycoord, $character, $vehicle ) = gamelog::getPlayerArea ( $player2{'name'} );
#
# 				#RenRem::RenRemCMD ( "cmsgp $player{id} 30,144,255 You are currently in the area $area. Your coordinates are $xcoord, $ycoord." );
# 				if ( $vehicle ne "" )
# 				{
# 					RenRem::RenRemCMD ( "ppage $player{id} $player2{name} is in the area $area, as a $character, inside a $vehicle." );
# 					brIRC::ircmsg ( "09Page sent to $player{name} --> $player2{name} is in the area $area, as a $character, inside a $vehicle.", $args{'ircChannelCode'} );
# 				}
# 				else
# 				{
# 					RenRem::RenRemCMD ( "ppage $player{id} $player2{name} is in the area $area, as a $character." );
# 					brIRC::ircmsg ( "09Page sent to $player{name} --> $player2{name} is in the area $area, as a $character.", $args{'ircChannelCode'} );
# 				}
#
# 			}
# 			else
# 			{
# 				RenRem::RenRemCMD ( "ppage $player{id} $player2{name} is not on your team! This command can only be used on your teammates." );
# 				brIRC::ircmsg ( "09Page sent to $player{name} --> $player2{name} is not on your team! This command can only be used on your teammates.", $args{'ircChannelCode'} );
# 			}
# 		}
# 		else
# 		{
# 			RenRem::RenRemCMD ( "ppage $player{id} $args{arg1} was not found in the game, or is not unique." );
# 			brIRC::ircmsg ( "09Page sent to $player{name} --> $args{arg1} was not found in the game, or is not unique.", $args{'ircChannelCode'} );
# 		}
# 	}
# }


# Creates a new area
# sub addArea
# {
# 	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
# 	my %args = %{$args};
#
# 	return if ( $args{nicktype} == 1 || modules::get_module ( "gamelog" ) != 1 );
#
# 	my ( $result, %player ) = playerData::getPlayerData ( $args{nick} );
# 	if ( $result == 1 )
# 	{
# 		if ( $player{'openArea'} )
# 		{
# 			RenRem::RenRemCMD ( "ppage $player{id} You already have the area '$player{openArea}' open for editing! You must close this area with !closeArea before opening a new area." );
# 			brIRC::ircmsg ( "09Page sent to $player{name} --> You already have the area '$player{openArea}' open for editing! You must close this area with !closeArea before opening a new area.", $args{'ircChannelCode'} );
# 			return;
# 		}
#
# 		if ( $args{arg} =~ m/^\!\S+\s(.+)\s(\d)$/i )
# 		{
# 			my $result = gamelog::createArea ( $1, $2, $args{nick} );
# 			if ( $result == 1 )
# 			{
# 				RenRem::RenRemCMD ( "ppage $player{id} Created new area '$1'. Use !updateArea to expand the area, and close it with !closeArea." );
# 				brIRC::ircmsg ( "09Page sent to $player{name} --> Created new area '$1'. Use !updateArea to expand the area, and close it with !closeArea.", $args{'ircChannelCode'} );
#
# 				playerData::setKeyValue ( $player{'id'}, "openArea", $1 );
# 			}
# 			elsif ( $result == 2 )
# 			{
# 				RenRem::RenRemCMD ( "ppage $player{id} Expanded existing area '$1' to include your current position, and opened for editing." );
# 				brIRC::ircmsg ( "09Page sent to $player{name} --> Expanded existing area '$1' to include your current position, and opened for editing.", $args{'ircChannelCode'} );

# 				playerData::setKeyValue ( $player{'id'}, "openArea", $1 );
# 			}
# 			else
# 			{
# 				RenRem::RenRemCMD ( "ppage $player{id} Error: Unable to access area data!" );
# 				brIRC::ircmsg ( "09Page sent to $player{name} --> Error: Unable to access area data!", $args{'ircChannelCode'} );
# 			}
# 		}
# 		else
# 		{
# 			RenRem::RenRemCMD ( "ppage $player{id} Correct Usage: ".$args{settings}->{syntax}->{value} );
# 			brIRC::ircmsg ( "09Page sent to $player{name} --> Correct Usage: ".$args{settings}->{syntax}->{value}, $args{'ircChannelCode'} );
# 		}
# 	}
# }

# Opens an exiting area
# sub openArea
# {
# 	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
# 	my %args = %{$args};
#
# 	return if ( $args{nicktype} == 1 || modules::get_module ( "gamelog" ) != 1 );
#
# 	my ( $result, %player ) = playerData::getPlayerData ( $args{nick} );
# 	if ( $result == 1 )
# 	{
# 		if ( !($player{'openArea'}) && $args{arg} =~ m/^\!\S+\s(.+)$/i )
# 		{
# 			my $result = gamelog::expandArea ( $1, $args{nick} );
# 			if ( $result == 1 )
# 			{
# 				RenRem::RenRemCMD ( "ppage $player{id} Expanded existing area '$1' to include your current position, and opened for editing." );
# 				brIRC::ircmsg ( "09Page sent to $player{name} --> Expanded existing area '$1' to include your current position, and opened for editing.", $args{'ircChannelCode'} );

# 				playerData::setKeyValue ( $player{'id'}, "openArea", $1 );
# 			}
# 			else
# 			{
# 				RenRem::RenRemCMD ( "ppage $player{id} Unable to find any area called '$1'!" );
# 				brIRC::ircmsg ( "09Page sent to $player{name} --> Unable to find any area called '$1'!", $args{'ircChannelCode'} );
# 			}
# 		}
# 		else
# 		{
# 			RenRem::RenRemCMD ( "ppage $player{id} You already have the area '$player{openArea}' open for editing! You must close this area with !closeArea before opening a new area." );
# 			brIRC::ircmsg ( "09Page sent to $player{name} --> You already have the area '$player{openArea}' open for editing! You must close this area with !closeArea before opening a new area.!", $args{'ircChannelCode'} );
# 		}
# 	}
# }


# Creates a new area
# sub updateArea
# {
# 	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
# 	my %args = %{$args};
#
# 	return if ( $args{nicktype} == 1 || modules::get_module ( "gamelog" ) != 1 );
#
# 	my ( $result, %player ) = playerData::getPlayerData ( $args{nick} );
# 	if ( $result == 1 )
# 	{
# 		if ( $player{'openArea'} )
# 		{
# 			my $result = gamelog::expandArea ( $player{'openArea'}, $args{nick} );
# 			if ( $result == 1 )
# 			{
# 				RenRem::RenRemCMD ( "ppage $player{id} Expanded area '$player{openArea}' to include your current position." );
# 				brIRC::ircmsg ( "09Page sent to $player{name} --> Expanded area '$player{openArea}' to include your current position.", $args{'ircChannelCode'} );
# 			}
# 			else
# 			{
# 				RenRem::RenRemCMD ( "ppage $player{id} Error: Unable to access area data!" );
# 				brIRC::ircmsg ( "09Page sent to $player{name} --> Error: Unable to access area data!", $args{'ircChannelCode'} );
# 			}
#
# 			return;
# 		}
#
# 		RenRem::RenRemCMD ( "ppage $player{id} You do not have any area open for editing at this time. Create a new area using !addArea, or open an existing area using !openArea." );
# 		brIRC::ircmsg ( "09Page sent to $player{name} --> You do not have any area open for editing at this time. Create a new area using !addArea, or open an existing area using !openArea.", $args{'ircChannelCode'} );
# 	}
# }


# Closes an area
# sub closeArea
# {
# 	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
# 	my %args = %{$args};
#
# 	return if ( $args{nicktype} == 1 || modules::get_module ( "gamelog" ) != 1 );
#
# 	my ( $result, %player ) = playerData::getPlayerData ( $args{nick} );
# 	if ( $result == 1 )
# 	{
# 		if ( $player{'openArea'} )
# 		{
# 			RenRem::RenRemCMD ( "ppage $player{id} The area '$player{openArea}' has been closed!" );
# 			brIRC::ircmsg ( "09Page sent to $player{name} --> The area '$player{openArea}' has been closed!", $args{'ircChannelCode'} );
# 			playerData::setKeyValue ( $player{id}, "openArea", "" );
# 			return;
# 		}
#
# 		RenRem::RenRemCMD ( "ppage $player{id} You did not have an area open to begin with!" );
# 		brIRC::ircmsg ( "09Page sent to $player{name} --> You did not have an area open to begin with!", $args{'ircChannelCode'} );
# 	}
# }





###################################################
####
## Plugin management functions
####
###################################################

sub plugins
{
  my %args = %{$_[ ARG0 ]};

  if ($args{'nicktype'} != 1)
  {
    RenRem::pagePlayer($args{'nick'}, "The !plugins command can only be executed from IRC.");
    return;
  }

  $args{'nick'} =~ m/(.+)\@.+/i;
  my $nick = $1;

  brIRC::ircnotice ( $nick, "1Current plugin states;" );

  my %plugins = plugin::get_plugins();

  my @pluginStrings;
  while ( my($plugin, $state) = each(%plugins))
  {
    my $pluginString = ( $state == 1 )
      ? '09' . $plugin . ''
      : ( $state == 2 )
        ? '07' . $plugin . ''
        : '04' . $plugin . '';
    push ( @pluginStrings, $pluginString );
  }

  # Print to IRC in groups of 5
  my $msg = "";
  for ( my $i =0; $i <= scalar(@pluginStrings)-1; ++$i )
  {
    if ( ($i+1)%5 != 0 )
      { $msg .= modules::padd_string ( 20, $pluginStrings[$i] ).' '; }
    else
    {
       # No need to pad the one at the end of the line
      brIRC::ircnotice ( $nick, $msg . $pluginStrings[$i] );
      $msg = "";
    }
  }

  # If there is a partial line remaining then print it out
  if ( $msg ne "" )
    { brIRC::ircnotice ( $nick, $msg ); }
}

# --------------------------------------------------------------------------------------------------

sub plugin_load
{
  my %args = %{$_[ ARG0 ]};

  if ($args{'nicktype'} != 1)
  {
    RenRem::pagePlayer($args{'nick'}, "The !plugin_load command can only be executed from IRC.");
    return;
  }

  if (!$args{'arg1'})
  {
    my $syntaxvalue = $args{'settings'}->{'syntax'}->{'value'};
    brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
    return;
  }

  my $result = plugin::load_plugin($args{'arg1'});
  if ( $result == 0 or $result == 1 )
    { brIRC::ircmsg ( 'The plugin '.$args{'arg1'}.' was successfully loaded', $args{'ircChannelCode'} ); }
  elsif ( $result == -1 )
    { brIRC::ircmsg ( 'Unable to find a plugin called '.$args{'arg1'}, $args{'ircChannelCode'} ); }
  elsif ( $result == 2 )
    { brIRC::ircmsg ( 'An error occured whilst trying to load the plugin '.$args{'arg1'}, $args{'ircChannelCode'} ); }
}

# --------------------------------------------------------------------------------------------------

sub plugin_unload
{
  my %args = %{$_[ ARG0 ]};

  if ($args{'nicktype'} != 1)
  {
    RenRem::pagePlayer($args{'nick'}, "The !plugin_unload command can only be executed from IRC.");
    return;
  }

  if (!$args{'arg1'})
  {
    my $syntaxvalue = $args{'settings'}->{'syntax'}->{'value'};
    brIRC::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
    return;
  }

  plugin::unload_plugin($args{'arg1'});
  brIRC::ircmsg ( 'The plugin '.$args{'arg1'}.' is now being unloaded...', $args{'ircChannelCode'} );

  # Create session to check result (it takes 5 seconds to process a plugin unload to allow shutdown)
  POE::Session->create
  (
    inline_states =>
    {
      _start        => sub { $_[KERNEL]->delay('check_plugin' => 6); },
      check_plugin  => sub
      {
        my $plugin_state = plugin::get_state($args{'arg1'});
        if ( $plugin_state == 0 || $plugin_state == -1 )
          { brIRC::ircmsg ( 'The plugin '.$args{'arg1'}.' was successfully unloaded', $args{'ircChannelCode'} ); }
        else
          { brIRC::ircmsg ( 'The plugin '.$args{'arg1'}.' failed to unload, see the console for more information', $args{'ircChannelCode'} ); }
      },
    }
  );
}

# --------------------------------------------------------------------------------------------------




# Return true
1;