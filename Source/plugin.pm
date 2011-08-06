#!/usr/bin/perl

package plugin;
use strict;

use POE;
use XML::Simple;
#use Data::Dumper;		# Debugging use only
use Cwd;

use modules;


our %xml;
our %plugin_commands;
our %plugin_events;
our %plugin_config;
our %plugin_gamelog_regexes;
our %plugin_renlog_regexes;
our @plugins;							# List of all plugins
our @gamelogRegexPlugins;				# List of plugins which have gamelog hooks setup
our @renlogRegexPlugins;				# List of plugins which have renlog hooks setup



sub get_irc_channel
{
	return $brconfig::irc_adminChannel;
}

sub get_plugins
{
	unless(opendir(DATADIR, "plugins/"))
	{
		return;
	}

	my @plugin_files;
	@plugin_files = grep(/\.pm$/i,readdir(DATADIR));

	foreach (@plugin_files)
	{
		my $plugin = $_;
		$plugin =~ s/\.pm$//g;
		modules::console_output ( "Loading plugin $plugin... ", 1 );

		# Load plugin.pm
		eval "use lib '".getcwd."/plugins'; use $plugin;";
		if ($@)
		{
			modules::console_output ( "Failed! Error loading $plugin.pm: $@", 3 );
			next;
		}


		# Read plugin.xml file
		eval
		{
			$xml{$plugin} = XMLin ( "plugins/$plugin.xml", ForceArray => [ qw(event group command hook) ], KeyAttr => [ 'name', 'key', 'id', 'event' ] );
		};
		if ($@)
		{
			modules::console_output ( "Failed! Error reading $plugin.xml: $@", 3 );
			next;
		}

		# DEBUGGING
# 		use Data::Dumper;
#		open ( DATA_DUMP, '>' . $plugin . '_xmldatadump.txt' );
#		print DATA_DUMP Dumper( $xml{$plugin} );
#		close DATA_DUMP;


		# Get additional events
		my %additional_events;
		eval "%additional_events = %" . $plugin . "::additional_events;";
		if ($@)
		{
			modules::console_output ( "Failed! Error loading additional events: $@", 3 );
			next;
		}

		# Build additional events string
		my $additional_events;
		while (my ($key, $value) = each %additional_events)
		{
			$additional_events .= "  $key => \\&" . $plugin . "::$value, \n";
		}


		# Populate relevant data structures from XML data
		@{$plugin_commands{$plugin}}		= get_commands($xml{$plugin}, $plugin);
		@{$plugin_events{$plugin}}			= get_events($xml{$plugin}, $plugin);
		%{$plugin_config{$plugin}}			= get_plugin_config($xml{$plugin}, $plugin);
		%{$plugin_gamelog_regexes{$plugin}}	= get_gamelog_regexes ( $xml{$plugin}, $plugin );
		%{$plugin_renlog_regexes{$plugin}}	= get_renlog_regexes ( $xml{$plugin}, $plugin );


		# Loaded successfully, now try to start it...
		modules::console_output ( "Success! Attempting to start plugin", 3 );


		# Build session creation string
		my $poe = "POE::Session->create (\n";
		$poe .= "	inline_states => {\n";
   		$poe .= "		_start => \\&plugin_start, \n";
   		$poe .= "		_stop => sub { eval{ ".$plugin."::stop(\@_) }; print 'Plugin ".$plugin."::_stop failed: '.\$\@.\"\\n\"; }, \n";
		$poe .= 		$additional_events;
   		$poe .= "		plugin_start => sub { plugin_event('".$plugin."','start',\@_); }, \n";
   		$poe .= "		command => sub { plugin_event('".$plugin."','command',\@_); }, \n";
   		$poe .= "		text => sub { plugin_event('".$plugin."','text',\@_); }, \n";
   		$poe .= "		playerjoin => sub { plugin_event('".$plugin."','playerjoin',\@_); }, \n";
   		$poe .= "		playerleave => sub { plugin_event('".$plugin."','playerleave',\@_); }, \n";
   		$poe .= "		mapload => sub { plugin_event('".$plugin."','mapload',\@_); }, \n";
   		$poe .= "		changeteam => sub { plugin_event('".$plugin."','changeteam',\@_); }, \n";
   		$poe .= "		gameresult => sub { plugin_event('".$plugin."','gameresult',\@_); }, \n";
		$poe .= "	},\n";
		$poe .= "	args => \[ '$plugin' \]\n";
		$poe .= ");\n";


		# Execute session creation string
		eval "\n".$poe;
		if ($@)
		{
			modules::console_output ( "$plugin failed to start! Error: $@" );

			# Wipe the plugin from the data structures
			delete $plugin_commands{$plugin};
			delete $plugin_events{$plugin};
			delete $plugin_config{$plugin};
			delete $plugin_gamelog_regexes{$plugin};
			delete $plugin_renlog_regexes{$plugin};

			next;
		}

		# Plugin completely loaded, add it to the list of plugins
		push (@plugins, $plugin);

	}	# end of plugin foreach
}


# Get an array of plugins which have registered for the named event
sub get_plugin_event
{
	my $event = shift;
	my @found_plugins;

	foreach (@plugins)
	{
		my $plugin = $_;
		my @events = @{$plugin_events{$plugin}};

		foreach (@events)
		{
			if ($_ eq $event)
			{
				push (@found_plugins, $plugin);
				last;
			}
		}
	}

	return @found_plugins;
}

# Returns a list of plugins which have gamelog regex hooks setup
sub get_plugin_gamelog_regexes
{
	return @gamelogRegexPlugins;
}


# Returns a list of plugins which have renlog regex hooks setup
sub get_plugin_renlog_regexes
{
	return @renlogRegexPlugins;
}


sub plugin_start
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
   	my $kernel = $_[KERNEL];

   	my $alias = "plugin_" . $args;
   	$_[KERNEL]->alias_set($alias);
   	$_[KERNEL]->yield("plugin_start");

	my $set_plugin = "\$" . $args . "::plugin_name = '$args';";
	eval ("\n" . $set_plugin);

	if ( $plugin_config{$args} )
	{
		my %config = %{$plugin_config{$args}};
		my $set_config = "\%" . $args . "::config = %config;";
		eval ("\n" . $set_config);
	}
}


# Execute the named event on the given plugin
sub plugin_event
{
	# Shift plugin name and event name off the arguments array
	my $plugin = shift;
	my $event = shift;

	# Execute the event using the remaining arguments
	eval $plugin.'::'.$event.'(@_);';
	print 'Plugin '.$plugin.'::'.$event.' failed: '.$@."\n" if $@;
}


# Returns a hash of all the plugin gamelog regexes, and the events they should trigger
sub get_gamelog_regexes
{
	my $xml = shift;
	my $plugin = shift;

	my $c = $xml->{gamelog_regex_hooks}->{hook};
	my %regexes;

	if ( $c )
	{
		push ( @gamelogRegexPlugins, $plugin );
		for my $event ( keys %{$c} )
		{
			my $regex = $c->{$event}->{regex};
			$regexes{$regex} = $event;
		}
	}

	return %regexes;
}


# Returns a hash of all the plugin renlog regexes, and the events they should trigger
sub get_renlog_regexes
{
	my $xml = shift;
	my $plugin = shift;

	my $c = $xml->{renlog_regex_hooks}->{hook};
	my %regexes;

	if ( $c )
	{
		push ( @renlogRegexPlugins, $plugin );
		for my $event ( keys %{$c} )
		{
			my $regex = $c->{$event}->{regex};
			$regexes{$regex} = $event;
		}
	}

	return %regexes;
}


sub get_events
{
	my $xml = shift;
	my $plugin = shift;
	my @events;

	if ( $xml->{events}->{event} )
		{ @events = @{$xml->{events}->{event}}; }
	return (@events);
}

sub get_plugin_config
{
	my $xml = shift;
	my $plugin = shift;
	my %hash;

	my $c = $xml->{config}->{cvar};

	for my $key ( keys %{$c} )
	{
		my $value = $c->{$key}->{value};
		$hash{$key} = $value;
	}

	return (%hash);
}

sub get_commands
{
	my $xml    = shift;
	my $plugin = shift;

	my $c = $xml->{command};
	my @commands;

	while (my ($key, $value) = each %{$c})
	{
		my %hash;
		$hash{name} = $key;
		push (@commands, \%hash);

		next if ($key eq "event");

		foreach ($value)
		{

			my @array = @{$_} if ($_ =~ "ARRAY");

			foreach (@array)
			{
				$value = $_;
				my %hash = %{$value};
			}
		}


		if ($value->{alias})
		{
			my @aliases;

			if ($value->{alias} =~ "ARRAY")
			{
				@aliases = @{$value->{alias}};
			}
			else
			{
				@aliases = ($value->{alias});
			}

			if (@aliases)
			{
				foreach (@aliases)
				{
					my %hash;
					$hash{name}  = $_;
					$hash{alias} = $key;
					push (@commands, \%hash);
				}
			}
		}
	}

	return @commands;
}


sub get_command_settings
{
	my $command = shift;
	my $xml = shift;
	my $plugin = shift;

	my $c = $xml->{command}->{$command};

	my @alias;
	my @commandgroups;
	#my @usergroups;
	my @modules;

	my $count = scalar($c);
	if ($c->{alias})
	{
		my $count = scalar($c->{alias});

		if ($count > 0)
		{
			my @array = (@{$c->{alias}}) if scalar($c->{alias});

			if (@array)
			{
				foreach (@{$c->{alias}})
				{
					push (@alias, $_);
				}
			}
		} else
		{
			push (@alias, $count);
		}
	}

	# dereference command groups

	if ($c->{group})
	{

		my $count = scalar($c->{group});
		if ($count > 0)
		{
			my @array = (@{$c->{group}}) if scalar($c->{group});

			if (@array)
			{
				foreach (@{$c->{group}})
				{
					push (@commandgroups, $_);
				}
			}
		} else
		{
			push (@commandgroups, $count);
		}
	}


	if ($c->{module})
	{
		my $count = scalar($c->{module});

		if ($count > 0)
		{
			my @array = (@{$c->{module}}) if scalar($c->{module});

			if (@array)
			{
				foreach (@{$c->{module}})
				{
					push (@modules, $_);
				}
			}
		} else
		{
			push (@modules, $count);
		}
	}

	return ($c, \@alias, \@commandgroups, \@modules);
}

sub display_plugin_error
{
	my $plugin = shift;
	my $error = shift;

	modules::console_output ( "Error in Plugin $plugin - $error" );
}








##################################################
####
## API functions for plugins
####
##################################################

#########################
## Player functions
#########################

# Get the data hash of each player currently in the server
#
# \return
#   Hash of player data hashes indexed by their player ID
sub get_playerlist { return playerData::getPlayerList(); }


# Check if a player is ingame and get their data hash
#
# \param[in] $player
#   Name or ID of player to lookup
#
# \return
#   Array of ($result,$playerData) where $result is either 0 (not found), 1 (found) or 2 (multiple
#   non-exact matches found) and $playerData is either a hash of player data (if $result is 1) or an
#   empty list (any other value of $result)
sub getPlayerData { return playerData::getPlayerData($_[0]); }


# pagePlayer function for plugins
sub pagePlayer { return modules::pagePlayer ( @_ ); }


# Check moderator status of players, returns 1 for true, 0 for false.
# Parameters: playername
sub isTempMod { return modules::isTempMod(@_); }
sub isHalfMod { return modules::isHalfMod(@_); }
sub isFullMod { return modules::isFullMod(@_); }
sub isAdmin { return modules::isAdmin(@_); }


# Check if a given player has finished loading the map, returns 1 for 1, 0 for false.
# Parameters: playername
sub isPlayerLoaded { return gamelog::isPlayerLoaded(@_); }




#########################
## Server functions
#########################

# Send a RenRem command to the FDS
#
# \param[in] $command
#   Command line to send to the FDS
sub RenRemCMD { modules::RenRemCMD($_[0]); }


# Send a RenRem command to the FDS after a delay
#
# \param[in] $command
#   Command line to send to the FDS
# \param[in] $delay
#   Delay, in seconds, before the command should be sent
sub RenRemCMDtimed { modules::RenRemCMDtimed(@_); }


# Allows plugins to get the game status
sub getGameStatus { return serverStatus::getGameStatus(); }


# Server message function for plugins - shows a public chat message
# for all players in the server
sub serverMsg
{
	my $msg = shift;
	RenRemCMD ( "msg $msg" );
}




#########################
## Database functions
#########################

# Execute a query on the brenbot.dat SQLite3 database
#
# \param[in] $query
#   SQL statement to be executed on the database
# \param[in] $skipResults
#   Flag to indicate the results of the query should not be returned. Set this to 0 or leave it
#   undefined to get the query resutls
#
# \return
#   Hash of database result rows, each containing a hash of values for that row
sub execute_query { return brdatabase::execute_query( $_[0], $_[1] ); }


# Allows plugins to set globals in BRenBot's globals table
sub set_global { brdatabase::set_global(@_); }


# Allows plugins to retrieve globals in BRenBot's globals table
sub get_global { return brdatabase::get_global(@_); }




#########################
## Gamelog functions
#########################

# Allows plugins to translate presets
sub translatePreset { return gamelog::translatePreset(@_); }


# Allows plugins to translate weapon presets
sub translateWeaponPreset { return gamelog::translateWeaponPreset(@_); }


# Allows plugins to get playernames from object ID's
sub getPlayerFromObjectID { return gamelog::getPlayerFromObjectID(@_); }




#########################
## IRC functions
#########################

# Get permission level of an IRC user.
# Parameters: username, channelCode
sub getIrcPermissions { return brIRC::getUserPermissions(@_); }


# IRC Commands for plugins
sub ircmsg { brIRC::ircmsg(@_); }


# Send a message to a user
sub ircpm { brIRC::ircpm(@_); }


# Send a notice to a user
sub ircnotice { brIRC::ircnotice(@_); }




#########################
## Misc. / Unsorted functions
#########################

# Run a BRenBot command from a plugin
sub call_command
{
	my $callername  = shift;
	my $command     = shift;

	$command = "!$command";

	eval { commands::parsearg($command, $callername, "Y") };
	modules::display_error($@) if $@;
}


# Allows plugins to use the get_date_time function in modules
sub get_date_time { return modules::get_date_time (@_); }


# Internal IsNumeric function
# Parameters: input string
# Return: true/false
sub IsNumeric { return modules::IsNumeric(@_); }


# Get BRenBot version number
# Return: float
sub getBrVersion { return main::BR_VERSION; }


# Get BRenBot build number
# Return: int
sub getBrBuild { return main::BR_BUILD; }


# Print a timestamped message to the BRenBot console window
#
# \param[in] $message
#   Message to be written to the console window
sub console_output { return modules::console_output(@_); }








###################################################
####
## Deprecated API functions for plugins
####
###################################################

# \deprecated Use getPlayerData instead
sub PlayerInGame
{
	my ( $result, %player ) = playerData::getPlayerData($_[0]);
	return ( $result, "", \%player );
}

# \deprecated RenGuard is no longer supported
sub is_on_renguard { return 1; }

# \deprecated Use getPlayerData and use the value of the bhsVersion key within their data hash
sub get_bhs_version { return playerData::getKeyValue ( shift, "bhsVersion"); }

1;