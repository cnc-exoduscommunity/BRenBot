#**
# This plugin is a major overhaul of the original custom commands plugin that has been available for
# BRenBot for several years now. It provides a much more comprehensive way to implement macro based
# custom commands which can use the full range of BRenBots functionality, rather than being limited
# to sending host messages to the server.
#
# \author Daniel Paul (danpaul88@yahoo.co.uk)
# \version 2.0
#*

package custom_commands;

use POE;
use plugin;

my $currentVersion = '2.00';
my $loaded_ok = undef;

# Check bot compatibility
if ( !defined(plugin::getBrVersion) || plugin::getBrVersion() < 1.54
  || (plugin::getBrVersion() == 1.54 && plugin::getBrBuild() < 1 ) )
{
  print " == Custom Commands Plugin Error ==\n"
      . "This version of the plugin is not compatible with BRenBot versions older than 1.54.1\n";
  return 0;
}

# --------------------------------------------------------------------------------------------------

# BRenBot supplies these on plugin startup
our $plugin_name;
our %config;

# Define additional events in the POE session
our %additional_events = ();




# --------------------------------------------------------------------------------------------------
##
#### Bot Events
##
# --------------------------------------------------------------------------------------------------

sub start
{
  # Set our current version in the globals table
  plugin::set_global('version_plugin_custom_commands', $currentVersion);

  return ($loaded_ok = 1);
}

sub stop
{
}




# --------------------------------------------------------------------------------------------------
##
#### Game Events
##
# --------------------------------------------------------------------------------------------------

sub command
{
  return if ($loaded_ok == 0);

  my %args = %{$_[ARG0]};

  # Check if the command requires a target and abort if it does and none is found
  my %target = get_target(@_);
  return if !defined(%target);

  # Todo: check minimum arguments

  # Process each action for this command
  my @actions = get_command_actions(@_);
  foreach (@actions)
  {
    process_command_action($_, $args{'nick'}, \%target, $args{'arg'});
  }
}




# --------------------------------------------------------------------------------------------------
##
#### Utility Functions
##
# --------------------------------------------------------------------------------------------------

# Checks if a target is required for this command and, if so, determines who that should be. Returns
# an empty hash if no target is required, undef if a target is required but none was found or the
# player hash of the target if a target is required and one was found.
sub get_target()
{
  my %args = %{$_[ARG0]};

  return () if (1 != $args{'settings'}->{'requiresTarget'});

  # Figure out who the target should be
  my $target = $args{'arg1'};
  if (!$target and 1 == $args{'settings'}->{'defaultSelfTarget'} and 0 == $args{'nicktype'})
  {
    $target = $args{'nick'};
  }

  # Check the target exists in the server
  my ($result, %targetdata) = plugin::getPlayerData();
  return %targetdata if (1 == $result);

  if (0 == $args{'nicktype'})
  {
    plugin::pagePlayer($donator_id, 'BRenBot', 'Donations are not allowed on '.plugin::get_map()." in the first $donatelimit minutes. You have to wait $remaining more minutes" );
  }

  # Show error message
  my $message = $target.' was not found in the server or is not unique';
  if (0 == $args{'nicktype'})
    { plugin::pagePlayer( $args{'nick'}, 'BRenBot', $syntax ); }
  elsif (1 == $args{'nicktype'})
    { plugin::ircmsg( $syntax, $args{'ircChannelCode'} ); }

  return undef;
}

# Get an array of actions to be performed by the command
sub get_command_actions()
{
  my %args = %{$_[ARG0]};

  return () if !defined($args{'settings'}->{'action'});

  my @actions;
  for (split /^/, $args{'settings'}->{'action'})
  {
    push @actions, $_ if ($_ =~ m/^\!/i);
  }

  return @actions;
}

sub process_command_action()
{
  my $command = shift;
  my $user    = shift;
  my $target  = shift;
  my $args    = shift;

  # todo: parse macros

  plugin::call_command($command, $user);
}


# Plugin loaded OK
1;
