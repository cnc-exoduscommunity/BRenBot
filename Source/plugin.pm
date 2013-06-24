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


my %plugins;                    # List of all known plugins and data associated with them
our %commands;                  # Hash of commands and aliases in currently loaded plugins
our %core_function_overrides;

our %plugin_config;


# --------------------------------------------------------------------------------------------------

#** \function find_plugins()
# \brief Checks for new plugins in the plugins directory
#*
sub find_plugins
{
  my @deleted_plugins = keys %plugins;
  
  return unless(opendir(DATADIR, "plugins/"));

  # Check plugins list in the plugins directory
  my @plugin_files = grep(/\.pm$/i,readdir(DATADIR));
  foreach (@plugin_files)
  {
    my $plugin_name = $_;
    $plugin_name =~ s/\.pm$//g;
    if ( !exists($plugins{$plugin_name}) )
    {
      $plugins{$plugin_name} = {
        'name'    => $plugin_name,
        'state'   => 0
      };
    }

    my ($idx) = grep { $deleted_plugins[$_] eq $plugin_name } 0..$#deleted_plugins;
    splice(@deleted_plugins,$idx,1) if defined($idx);
  }
  
  closedir(DATADIR);

  # Remove any plugins that we didn't find (unless they are in the "loaded" state)
  foreach ( @deleted_plugins )
    { delete $plugins{$_} if (get_state($_) != 1); }

  return %plugins;
}

# --------------------------------------------------------------------------------------------------

#** \function public init()
# \brief Called when BRenBot is ready for the plugins subsystem to initialise, loads a list of known
#        plugins and loads them as appropriate
#
# \todo Config item - autoload new plugins (those not already known about)
sub init
{
  find_plugins();
  use lib getcwd.'/plugins';

  while ( my($plugin,$data) = each(%plugins) )
  {
    # Get initial state for plugin from database
    my @db_record = plugin::execute_query("SELECT * FROM plugins WHERE name = '$plugin_name'");
    if ( @db_record and $db_record[0]->{'bIsEnabled'} == 1 )
    {
      # Get initial state for plugin from database
      load_plugin($plugin);
    }
  }
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
  my $plugin_state = shift;

  if ( exists ($plugins{$plugin_name}) )
  {
    $plugins{$plugin_name}{'state'} = $plugin_state;

    # Save the new enabled/disabled state to the database...
    my $dbState = ($plugin_state==1)?"1":"0";
    if ( plugin::execute_query("SELECT * FROM plugins WHERE name = '$plugin_name'") )
      { plugin::execute_query("UPDATE plugins SET bIsEnabled = $db_state WHERE name = '$plugin_name'", 1); }
    else
      { plugin::execute_query("INSERT INTO plugins(name,bIsEnabled) VALUES ( '$plugin_name', $db_state )", 1); }
  }
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

  if ( defined($plugins{$plugin_name}) )
    { return $plugins{$plugin_name}{'state'}; }

  return -1;
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
  
  # If the plugin state was not found try checking the plugin directory to see if it was added...
  if ( $plugin_state == -1 )
  {
    find_plugins();
    return -1 if (($plugin_state = get_state($plugin_name)) == -1);
  }

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
    unimport_plugin($plugin_name);
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
    unimport_plugin($plugin_name);
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
  read_xml_commands($plugin_name, $xml);
  read_xml_config($plugin_name, $xml);
  register_plugin_events($plugin_name,$xml)


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
      $poe .= "    plugin_start => sub {
                     my \$result = plugin_event('".$plugin_name."','start',\@_);
                     if ( defined(\$result) and \$result == 0 )
                     {
                       set_state('".$plugin_name."',2);
                       unload_plugin('".$plugin_name."');
                     }
                   }, \n";
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

  delete $plugin_config{$plugin_name};

  # Unimport plugin package in 5 seconds - this gives the plugin chance to shut down cleanly
  POE::Session->create
  (
    inline_states =>
    {
      _start        => sub { $_[KERNEL]->delay('unload_plugin' => 5); },
      unload_plugin => sub
      {
        my $error = unimport_plugin($plugin_name);
        if ($error)
        {
          modules::console_output ( "[PLUGIN] Failed to unload $plugin_name.pm: $error" );
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

#** function private unimport_plugin ( $$plugin_name )
# \brief Attempts to unimport all namespaces from the specified plugin, used to tidy up after a
#        failed plugin load or when unloading a plugin
#*
sub unimport_plugin
{
  my $plugin_name = shift;
  
  eval "no $plugin_name;
        Class::Unload->unload('$plugin_name');
        delete \$INC{'$plugin_name.pm'};";
  return $@;
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
  my $result = undef;
  eval '$result = '.$plugin_name.'::'.$plugin_event.'(@_);';
  if ( $@ )
  {
    modules::console_output ( '[PLUGIN] Plugin '.$plugin_name.'::'.$plugin_event.' failed: '.$@ );
    return 0;
  }

  return $result;
}

# --------------------------------------------------------------------------------------------------

#** \function register_plugin_events ( $$plugin_name, $$xml )
# \brief Register game events and log hooks for a plugin based on its XML file
#
# \param[in] $plugin_name
#   Name of the plugin to register events for
# \param[in] $xml
#   Parsed XML configuration file for the plugin
#*
sub register_plugin_events
{
  my $plugin_name = shift;
  my $xml = shift;

  if ( $xml->{'events'}->{'event'} )
  {
    $plugins{$plugin_name}{'events'} = @{$xml->{'events'}->{'event'}} );
  }

  $plugins{$plugin_name}{'renlog_hooks'} = {};
  $plugins{$plugin_name}{'gamelog_hooks'} = {};

  my $hooks = $xml->{'renlog_regex_hooks'}->{'hook'};
  if ( $hooks )
  {
    while ( my ($event,$regex) = each %{$hooks} )
    {
      $plugins{$plugin_name}{'renlog_hooks'}{$regex} = $event;
    }
  }

  $hooks = $xml->{'gamelog_regex_hooks'}->{'hook'};
  if ( $hooks )
  {
    while ( my ($event,$regex) = each %{$hooks} )
    {
      $plugins{$plugin_name}{'gamelog_hooks'}{$regex} = $event;
    }
  }
}

# --------------------------------------------------------------------------------------------------

# Get an array of plugins which have registered for the named event
sub get_plugin_event
{
  my $event = shift;

  my @found_plugins;
  while ( my($plugin, $data) = each(%plugins) )
  {
    next if ( get_state($plugin) != 1);

    foreach ( @{$data->{'events'}} )
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


# Takes a player name and returns it with any appropriate moderator symbols appended, based on their
# moderator status and the bot configuration for decorating moderator names
sub parseModName { return modules::parseModName(@_); }




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


# Allows plugins to write log entries
#
# \param[in] $code
#    A numerical code for this log entry, each plugin should use a unique code. Codes 1 to 10 are
#    reserved for use by BRenBot
# \param[in] $content
#    The string content of the log entry.
sub write_to_log
{
  # Prevent use of codes below 10
  return if ( $_[0] !~ m/^\d+$/ || $_[0] < 10 );
  brdatabase::writeLog(@_);
}




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


# Format string as a bold IRC string
sub irc_bold { brIRC::bold(@_); }


# Format string as a colourised IRC string in the specified colour
sub irc_colourise { brIRC::colourise(@_); }




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
## Team configuration query functions for plugins
##
## For all of these functions the team IDs are 0 (Nod), 1 (GDI) and 2 (Neutral/Other)
####
###################################################

# Get the full name of a team given its ID or abbreviation
#
# \param[in] $team
#   The ID or abbreviation of the team
sub plugin::team_get_name { return brTeams::get_name(@_); }

# Get the abbreviation for a team given its ID
#
# \param[in] $team
#   The ID of the team
sub plugin::team_get_abbreviation { return brTeams::get_abbreviation(@_); }

# Get the IRC colour code for a team given its ID
#
# \param[in] $team
#   The ID or abbreviation of the team
sub plugin::team_get_colour { return brTeams::get_colour(@_); }

# Colourise a string with the specified teams IRC colour
#
# \param[in] $team
#   The ID or abbreviation of the team
# \param[in] $string
#   The string to colourise
sub plugin::team_colourise { return brTeams::colourise(@_); }

# Get the full name of a team in a colourised IRC string given its ID or abbreviation
#
# \param[in] $team
#   The ID or abbreviation of the team
sub plugin::team_get_colourised_name { return brTeams::get_colourised_name(@_); }

# Get the abbreviation for a team in a colourised IRC string given its ID
#
# \param[in] $team
#   The ID of the team
sub plugin::team_get_colourised_abbreviation { return brTeams::get_colourised_abbreviation(@_); }








###################################################
####
## Sound effects
####
###################################################

# Plays a 2D sound effect for the specified player
sub play_sound_for_player
{
  my $player = shift;
  my $sound = shift;

  return bhs::playsndp($sound, $player);
}

# Plays a 2D sound effect for the specified team, by ID, name or abbreviation
sub play_sound_for_team
{
  my $team = shift;
  my $sound = shift;

  return bhs::playsndp_team($sound, $team);
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