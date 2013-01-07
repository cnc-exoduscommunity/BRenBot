#
# Test Plugin for BRenBot 1.x
# This plugin is used to test the BRenBot plugin interface is working correctly
#
package test-plugin;

use POE;
use plugin;
use strict;

# --------------------------------------------------------------------------------------------------

our %additional_events =
(
  # !commands
  "test-plugin" => "test-plugin",
);

# plugin_name and config are automatically populated by BRenBot
our $plugin_name;
our %config;

# --------------------------------------------------------------------------------------------------
# Event Handlers

# Runs when BRenBot loads the plugin
sub start
{
  plugin::console_output ( '[TEST-PLUGIN] Started' );
}

# Runs when the plugin is unloaded
sub stop
{
  plugin::console_output ( '[TEST-PLUGIN] Stopped' );
}

# Runs when a !command specified in the .xml file is typed
sub command
{
  my %args = %{$_[ ARG0 ]};
  plugin::console_output ( '[TEST-PLUGIN] Command' );
  
  if ( $args{'command'} eq 'show_commands' )
    { $_[KERNEL]->yield('show_commands' => \%args); }
}

# Runs when any text is typed ingame or in IRC
sub text
{
  my %args = %{$_[ ARG0 ]};
  plugin::console_output ( '[TEST-PLUGIN] Text ('.$args{'nick'}.': '.$args{'message'} );
}

# --------------------------------------------------------------------------------------------------
# Commands

sub test-plugin
{
  plugin::console_output('[TEST-PLUGIN] command called by ' . $args{'nick'});
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
        plugin::console_output('[TEST-PLUGIN] Session 1 Started');
        $_[KERNEL->yield('tick');
      },
      _stop           => sub { plugin::console_output('[TEST-PLUGIN] Session 1 Stopped'); },
      shutdown        => sub { plugin::console_output('[TEST-PLUGIN] Session 1 Shutdown'); },
      tick => sub
      {
        plugin::console_output('[TEST-PLUGIN] Session 1 Tick');
        $_[KERNEL]->alarm( tick => $_[HEAP]->{next_alarm_time} );
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
        plugin::console_output('[TEST-PLUGIN] Session 2 Started');
        $_[KERNEL->alias_add('test-plugin-session-2');
      },
      _stop           => sub { plugin::console_output('[TEST-PLUGIN] Session 2 Stopped'); },
      shutdown        => sub
      {
        plugin::console_output('[TEST-PLUGIN] Session 2 Shutdown');
        $_[KERNEL->alias_remove('test-plugin-session-2');
      },
    }
  );
}