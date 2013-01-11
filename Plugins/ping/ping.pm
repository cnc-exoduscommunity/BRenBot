#
# Ping Plugin for BRenBot 1.x
# This plugin replaces the pingresponse module in BRenBot 1.53.11 and earlier
#
package ping;

use POE;
use plugin;
use strict;

# --------------------------------------------------------------------------------------------------

our %additional_events =
(
  # !commands
  "ping" => "ping",
);

# plugin_name and config are automatically populated by BRenBot
our $plugin_name;
our %config;

# --------------------------------------------------------------------------------------------------
# Event Handlers

# Runs when BRenBot loads the plugin
sub start
{}

# Runs when the plugin is unloaded
sub stop
{}

# Runs when a !command specified in the .xml file is typed
sub command
{
  my %args = %{$_[ ARG0 ]};
  
  if ( $args{'command'} eq 'ping' )
    { $_[KERNEL]->yield('ping' => \%args); }
}

# Runs when any text is typed ingame or in IRC
sub text
{
  my %args = %{$_[ ARG0 ]};
  
  return if ( $config{'chat_response'} != '1' or $args{'nicktype'} != 0 );
  
  if ( $args{'message'} =~ m/\blag.*\b|\bl+a+g+\b|\bping\b|\b56k\b|\bteleport.*\b|\bwarp.*\b/i and $args{'message'} !~ m/\!ping/i )
    { report_own_ping($args{'id'}); }
}

# --------------------------------------------------------------------------------------------------
# Commands

sub ping
{
  my %args = %{$_[ ARG0 ]};
  
  # If used from IRC check there is a name given
  if ( !$args{'arg1'} && $args{'nicktype'} != 0 )
  {
    my $syntax = $args{'settings'}->{'syntax'}->{'value'};
    plugin::ircmsg ( "You must specify which player to get the ping for. Usage: $syntax", $args{'ircChannelCode'} );
    return;
  }
  
  if ( !$args{'arg1'} )
    { report_own_ping($args{'id'}); }
    
  else
  {
    my ($searchName,$message) = ($args{'arg1'},"");
    
    my ( $result, %player ) = playerData::getPlayerData( $searchName );
    if ( $result == 1 )     { $message = "$player{name} has a ping of $player{ping}."; }
    elsif ( $result == 2 )  { $message = "$searchName is not unique, please be more specific."; }
    else                    { $message = "$searchName was not found in the server."; }
    
    if ( $args{'nicktype'} == 0 )
      { plugin::pagePlayer ( $player{'id'}, 'Your ping is currently '.$player{'ping'} ); }
    else
      { plugin::::ircmsg ( $message, $args{'ircChannelCode'} ); }
  }
}

# --------------------------------------------------------------------------------------------------
# Misc. Commands

sub report_ping
{
  my $player_id = shift;
  
  my ( $result, %player ) = playerData::getPlayerData ( $player_id );
  if ( $result == 1 )
    { plugin::pagePlayer ( $player{'id'}, 'Your ping is currently '.$player{'ping'} ); }
}

1;