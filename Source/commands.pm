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
use brTeams;
use brAuth;
use RenRem;
use fds;


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
      { ($command_name,$command_config) = find_command($command); }

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
			players => \&players,
			playerinfo => \&playerinfo,
			gameinfo => \&gameinfo,
			addtempmod => \&addtempmod,
			deltempmod => \&deltempmod,
			scripts => \&scripts,
			ids => \&ids,
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
			showmsgs => \&showmsgs,
			buildings => \&buildings,
			vehicles => \&vehicles,
			stats => \&stats,
			statsme => \&statsme,
			stop => \&stop,
			getbw => \&getbw,
			setbw => \&setbw,
			wpage => \&wpage,
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
      plugins => \&plugins,
      plugin_load => \&plugin_load,
      plugin_unload => \&plugin_unload
		}
		);


	}
} # end of parsearg




# --------------------------------------------------------------------------------------------------
##
#### General Command Functions
##
# --------------------------------------------------------------------------------------------------

##* \function logsearch
# \brief Searches in the database logs table for entries containing a specified search string
#
# \param[in] $search
#   String to search for within the log entries
#*
sub LogSearch
{
  my %args = %{$_[ ARG0 ]};

  eval
  {
    $args{'arg'} =~ m/\!logsearch\s(.+)/i;
    my $search = $1;

    if (!($search))
    {
      show_syntax_error(@_);
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
    my ( $result, %player ) = playerData::getPlayerData($args{'nick'});
    return if ( $result != 1 );
    fds::send_message_player("Stats for $player{name}: Kills $player{stats_kills}, Deaths $player{stats_deaths}, Vehicle Repair $player{stats_vehicleRepair}, Building Repair $player{stats_buildingRepair}, Buildings destroyed $player{stats_buildingKills}", $player{'id'});
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
			show_syntax_error(@_);
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
      
      my ($plugin_name,$command_name,$command_config) = plugin::find_command($command);
      if ( !defined $command_name or $command_config->{'enabled'}->{'value'} == 0 )
        { ($command_name,$command_config) = find_command($command); }
        
    
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
			show_syntax_error(@_);
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

    my $nModules = scalar(@modulesList);
		for ( my $i = 0; $i < $nModules; $i += 4 )
		{
			my $module1 = modules::padd_string ( 20, $modulesList[$i] );
			my $module2 = ($i+1 < $nModules) ? modules::padd_string ( 20, $modulesList[$i+1] ) : "";
			my $module3 = ($i+2 < $nModules) ? modules::padd_string ( 20, $modulesList[$i+2] ) : "";
			my $module4 = ($i+3 < $nModules) ? $modulesList[$i+3] : "";

			# Fourth one does not need padding, it comes at the end of the line
			brIRC::ircnotice ( $nick, "$module1 $module2 $module3 $module4" );
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
    show_syntax_error(@_);
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
    my $uptime = main::get_uptime();
    my $message = 'I\'ve been running for ';
    
    # Format the uptime
    my $days  = int($uptime/86400);
    my $hours = int(($uptime%86400)/60);
    
    if ( $days > 0 )
    {
      $message .= "$days days";
      $message .= "and $hours hours" if ( $hours > 0 );
    }
    else
    {
      my $minutes = int((($uptime%86400)%60)/60);
      my $seconds = int((($uptime%86400)%60)%60);
      
      $message .= "$hours hours, " if ( $hours > 0 );
      $message .= "$minutes minutes and $seconds seconds";
    }
    
    if ( $args{nicktype} == 1 ) { brIRC::ircmsg ( $message, $args{'ircChannelCode'} ); }
    else { RenRem::RenRemCMD ( "msg [BR] $message" ); }
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

			if ($brconfig::serverScriptsVersion >= 2.0)
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
			} # end of >= 2.0
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
			} # end of < 2.0
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
			show_syntax_error(@_);
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

				$message=substr($message,0,228); #limit length to <249 chars to prevent fds crash

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

sub ppage
{
	my %args = %{$_[ ARG0 ]};

	eval
	{
		if (!$args{arg1})
		{
			show_syntax_error(@_);
      return;
		}
		if ($args{arg} =~ /^\!ppage\s(.+?)\s(.+)/i)
		{ #pamsg

			if ($brconfig::serverScriptsVersion >= 2.0)
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
			brIRC::ircmsg("The server does not support this command", $args{'ircChannelCode'});
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
      show_syntax_error(@_);
      return;
    }
    
    my $pager = $args{'nick'};
    my $sound = $args{'arg2'};
    
    my ( $result, %player ) = playerData::getPlayerData($args{'arg1'});
    if ( $result == 1 )
    {
      if ( fds::play_sound_player($sound, $player{'id'}) == 1 )
      {
        brIRC::ircmsg ( "9Private sound sent to $player{name} --> \($pager): $sound", $args{'ircChannelCode'} );
      }
      else
      {
        brIRC::ircmsg("The server does not support this command or the players scripts version is too old", $args{'ircChannelCode'});
      }
    }
    else
    {
      brIRC::ircmsg ( "Error: $args{arg1} was not found ingame, or is not unique.", $args{'ircChannelCode'} );
    }
  }
  or modules::display_error($@);
}


sub tpage
{
  my %args = %{$_[ ARG0 ]};

  eval
  {
    if (!$args{'arg1'})
    {
      show_syntax_error(@_);
      return;
    }
    if ($args{arg} =~ /^\!\S+\s(\S+)\s(.+)/i)
    {
      my $team = brTeams::get_id_from_name($1);
      my $text = $2;

      if (!defined($team) || length($text) < 1)
      {
        show_syntax_error(@_);
        return;
      }

      if (0 == fds::send_coloured_message_team(0,255,0,$team,$text,$args{'nick'}))
      {
        brIRC::ircmsg("The server does not support this command", $args{'ircChannelCode'});
        return;
      }

      brIRC::ircmsg("9TeamPage Sent to team $team --> \($args{nick}): $text", $args{'ircChannelCode'});
    }
  }
  or modules::display_error($@);
}


sub snda
{
  my %args = %{$_[ ARG0 ]};

  eval
  {
    if (!$args{'arg1'})
    {
      show_syntax_error(@_);
      return;
    }
    
    my $pager = $args{'nick'};
    my $sound = $args{'arg1'};
    
    if ( fds::play_sound($sound) == 1 )
    {
      brIRC::ircmsg ( "9Global Sound --> \($pager): $sound", $args{'ircChannelCode'} );
    }
    else
    {
      brIRC::ircmsg("The server does not support this command", $args{'ircChannelCode'});
    }
  }
  or modules::display_error($@);
}

sub sndt
{
  my %args = %{$_[ ARG0 ]};

  eval
  {
    if (!$args{'arg1'} || !$args{'arg2'})
    {
      show_syntax_error(@_);
      return;
    }
    
    my $pager = $args{'nick'};
    my $teamid = brTeams::get_id_from_name($args{'arg1'});
    my $sound = $args{'arg2'};
    
    if ( fds::play_sound_team($sound,$teamid) == 1 )
    {
      brIRC::ircmsg ( "9Sound played for team $teamid --> \($pager): $sound", $args{'ircChannelCode'} );
    }
    else
    {
      brIRC::ircmsg("The server does not support this command", $args{'ircChannelCode'});
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
			show_syntax_error(@_);
			return;
		}

		if ($args{arg} =~ /^\!pamsg\s(.+?)\s(.+)/i)
		{ #pamsg

			if ($brconfig::serverScriptsVersion >= 2.0)
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
			brIRC::ircmsg("The server does not support this command", $args{'ircChannelCode'});
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
			show_syntax_error(@_);
			return;
		}
		else
		{
			my $user = $args{arg1};

			$args{arg} =~ m/\!\S+\s*(\S+)\s*(.*)/i;
			my $text = $2;


			if ($brconfig::serverScriptsVersion >= 2.0)
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
			brIRC::ircmsg("The server does not support this command", $args{'ircChannelCode'});
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
			show_syntax_error(@_);
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
			show_syntax_error(@_);
			return;
		}
		my $user = $args{arg1};

		if ($brconfig::serverScriptsVersion >= 2.0)
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
			brIRC::ircmsg("The server does not support this command", $args{'ircChannelCode'});
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
			show_syntax_error(@_);
			return;
		}
		my $user = $args{arg1};

		if ($brconfig::serverScriptsVersion >= 2.0)
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

				# If we dont have SSGM 4 we need to swap their team twice to kill them, check this would not
				# end the game before doing so
				if ( !($brconfig::ssgm_version >= 4)
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

					# Use kill console command if SSGM 4 is installed, otherwise use team2 twice
					if ( $brconfig::ssgm_version >= 4 )
					{
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
			brIRC::ircmsg("The server does not support this command", $args{'ircChannelCode'});
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

		if ($brconfig::serverScriptsVersion >= 3.0)
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

				# If we dont have SSGM 4 we need to swap their team twice to kill them, check this would not
				# end the game before doing so
				if ( !($brconfig::ssgm_version >= 4)
					&& ( ( ( $player{side} eq "GDI" || $player{side} eq "All" ) && ( serverStatus::getPlayers_GDI() == 1 ) )
					|| ( ( $player{side} eq "NOD" || $player{side} eq "Sov" ) && ( serverStatus::getPlayers_Nod() == 1 ) ) ) )
				{
					modules::pagePlayer ( $player{'id'}, "BRenBot", "Killing yourself now would end the game!" );
					return;
				}


				if ( gamelog::isPlayerLoaded( $player{'name'} ) )
				{
					# Use kill console command if SSGM 4 is installed, otherwise use team2 twice
					if ( $brconfig::ssgm_version >= 4 )
					{
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
			brIRC::ircmsg("The server does not support this command", $args{'ircChannelCode'});
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
			show_syntax_error(@_);
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
			show_syntax_error(@_);
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
			show_syntax_error(@_);
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

		modules::record_ban ( '', $args{'nick'}, $reason, $ip, '' );


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
			show_syntax_error(@_);
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

    # Find any map specific rules
    my $maprules = get_map_setting('rules');
    if (defined($maprules))
    {
      fds::send_message('Special rules for '.serverStatus::getMap().': '.$maprules);
    }
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
          my $bantime = modules::strftimestamp('%d/%m/%Y %H:%M:%S', $hash{'timestamp'});
          my $string = "($hash{'id'})07 $hash{'name'} ($hash{'ip'}) banned by $hash{'banner'} on $bantime for '$hash{'reason'}'";

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
			show_syntax_error(@_);
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
    if (!$args{'arg1'})
    {
      show_syntax_error(@_);
      return;
    }

    if ( $args{'arg'} =~ /^\!.+?\s(.+)$/ )
    {
      my $msg = $1;

      # Put dots in bye or connect to prevent the
      # server from filtering them
      $msg =~ s/bye/by\.e/gi;
      $msg =~ s/connect/conn\.ect/gi;
      
      fds::send_message($msg, $args{'nick'});
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
      show_syntax_error(@_);
      return;
    }

    if ( $args{'arg'} =~ /^\!.+?\s(.+)$/ )
    {
      fds::send_admin_message($1, $args{'nick'});
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
      brIRC::ircmsg(brTeams::colourise(1,brIRC::bold(brTeams::get_name(1).':')." $gdiguys[$i] $gdiguys[$i+1] $gdiguys[$i+2] $gdiguys[$i+3]", $args{'ircChannelCode'} ));
    }
    for ( my $i = 0; $i <= scalar(@noddies)-1; $i = $i+5 )
    {
      brIRC::ircmsg(brTeams::colourise(0,brIRC::bold(brTeams::get_name(0).':')." $noddies[$i] $noddies[$i+1] $noddies[$i+2] $noddies[$i+3]", $args{'ircChannelCode'} ));
    }
  }
  or modules::display_error($@);
}



# Shows the scripts version of each player ingame
sub scripts
{
  my %args = %{$_[ ARG0 ]};

  # IRC only
  if ( $args{nicktype} != 1 )
    { return; }

  eval
  {
    if ($brconfig::serverScriptsVersion >= 1.3)
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
        brIRC::ircmsg(brTeams::colourise(1,brIRC::bold(brTeams::get_name(1).':')." $gdiguys[$i] $gdiguys[$i+1] $gdiguys[$i+2] $gdiguys[$i+3]", $args{'ircChannelCode'} ));
      }
      for ( my $i = 0; $i <= scalar(@noddies)-1; $i = $i+5 )
      {
        brIRC::ircmsg(brTeams::colourise(0,brIRC::bold(brTeams::get_name(0).':')." $noddies[$i] $noddies[$i+1] $noddies[$i+2] $noddies[$i+3]", $args{'ircChannelCode'} ));
      }
    }
    else
    {
			brIRC::ircmsg("The server does not support this command", $args{'ircChannelCode'});
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
		if ($brconfig::serverScriptsVersion >= 2.0)
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
				show_syntax_error(@_);
			}
		}
		else
		{
			brIRC::ircmsg("The server does not support this command", $args{'ircChannelCode'});
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
		if ($brconfig::serverScriptsVersion >= 2.0)
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

						$_[HEAP]->{'name'} = $pname;
						$_[HEAP]->{'outputType'} = $outputType;
					},
					tick => \&showbw
				}
			);
		}
		else
		{
			brIRC::ircmsg("The server does not support this command", $args{'ircChannelCode'});
		}
	}
	or modules::display_error($@);
}

sub showbw
{
  my %args = %{$_[ ARG0 ]};
  my $pname = $_[HEAP]->{'name'};

  if ( $pname )  # Name specified, look up their bandwidth
  {
    my ( $result, %player ) = playerData::getPlayerData($pname);
    if ( $result == 1 )
    {
      if ( $args{'nicktype'} eq 'irc' )
      {
        my $pname = brTeams::colourise($player{'teamid'}, modules::parseModName($player{'name'}, 1));
        brIRC::ircmsg ( "$pname has their bandwidth set to $player{'bandwidth'}", $args{'ircChannelCode'} );
      }
      else
      {
        my $pname = modules::parseModName($player{'name'}, 0);
        RenRem::RenRemCMD ( "msg [BR] $pname has their bandwidth set to $player{'bandwidth'}" );
      }
    }
  }
  else        # No name specified, list all players - IRC only
  {
    brIRC::ircmsg ( "Bandwidth settings:", $args{'ircChannelCode'} );
    my @bwoutput;

    my %playerlist = playerData::getPlayerList();
    while ( my ( $id, $player ) = each ( %playerlist ) )
    {
      my $pname = brTeams::colourise($player->{'teamid'}, modules::parseModName($player->{'name'}, 1));
      push ( @bwoutput, "$pname: $player->{bandwidth}" );
    }

    # Output players in groups of 4 to the IRC
    for ( my $i=0; $i<=scalar(@bwoutput)-1;$ i+=4 )
    {
      brIRC::ircmsg ( "$bwoutput[$i]   $bwoutput[$i+1]   $bwoutput[$i+2]   $bwoutput[$i+3]", $args{'ircChannelCode'} );
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
			show_syntax_error(@_);
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
			show_syntax_error(@_);
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
  my %args = %{$_[ ARG0 ]};

  eval
  {
    my ( $serverMode, $currentMap, $gdiPlayers, $gdiPoints, $nodPlayers, $nodPoints, $currentPlayers, $maxPlayers, $timeRemaining, $sfps ) = serverStatus::getGameStatus();
    my $team0name = brTeams::get_name(0);
    my $team0colour = brTeams::get_colour(0);
    my $team1name = brTeams::get_name(1);
    my $team1colour = brTeams::get_colour(1);
    
    if (modules::get_module("new_gi") )		# Use new style GI
    {
      my $string = brIRC::bold(brIRC::colourise(15,'Gameinfo: '));
      $string   .= brIRC::colourise(11,"($serverMode) ");
      $string   .= brIRC::colourise(15,"Map: $currentMap ");
      $string   .= brIRC::colourise($team1colour,"$team1name: $gdiPlayers/$maxPlayers players  $gdiPoints points ");
      $string   .= brIRC::colourise($team0colour,"$team0name: $nodPlayers/$maxPlayers players  $nodPoints points ");
      $string   .= brIRC::colourise(15,"$timeRemaining mins left SFPS: $sfps");
      brIRC::ircmsg ( $string, $args{'ircChannelCode'} );
    }
    else
    {
      # Use old style GI
      brIRC::ircmsg ( "      Map : $currentMap", $args{'ircChannelCode'} );
      brIRC::ircmsg ( "     Time : $timeRemaining", $args{'ircChannelCode'} );
      brIRC::ircmsg ( "  Players : $currentPlayers / $maxPlayers", $args{'ircChannelCode'} );
      
      brIRC::ircmsg ( brIRC::colourise($team1colour, modules::padd_string(9,$team1name,1)
      . " : $gdiPlayers players          $gdiPoints points", $args{'ircChannelCode'} ));
      
      brIRC::ircmsg ( brIRC::colourise($team0colour, modules::padd_string(9,$team0name,1)
      . " : $nodPlayers players          $nodPoints points", $args{'ircChannelCode'} ));
      
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
		my $format = " %-5s %-" . ($longestName +2) . "s %-6s %-5s %-5s %-16s %-5s %-10s";
		my $line = sprintf ( $format, 'Id', 'Name', 'Score', 'Side', 'Ping', 'Address', 'Kb/s', 'Time' );

    # Print out header line
    brIRC::ircmsg ( "01" . $line, $args{'ircChannelCode'} );


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

        # Finally output to IRC with team colour coding added
        brIRC::ircmsg ( brTeams::colourise($player->{'teamid'},$line), $args{'ircChannelCode'} );

			} # End of searching IF
		} # end of foreach playerlist
	}
	or modules::display_error($@);
} # end of playerinfo

# --------------------------------------------------------------------------------------------------

# !players command, commonly aliased as !pl, this command prints a list of ingame players to IRC. It
# cannot be used ingame. This command does not show detailed per-player stats, use the !playerinfo
# command for that.
sub players
{
  my %args = %{$_[ ARG0 ]};

  eval
  {
    if ( serverStatus::getCurrentPlayers() == 0 )
    {
      brIRC::ircmsg ( "There are no players ingame at this time.", $args{'ircChannelCode'} );
      return;
    }

    players_processTeam(1, $args{'ircChannelCode'});
    players_processTeam(0, $args{'ircChannelCode'});
    
    # These two will rarely be populated (the second hopefully never) but we should be returning
    # a complete list of players ingame so we check these anyway
    players_processTeam(2, $args{'ircChannelCode'});
    players_processTeam(undef, $args{'ircChannelCode'});
  }
  or modules::display_error($@);
}

# Worker function for the !players command
sub players_processTeam
{
  my $teamid      = shift;
  my $ircChannel  = shift;
  my $string      = "";
  my $count       = 0;

  my %teamplayers = playerData::getPlayersByTeam($teamid);
  while ( my($id, $player) = each(%teamplayers) )
  {
    $string .= " ".modules::padd_string(22, modules::parseModName($player->{'name'}, 1));

    if ( ++$count >= 5 )
    {
      players_outputTeam($teamid, $ircChannel, $string);
      $count = 0;
      $string = "";
    }
  }
  
  players_outputTeam($teamid, $ircChannel, $string) if ( $string ne "" );
}

# Worker function for the !teamplayers command
sub players_outputTeam
{
  my $teamid      = shift;
  my $ircChannel  = shift;
  my $string      = shift;
  
  $string = brTeams::colourise($teamid, brIRC::bold(brTeams::get_name($teamid).":").$string);
  brIRC::ircmsg($string, $ircChannel);
}

# --------------------------------------------------------------------------------------------------

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
		if ($brconfig::serverScriptsVersion >= 2.0)
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
		if ($brconfig::serverScriptsVersion >= 2.0)
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
  my %args = %{$_[ ARG0 ]};

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
        show_syntax_error(@_);
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

  if ( $args{'arg1'} )
  {
    $args{'arg'} =~ m/\!fds\s(.+)/i;
    my $message = substr ( $1, 0, 228 );    # Limit length to prevent crashing the FDS
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
			show_syntax_error(@_);
      return;
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
			show_syntax_error(@_);
      return;
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
  my %args = %{$_[ ARG0 ]};

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
  my %args = %{$_[ ARG0 ]};

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
					$_[KERNEL]->post( "voteThread" => "cancel" );
					$voteinprogress = 0;
				}
				elsif ( $teamsinprogress == 1 )
				{
					RenRem::RenRemCMD("msg [BR] Stopping team regulator..");
					$_[KERNEL]->post( "teams" => "cancel" );
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
			show_syntax_error(@_);
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
			show_syntax_error(@_);
			return;
		}

		# Now check that voting is enabled
		if ( $brconfig::config_votingenabled eq "0" )
		{
			modules::pagePlayer ( $args{'nick'}, 'BRenBot', 'Sorry, Voting has been temporarily disabled by the administration.' );
			return;
		}

		# Check they are not trying to use the voting system from IRC
		if ($args{'nicktype'} eq 1)
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
        modules::pagePlayer ( $args{'nick'}, 'BRenBot', 'Only 1 vote is allowed at a time.  Please wait for the current voting period to end.' );
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
        modules::pagePlayer ( $args{'nick'}, 'BRenBot', 'There isn\' anything to vote on at the moment' );
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
      modules::pagePlayer ( $args{'nick'}, 'BRenBot', 'You are not allowed to vote more than once' );
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
			$voteHeap{'kick_reason'} = "trying to VOTE-KICK a server moderator or server administator.";
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
        $_[KERNEL]->alarm( tick1 => undef );
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

  my $gdi_yes_votes = ( $voters{'team#1_yes'} ) ? $voters{'team#1_yes'} : 0;
  my $gdi_no_votes = ( $voters{'team#1_no'} ) ? $voters{'team#1_no'} : 0;
  my $nod_yes_votes = ( $voters{'team#0_yes'} ) ? $voters{'team#0_yes'} : 0;
  my $nod_no_votes = ( $voters{'team#0_no'} ) ? $voters{'team#0_no'} : 0;

	RenRem::RenRemCMD('msg [BR] Voting period over, tallying votes...   '
                    .brTeams::get_name(1)."; $gdi_yes_votes Yes, $gdi_no_votes No"
                    .brTeams::get_name(0)."; $nod_yes_votes Yes, $nod_no_votes No");

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
  my $vote  = shift;
  my $voter = shift;

  $voters{$voter} = $vote;

  # Get hash of voter so we can check their team
  my ( $result, %player ) = playerData::getPlayerData ( $voter );
  if ( $result == 1 )
  {
    my $voteText = ( $vote == 1 ) ? 'yes' : 'no';
    $voters{'team#'.$player{'teamid'}.'_'.$voteText}++;   # team#0_yes, team#1_no etc
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
## CMSG functions, for showing colours messages ingame
####
###################################################


sub cmsg
{
  my %args = %{$_[ ARG0 ]};

  eval
  {
    my ($colour, $message, $sendTo);

    if ($args{'command'} eq 'cmsg')           # Send to all
    {
      $args{'arg'} =~ /^\!cmsg\s(\S+|\d{1,3},\d{1,3},\d{1,3})\s(.*)/i;
      $colour = $1;
      $message = $2;
    }
    elsif ($args{'command'} eq 'cmsgp')       # Send to player
    {
      $args{'arg'} =~ /^\!cmsgp\s(\S+|\d{1,3},\d{1,3},\d{1,3})\s(\S+)\s(.*)/i;
      $colour = $1;
      $sendTo = $2;
      $message = $3;
    }
    elsif ($args{'command'} eq 'cmsgt')       # Send to team
    {
      $args{'arg'} =~ /^\!cmsgt\s(\S+|\d{1,3},\d{1,3},\d{1,3})\s(\S+)\s(.*)/i;
      $colour = $1;
      $sendTo = $2;
      $message = $3;
    }

    if (!defined $message)
    {
      show_syntax_error(@_);
      return;
    }

    my ($red,$green,$blue) = cmsg_colourToRgb($colour);
    if (!defined $red || !defined $green || !defined $blue)
    {
      brIRC::ircmsg("Error: Unknown colour $colour. Valid colours: Red, Green, Blue, Purple, Orange, White, Black", $args{'ircChannelCode'});
      return;
    }

    if ($args{'command'} eq 'cmsg')
    {
      if (1 != fds::send_coloured_message($red,$green,$blue,$message,$args{'nick'}))
      {
        brIRC::ircmsg('The server does not support this command, script version 2.6 or higher is required', $args{'ircChannelCode'});
        return;
      }
      
      brIRC::ircmsg ("14CMSG: ($args{nick}): $message", $args{'ircChannelCode'});
    }
    elsif ($args{'command'} eq 'cmsgp')
    {
      my ($result, %player) = playerData::getPlayerData($sendTo);
      if ($result != 1)
      {
        brIRC::ircmsg("$sendTo was not found in the player list or is not unique.", $args{'ircChannelCode'});
        return;
      }

      if (1 != fds::send_coloured_message_player($red,$green,$blue,$message,$player{'id'},$args{'nick'}))
      {
        brIRC::ircmsg('The server does not support this command, script version 2.6 or higher is required', $args{'ircChannelCode'});
        return;
      }

      brIRC::ircmsg ( "09CMSG sent to $player{name} --> ($args{nick}): $message", $args{'ircChannelCode'} );
    }
    elsif ( $args{command} eq "cmsgt" )
    {
      my $team = btTeams::get_id_from_name($2);
      if (!defined $team)
      {
        brIRC::ircmsg("Team name $sendTo not recognised", $args{'ircChannelCode'});
        return;
      }

      if (1 != fds::send_coloured_message_team($red,$green,$blue,$message,$team,$args{'nick'}))
      {
        brIRC::ircmsg('The server does not support this command, script version 2.6 or higher is required', $args{'ircChannelCode'});
        return;
      }
      
      brIRC::ircmsg('09CMSG sent to '.brTeams::get_name($team)." team --> ($args{nick}): $message", $args{'ircChannelCode'});
    }
  }
  or modules::display_error($@);
}

sub cmsg_colourToRgb
{
  my $colour = lc(shift);
  if ($colour =~ m/^(\d{1,3}),(\d{1,3}),(\d{1,3})$/)
  {
    return ($1,$2,$3) if (255 >= $1 && 255 >= $2 && 255 >= $3);
    return undef;
  }

  return (255, 0, 0) if $colour eq 'red';
  return (30, 144, 255) if $colour eq 'blue';
  return (112, 219, 147) if $colour eq 'green';
  return (138, 43, 226) if $colour eq 'purple';
  return (255, 127, 0) if $colour eq 'orange';
  return (255, 255, 255) if $colour eq 'white';
  return (0, 0, 0) if $colour eq 'black';

  return undef;
}





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

  my %plugins = plugin::find_plugins();

  my @pluginStrings;
  while ( my($plugin, $data) = each(%plugins))
  {
    my $pluginString = ( $data->{'state'} == 1 )
      ? '09' . $plugin . ''
      : ( $data->{'state'} == 2 )
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
    show_syntax_error(@_);
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
    show_syntax_error(@_);
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
##
#### Utility Functions
##
# --------------------------------------------------------------------------------------------------

sub show_syntax_error()
{
  my %args = %{$_[ ARG0 ]};
  my $syntax = 'Usage: '.$args{'settings'}->{'syntax'}->{'value'};

  if ( $args{'nicktype'} == 0 )
    { modules::pagePlayer( $args{'nick'}, 'BRenBot', $syntax ); }
  elsif ( $args{'nicktype'} == 1 )
    { brIRC::ircmsg( $syntax, $args{'ircChannelCode'} ); }
  else
    { modules::console_output('A plugin used incorrect command syntax for '.$args{'command'}); }
}

##* \function private check_ssgm_version ( $$required_version ))
# \brief Checks if the version of SSGM running on the server is >= to a required version
#
# \param[in] $required_version
#   The required version of SSGM to check against
#
# \return
#   1 if the version of SSGM is >= to the required version, 0 otherwise
#*
sub check_ssgm_version
{
  my $required_version = shift;

  return ( $brconfig::ssgm_version >= $required_version ) ? 1 : 0;
}




# Return true
1;