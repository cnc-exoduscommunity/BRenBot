#!/usr/bin/perl

package plugin;
use strict;

use POE;
use XML::Simple;
#use Data::Dumper;    # Debugging use only
use Cwd;
use Class::Unload;

use modules;
use RenRem;


our %xml;
our %plugin_commands;
our %plugin_events;
our %plugin_config;
our %plugin_gamelog_regexes;
our %plugin_renlog_regexes;
our @plugins;               # List of all plugins
our @gamelogRegexPlugins;   # List of plugins which have gamelog hooks setup
our @renlogRegexPlugins;    # List of plugins which have renlog hooks setup

# --------------------------------------------------------------------------------------------------

sub get_plugins
{
  # \todo Update list of plugins in database - find_plugins or similar will do this when updated
  
  # Temporary implementation
  unless(opendir(DATADIR, "plugins/"))
    { return; }

  use lib getcwd.'/plugins'; 
    
  my %plugin_states = ();
  my @plugin_files;
  @plugin_files = grep(/\.pm$/i,readdir(DATADIR));

  foreach (@plugin_files)
  {
    my $plugin = $_;
    $plugin =~ s/\.pm$//g;
    $plugin_states{$plugin} = get_state($plugin);
  }
  
  closedir(DATADIR);
  
  return %plugin_states;
}

# --------------------------------------------------------------------------------------------------

# \todo This should check the database to see which plugins are enabled
# \todo Config item - autoload new plugins (those not already known about - should this be done in find_plugins?)
sub load_all_plugins
{
  # \todo Update list of plugins in database - find_plugins or similar will do this when updated

  unless(opendir(DATADIR, "plugins/"))
    { return; }

  use lib getcwd.'/plugins'; 
    
  my @plugin_files;
  @plugin_files = grep(/\.pm$/i,readdir(DATADIR));

  foreach (@plugin_files)
  {
    my $plugin = $_;
    $plugin =~ s/\.pm$//g;
    load_plugin ( $plugin );
  }
  
  closedir(DATADIR);
}

# --------------------------------------------------------------------------------------------------

#** \function private set_state ( $$plugin_name, $$plugin_state )
# \brief Sets the state of a plugin
#
# \param[in] plugin_name
#   Name of the plugin to set the state of
# \param[in] plugin_state
#   New plugin state (-1 = not found, 0 = unloaded, 1 = loaded, 2 = error)
#*
sub set_state
{
  my $plugin_name = shift;
  
  # \todo Finish this function
}

# --------------------------------------------------------------------------------------------------

#** \function public get_state ( $$plugin_name )
# \brief Get current state of a plugin
#
# \param[in] plugin_name
#   Name of the plugin to get the current state of
#
# \return Current plugin state (-1 = not found, 0 = unloaded, 1 = loaded, 2 = error)
#*
sub get_state
{
  my $plugin_name = shift;
  
  # \todo Finish this function
  
  # Temporary until database code is added
  my ($size,$idx) = (scalar(@plugins),0);
  ++$idx until $plugins[$idx] eq $plugin_name or $idx >= $size;
  return 1 if ( $idx < $size );

  return 0;
}

# --------------------------------------------------------------------------------------------------

#** \function public load_plugin ( $$plugin_name )
# \brief Attempt to load a plugin
#
# \param[in] plugin_name
#   Name of the plugin to attempt to load
#
# @return Result of loading the plugin ( -1 = not found, 0 = already loaded, 1 = loaded OK, 2 = error)
#*
sub load_plugin
{
  my $plugin_name = shift;
  my $plugin_state = get_state($plugin_name);
  
  # \todo Update list of plugins in database - find_plugins or similar will do this when updated

  # If the plugin was not found or is already loaded return relevant result code
  if ( $plugin_state == -1 )
    { return -1; }
  if ( $plugin_state == 1 )
    { return 0; }

  # OK, plugin exists and is not already loaded, so lets see if we can load it...
  modules::console_output ( "[PLUGIN] Loading plugin $plugin_name... ", 1 );


  # Load the plugin XML file first - this is the most likely part to fail
  eval
  {
    no warnings 'deprecated';  # Suppress XML::Parser::Expat warning about tied handles...
    $xml{$plugin_name} = XMLin ( "plugins/$plugin_name.xml",
                        ForceArray => [ qw(event group command hook) ],
                        KeyAttr => [ 'name', 'key', 'id', 'event' ] );
  };
  if ($@)
  {
    modules::console_output ( "Failed!\n\tError reading $plugin_name.xml: $@", 3 );
    set_state ( $plugin_name, 2 );
    return 2;
  }


  # OK, we got the XML file loaded OK, go ahead and try to load the plugin itself
  eval "use $plugin_name;";
  if ($@)
  {
    modules::console_output ( "Failed!\n\tError loading $plugin_name.pm: $@", 3 );
    set_state ( $plugin_name, 2 );
    return 2;
  }


  # DEBUGGING CODE
#  use Data::Dumper;
#  open ( DATA_DUMP, '>' . $plugin_name . '_xmldatadump.txt' );
#  print DATA_DUMP Dumper( $xml{$plugin_name} );
#  close DATA_DUMP;


  # Get additional events from XML configuration
  my %additional_events;
  eval "%additional_events = %" . $plugin_name . "::additional_events;";
  if ($@)
  {
    modules::console_output ( "Failed!\n\tError loading additional events: $@", 3 );
    set_state ( $plugin_name, 2 );
    return 2;
  }

  # Build additional events string
  my $additional_events;
  while (my ($key, $value) = each %additional_events)
  {
    $additional_events .= "  $key => \\&" . $plugin_name . "::$value, \n";
  }


  # Populate relevant data structures from XML data
  # \todo are all of these still actually being used? If not, maybe they should be removed?
  @{$plugin_commands{$plugin_name}}         = get_commands($xml{$plugin_name}, $plugin_name);
  @{$plugin_events{$plugin_name}}           = get_events($xml{$plugin_name}, $plugin_name);
  %{$plugin_config{$plugin_name}}           = get_plugin_config($xml{$plugin_name}, $plugin_name);
  %{$plugin_gamelog_regexes{$plugin_name}}  = get_gamelog_regexes ( $xml{$plugin_name}, $plugin_name );
  %{$plugin_renlog_regexes{$plugin_name}}   = get_renlog_regexes ( $xml{$plugin_name}, $plugin_name );


  # Loaded successfully, now try to start it...
  modules::console_output ( "Success!", 3 );


  # Build session creation string
  my $poe = "POE::Session->create (\n";
    $poe .= "  inline_states => {\n";
      $poe .= "    _start => \\&plugin_start, \n";
      $poe .= "    _stop => sub { plugin_event('".$plugin_name."','stop',\@_); }, \n";
      $poe .= '    _child => sub {
                     if ( \$_[ARG0] eq \'lose\' )
                     {
                       my $size = scalar(@{$_[HEAP]->{\'child_sessions\'}});
                       my $idx = 0;
                       ++$idx until $_[HEAP]->{\'child_sessions\'}[$idx] == $_[ARG1] or $idx >= $size;
                       if ( $idx < $size )
                         { delete $_[HEAP]->{\'child_sessions\'}[$idx]; }
                     }
                     else
                       { push(@{$_[HEAP]->{\'child_sessions\'}},$_[ARG1]); }
                   },'."\n";
      $poe .=     $additional_events;
      $poe .= "    plugin_start => sub { plugin_event('".$plugin_name."','start',\@_); }, \n";
      $poe .= "    command => sub { plugin_event('".$plugin_name."','command',\@_); }, \n";
      $poe .= "    text => sub { plugin_event('".$plugin_name."','text',\@_); }, \n";
      $poe .= "    playerjoin => sub { plugin_event('".$plugin_name."','playerjoin',\@_); }, \n";
      $poe .= "    playerleave => sub { plugin_event('".$plugin_name."','playerleave',\@_); }, \n";
      $poe .= "    mapload => sub { plugin_event('".$plugin_name."','mapload',\@_); }, \n";
      $poe .= "    changeteam => sub { plugin_event('".$plugin_name."','changeteam',\@_); }, \n";
      $poe .= "    gameresult => sub { plugin_event('".$plugin_name."','gameresult',\@_); }, \n";
      $poe .= "    shutdown => \\&plugin_shutdown, \n";
    $poe .= "  },\n";
    $poe .= "  args => \[ '$plugin_name' \]\n";
    $poe .= ");\n";


  # Execute session creation string
  eval "\n".$poe;
  if ($@)
  {
    modules::console_output( "[PLUGIN] $plugin_name failed to start! Error: $@" );
    set_state( $plugin_name, 2 );
    unload_plugin( $plugin_name );
    return 2;
  }

  # Plugin completely loaded, add it to the list of plugins
  # \todo once we finish the state get/set functions (database backed), do we need to keep this list?
  push (@plugins, $plugin_name);

  # Return success
  set_state ( $plugin_name, 1 );
  return 1;
}

# --------------------------------------------------------------------------------------------------

#** \function public unload_plugin ( $$plugin_name )
# \brief Unload a plugin
#
# \param[in] plugin_name
#   Name of the plugin to unload
#*
sub unload_plugin
{
  my $plugin_name = shift;
  my $plugin_state = get_state($plugin_name);

  # If the plugin is not currently loaded then do nothing
  if ( $plugin_state != 1 && $plugin_state != 2 )
    { return; }

  modules::console_output ( "[PLUGIN] Unloading plugin $plugin_name" );
  
  my $plugin_session = $poe_kernel->alias_resolve('plugin_'.$plugin_name);
  if ( defined($plugin_session) )
    { $poe_kernel->post($plugin_session,'shutdown'); }
  
  # Wipe the plugin from all data structures
  delete $plugin_commands{$plugin_name};
  delete $plugin_events{$plugin_name};
  delete $plugin_config{$plugin_name};
  delete $plugin_gamelog_regexes{$plugin_name};
  delete $plugin_renlog_regexes{$plugin_name};
  
  my ($size,$idx) = (scalar(@plugins), 0);
  ++$idx until $plugins[$idx] eq $plugin_name or $idx >= $size;
  delete $plugins[$idx] if ( $idx < $size );
  
  # Unimport plugin package in 5 seconds - this gives the plugin chance to shut down cleanly
  POE::Session->create
  (
    inline_states =>
    {
      _start        => sub { $_[KERNEL]->delay('unload_plugin' => 5); },
      unload_plugin => sub
      {     
        eval "no $plugin_name;
              Class::Unload->unload('$plugin_name');
              delete \$INC{'$plugin_name.pm'};";
        if ($@)
        {
          modules::console_output ( "[PLUGIN] Failed to unload $plugin_name.pm: $@" );
          set_state ( $plugin_name, 2 );
        }

        # If the plugin state is 2 leave it set to that (the caller will have set it), otherwise
        # set the state to unloaded
        elsif ( get_state($plugin_name) != 2 )
          { set_state ( $plugin_name, 0 ); }
      },
    }
  );
}

# --------------------------------------------------------------------------------------------------

#** \function private plugin_start
#* \brief Entry point for plugin sessions
#
# This function sets the POE session alias, copies the configuration data into the plugins shared
# %config variable and calls the plugin start function
#*
sub plugin_start
{
  my ( $kernel, $heap, $plugin_name ) = @_[KERNEL, HEAP, ARG0];
  
  $heap->{'plugin_name'}       = $plugin_name;
  @{$heap->{'child_sessions'}} = ();

  eval "
    \$". $plugin_name ."::plugin_name = '$plugin_name';
    if ( \$plugin_config{$plugin_name} )
      { \%". $plugin_name ."::config = %{\$plugin_config{$plugin_name}}; }
  ";

  if ( $@ )
  {
    modules::console_output ( "[PLUGIN] Failed to pass configuration data to plugin $plugin_name!" );
    unload_plugin($plugin_name);
    return;
  }

  $kernel->alias_set("plugin_" . $plugin_name);
  $kernel->yield("plugin_start");
}

# --------------------------------------------------------------------------------------------------

#** \function private plugin_shutdown
#* \brief Shutdown routine for plugin sessions
#
# This function is used to shutdown a plugin session prior to it being unloaded, allowing the POE
# session to exit gracefully. Note that plugins themselves can cause the session to linger beyond
# the intended lifespan, so we propagate the shutdown message to any child sessions.
#*
sub plugin_shutdown
{
  my ( $kernel, $heap ) = @_[KERNEL, HEAP];
  my $plugin_name = $heap->{'plugin_name'};

  # Remove the session alias and cancel any pending alarms or delays
  $kernel->alias_remove("plugin_" . $plugin_name);
  $kernel->alarm_remove_all();
  
  # Progagate message to any child sessions
  foreach (@{$heap->{'child_sessions'}})
    { $kernel->post ( $_, 'shutdown' ); }
  
  # Detach sessions to ensure we can shutdown properly even if they linger...
  while ( scalar(@{$heap->{'child_sessions'}}) > 0 )
  {
    my $session = pop(@{$heap->{'child_sessions'}});
    $kernel->detach_child($session);
  }
  
}

# --------------------------------------------------------------------------------------------------

#** \function private plugin_event ( $$plugin_name, $$event_name, ... )
# \brief Wrapper used to safely execute the named event on the given plugin
#
# \param[in] plugin_name
#   The name of the plugin to execute an event upon
# \param[in] plugin_event
#   The name of the event to execute within the plugin
# \param[in] ...
#   Additional arguments to be passed to the plugin event
#*
sub plugin_event
{
  # Shift plugin name and event name off the arguments array
  my $plugin_name = shift;
  my $plugin_event = shift;

  # Execute the event using the remaining arguments
  eval $plugin_name.'::'.$plugin_event.'(@_);';
  if ( $@ )
    { modules::console_output ( '[PLUGIN] Plugin '.$plugin_name.'::'.$plugin_event.' failed: '.$@ ); }
}

# --------------------------------------------------------------------------------------------------

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
sub RenRemCMD { RenRem::RenRemCMD($_[0]); }


# Send a RenRem command to the FDS after a delay
#
# \param[in] $command
#   Command line to send to the FDS
# \param[in] $delay
#   Delay, in seconds, before the command should be sent
sub RenRemCMDtimed { RenRem::RenRemCMDtimed(@_); }


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

#**
# \deprecated, not required for new IRC infrastructure
#*
sub get_irc_channel
{
  return $brconfig::irc_adminChannel;
}

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

sub display_plugin_error
{
  my $plugin = shift;
  my $error = shift;

  modules::console_output ( "[PLUGIN] Error in plugin $plugin - $error" );
}








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

# \deprecated Use getPlayerData and use the value of the scriptsVersion key within their data hash
sub get_bhs_version { return playerData::getKeyValue ( shift, "scriptsVersion"); }

1;