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


our %commands;              # Hash of commands and aliases in all plugins

our %plugin_events_old;
our %plugin_config;
our %plugin_gamelog_regexes;
our %plugin_renlog_regexes;
our @plugins;               # List of all plugins
our @gamelogRegexPlugins;   # List of plugins which have gamelog hooks setup
our @renlogRegexPlugins;    # List of plugins which have renlog hooks setup

our %core_function_overrides;

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

#** \function public get_state ( $plugin_name )
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
  ++$idx until $idx >= $size or $plugins[$idx] eq $plugin_name;
  return 1 if ( $idx < $size );

  return 0;
}

# --------------------------------------------------------------------------------------------------

#** \function public load_plugin ( $plugin_name )
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
  my $xml = undef;
  eval
  {
    no warnings 'deprecated';  # Suppress XML::Parser::Expat warning about tied handles...
    $xml = XMLin ( "plugins/$plugin_name.xml",
      ForceArray => [ qw(event group command hook cvar) ],
      KeyAttr => [ 'name', 'key', 'id', 'event' ] );
  };
  if ($@)
  {
    modules::console_output ( "Failed!\n\tError reading $plugin_name.xml: $@", 3 );
    set_state ( $plugin_name, 2 );
    return 2;
  }


  # OK, we got the XML file loaded OK, go ahead and try to load the plugin itself
  eval "use lib getcwd.'/plugins'; use $plugin_name;";
  if ($@)
  {
    modules::console_output ( "Failed!\n\tError loading $plugin_name.pm: $@", 3 );
    set_state ( $plugin_name, 2 );
    return 2;
  }


  # DEBUGGING CODE
#  open ( DATA_DUMP, '>' . $plugin_name . '_xmldatadump.txt' );
#  print DATA_DUMP Dumper( $xml );
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
    $additional_events .= " $key => sub { plugin_event('$plugin_name','$value',\@_); }, \n";
  }


  # Populate relevant data structures from XML data
  # \todo are all of these still actually being used? If not, maybe they should be removed?
  read_xml_commands($plugin_name, $xml);
  @{$plugin_events_old{$plugin_name}}           = get_events($xml, $plugin_name);
  read_xml_config($plugin_name, $xml);
  %{$plugin_gamelog_regexes{$plugin_name}}  = get_gamelog_regexes ( $xml, $plugin_name );
  %{$plugin_renlog_regexes{$plugin_name}}   = get_renlog_regexes ( $xml, $plugin_name );


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
                       ++$idx until $idx >= $size or $_[HEAP]->{\'child_sessions\'}[$idx] == $_[ARG1];
                       if ( $idx < $size )
                         { splice(@{$_[HEAP]->{\'child_sessions\'}},$idx,1); }
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

#** \function public unload_plugin ( $plugin_name )
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
  foreach(keys %commands) { delete $commands{$_} if $commands{$_}{'plugin_name'} eq $plugin_name; }

  # Wipe the plugin from all core function overloads
  foreach (keys %core_function_overrides)
    { delete $core_function_overrides{$_} if $core_function_overrides{$_}{'plugin_name'} eq $plugin_name; }

  delete $plugin_events_old{$plugin_name};
  delete $plugin_config{$plugin_name};
  delete $plugin_gamelog_regexes{$plugin_name};
  delete $plugin_renlog_regexes{$plugin_name};

  my ($size,$idx) = (scalar(@plugins), 0);
  ++$idx until $idx >= $size or $plugins[$idx] eq $plugin_name;
  splice (@plugins,$idx,1) if ( $idx < $size );

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
    my @events = @{$plugin_events_old{$plugin}};

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

# --------------------------------------------------------------------------------------------------

#** \function call_core_override ( $functionality, ... )
# \brief Calls the current override for the specified core functionality if one is set
#
# \return 1 if the core override was called, 0 if this functionality is not overridden
#*
sub call_core_override
{
  my $functionality = shift;

  if ( exists($core_function_overrides{$functionality}) )
  {
    plugin_event(
      $core_function_overrides{$functionality}{'plugin_name'},
      $core_function_overrides{$functionality}{'plugin_event'},
      @_);
    return 1;
  }
  
  return 0;
}

# --------------------------------------------------------------------------------------------------


#** \function private read_xml_config ( $plugin_name, $plugin_xml )
# \brief Read the plugin configuration settings from the XML file and load them into a hash
#*
sub read_xml_config
{
  my $plugin_name = shift;
  my $plugin_xml  = shift;

  $plugin_config{$plugin_name} = {};

  my $config_nodes = $plugin_xml->{'config'}->{'cvar'};
  for my $config_key ( keys %{$config_nodes} )
    { $plugin_config{$plugin_name}{$config_key} = $config_nodes->{$config_key}->{'value'}; }
}

#** \function private read_xml_commands ( $plugin_name, $plugin_xml )
# \brief Read the plugin commands from the XML file and load them into a hash
#*
sub read_xml_commands
{
  my $plugin_name = shift;
  my $plugin_xml  = shift;

  my $command_nodes = $plugin_xml->{'command'};
  while (my ($command, $command_config) = each %{$command_nodes})
  {
    $commands{$command} = {
      'plugin_name'     => $plugin_name,
      'configuration'   => $command_config
    };

    # Load aliases
    my $alias_nodes = $command_config->{'alias'};
    if ( defined $alias_nodes and $alias_nodes =~ "ARRAY")
    {
      foreach ( @{$alias_nodes} )
      {
        $commands{$_} = {
          'plugin_name'     => $plugin_name,
          'alias_for'       => $command
        };
      }
    }
    elsif ( defined $alias_nodes )
    {
      $commands{$alias_nodes} = {
        'plugin_name'     => $plugin_name,
        'alias_for'       => $command
      };
    }
  }
}


#** \function public find_command ( $command_name )
# \brief Search for a plugin command with the specified name or alias
#
# \returns $plugin_name Name of the plugin containing the command, or undef if none was found
# \returns $command_name The full name of the commmand, or undef if none was found
# \returns $command_config Configuration settings for the command, or undef if none was found
#*
sub find_command
{
  my $command_name = shift;

  if ( defined $commands{$command_name} )
  {
    my %command = %{$commands{$command_name}};

    # Check if this command is an alias for another...
    if ( defined $command{'alias_for'} )
    {
      # Safety check, make sure the command we are an alias for actually exists...
      if ( !defined $commands{$command{'alias_for'}} )
        { return (undef,undef,undef); }

      $command_name = $command{'alias_for'};
      %command = %{$commands{$command{'alias_for'}}};
    }

    return ($command{'plugin_name'},$command_name,$command{'configuration'});
  }

  return (undef,undef,undef);
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
#
# \param[in] $player
#   Name or ID of player to lookup
# \param[in] $sender
#   Message sender
# \param[in] $message
#   Message to send
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








###################################################
####
## Core Functionality Overrides for plugins
####
###################################################

#** \function public core_override_playerjoin_message ( $plugin_name, $plugin_event )
# \brief Sets an override event for the "player has joined" IRC message which will be called when a
#        new player joins the game. All player data except scripts version will be available when
#        this event is called
#
# \param[in] plugin_name
#   The name of the plugin setting the override
# \param[in] plugin_event
#   The name of an event to call on the plugin
#
# @return 1 if the override was set successfully, 0 if another plugin has already overridden this
#         functionality. This override can only be set once.
#*
sub core_override_playerjoin_message($$)
{
  my $plugin_name = shift;
  my $plugin_event = shift;

  return 0 if ( exists($core_function_overrides{'playerjoin_msg'}) );
  $core_function_overrides{'playerjoin_msg'} = { 'plugin_name' => $plugin_name, 'plugin_event' => $plugin_event };
  return 1;
}

#** \function public core_override_playerleave_message ( $plugin_name, $plugin_event )
# \brief Sets an override event for the "player has left" IRC message which will be called when a
#        player leaves the game. All player data will still be available when this event is called
#
# \param[in] plugin_name
#   The name of the plugin setting the override
# \param[in] plugin_event
#   The name of an event to call on the plugin
#
# @return 1 if the override was set successfully, 0 if another plugin has already overridden this
#         functionality. This override can only be set once.
#*
sub core_override_playerleave_message($$)
{
  my $plugin_name = shift;
  my $plugin_event = shift;

  return 0 if ( exists($core_function_overrides{'playerleave_msg'}) );
  $core_function_overrides{'playerleave_msg'} = { 'plugin_name' => $plugin_name, 'plugin_event' => $plugin_event };
  return 1;
}