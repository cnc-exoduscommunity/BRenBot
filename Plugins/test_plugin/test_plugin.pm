#
# Test Plugin for BRenBot 1.x
# This plugin is used to test the BRenBot plugin interface is working correctly
#
package test_plugin;

use POE;
use plugin;
use strict;

# --------------------------------------------------------------------------------------------------

our %additional_events =
(
  # !commands
  "test_plugin" => "test_plugin",
);

# plugin_name and config are automatically populated by BRenBot
our $plugin_name;
our %config;

# --------------------------------------------------------------------------------------------------
# Event Handlers

# Runs when BRenBot loads the plugin
sub start
{
  plugin::console_output ( '[test_plugin] Started. Config is '.$config{'param1'}.' and '.$config{'param2'} );
  start_sessions();
}

# Runs when the plugin is unloaded
sub stop
{
  plugin::console_output ( '[test_plugin] Stopped' );
}

# Runs when a !command specified in the .xml file is typed
sub command
{
  my %args = %{$_[ ARG0 ]};
  plugin::console_output ( '[test_plugin] Command' );
  
  if ( $args{'command'} eq 'test_plugin' )
    { $_[KERNEL]->yield('test_plugin' => \%args); }
}

# Runs when any text is typed ingame or in IRC
sub text
{
  my %args = %{$_[ ARG0 ]};
  plugin::console_output ( '[test_plugin] Text ('.$args{'nick'}.': '.$args{'message'}.')' );
}

# --------------------------------------------------------------------------------------------------
# Commands

sub test_plugin
{
  my %args = %{$_[ ARG0 ]};
  plugin::console_output('[test_plugin] command called by ' . $args{'nick'});
}

# --------------------------------------------------------------------------------------------------
# Sessions

sub start_sessions()
{
  # Session with recurring alarm
  POE::Session->create
  (
    inline_states =>
    {
      _start          => sub
      {
        plugin::console_output('[test_plugin] Session 1 Started');
        $_[KERNEL]->yield('tick');
      },
      _stop           => sub { plugin::console_output('[test_plugin] Session 1 Stopped'); },
      shutdown        => sub
      {
        $_[KERNEL]->alarm_remove_all();
        plugin::console_output('[test_plugin] Session 1 Shutdown');
      },
      tick => sub
      {
        plugin::console_output('[test_plugin] Session 1 Tick');
        $_[KERNEL]->delay( tick => 5 );
      },
    }
  );
  
  
  # Session with an alias
  POE::Session->create
  (
    inline_states =>
    {
      _start          => sub
      {
        plugin::console_output('[test_plugin] Session 2 Started');
        $_[KERNEL]->alias_set('test_plugin-session-2');
      },
      _stop           => sub { plugin::console_output('[test_plugin] Session 2 Stopped'); },
      shutdown        => sub
      {
        plugin::console_output('[test_plugin] Session 2 Shutdown');
        $_[KERNEL]->alias_remove('test_plugin-session-2');
      },
    }
  );
}

1;