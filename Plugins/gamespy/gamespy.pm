#**
# The gamespy plugin for BRenBot 1.54 and newer, this contains all the functionality of the gamespy
# broadcast system that existed in BRenBot prior to version 1.54.1 plus some additional new features
#
# \author Daniel Paul (danpaul88@yahoo.co.uk)
# \version 1.0
#*

package gamespy;

use POE;
use IO::Socket;
use plugin;

my $currentVersion = '1.0';
my $loaded_ok = undef;

# Check bot compatibility
if ( !defined(plugin::getBrVersion) || plugin::getBrVersion() < 1.54
  || (plugin::getBrVersion() == 1.54 && plugin::getBrBuild() < 1 ) )
{
  print " == GameSpy Plugin Error ==\n"
      . "This version of the plugin is not compatible with BRenBot versions older than 1.54.1\n";
  return 0;
}

# --------------------------------------------------------------------------------------------------

# BRenBot supplies these on plugin startup
our $plugin_name;
our %config;

# Define additional events in the POE session
our %additional_events = ();

my $queryid = 10;
my @flood;
my @bans;




# --------------------------------------------------------------------------------------------------
##
#### Bot Events
##
# --------------------------------------------------------------------------------------------------

sub start
{
  return ($loaded_ok = 0) if (1 != load_config());

  # Set our current version in the globals table
  plugin::set_global ( "version_plugin_gamespy", $currentVersion );
  
  # Create UDP query server session
  POE::Session->create
  (
    inline_states =>
    {
      _start          => \&query_server_start,
      _stop           => \&query_server_stop,
      shutdown        => \&query_server_stop,
      select_read     => \&query_server_receive,
      socket_error    => \&query_server_error
    },
    options => {debug => 1},
  );

  foreach (@{$config{'master_servers'}})
  {
    # Create a master server session
    POE::Session->create
    (
      inline_states =>
      {
        _start          => \&master_heartbeat_start,
        _stop           => \&master_heartbeat_stop,
        shutdown        => \&master_heartbeat_stop,
        select_read     => sub {my $message; recv($_[HEAP]->{'socket_handle'}, $message, 1024, 0)},
        send_datagram   => \&master_heartbeat_send,
      },
      args    => [$_->{'ip'}, $_->{'port'}],
      options => {debug => 1},
    );
  }

  return ($loaded_ok = 1);
}

sub stop
{
}




# --------------------------------------------------------------------------------------------------
##
#### Query Server Events
##
# --------------------------------------------------------------------------------------------------

sub query_server_start
{
  my ($kernel, $heap) = @_[KERNEL, HEAP, ARG0];

  if (defined ($heap->{'socket_handle'} = IO::Socket::INET->new(Proto => 'udp', LocalPort => $config{'query_port'})))
  {
    $kernel->select_read($heap->{'socket_handle'}, 'select_read');
    plugin::console_output('[GSA] Opened gamespy query port '.$config{'query_port'});
  }
  else
  {
    plugin::console_output('[GSA] Failed to open query port '.$config{'query_port'}.'. Error: '.$!);
  }
}

# --------------------------------------------------------------------------------------------------

sub query_server_stop
{
  $_[KERNEL]->alarm_remove_all();
  if (defined($_[HEAP]->{'socket_handle'}))
  {
    $_[KERNEL]->select_read($_[HEAP]->{'socket_handle'});
    undef $_[HEAP]->{'socket_handle'};
    delete $_[HEAP]->{'socket_handle'};
  }
}

# --------------------------------------------------------------------------------------------------

sub query_server_receive
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  my $remote_socket = recv($heap->{'socket_handle'}, my $message = '', 2048, 0);
  if (defined $remote_socket)
  {
    return if is_banned_for_flooding($remote_socket);

    my $reply = undef;
    $reply = generate_basic() if ($message eq "\\basic\\");
    $reply = generate_info() if ($message eq "\\info\\");
    $reply = generate_rules() if ($message eq "\\rules\\");
    $reply = "\\echo\\$1" if ($message =~ m/\\echo\\(.+)/);

    if (defined $reply)
    {
      $reply .= "\\final\\\\queryid\\".(++$queryid).".1";
      send ($heap->{'socket_handle'}, $reply, 0, $remote_socket);
    }

    # For the players and status queries we output a list of players ingame
    if ($message eq "\\players\\" || $message eq "\\status\\")
    {
      ++$queryid;
      my $index = 1;
      if ($message eq "\\status\\")
      {
        $reply = generate_basic().generate_info().generate_rules(). "\\queryid\\".($queryid).'.'.$index++;
        send ($heap->{'socket_handle'}, $reply, 0, $remote_socket);
      }

      generate_players($heap->{'socket_handle'}, $remote_socket, $queryid, $index);
    }
  }
}

# --------------------------------------------------------------------------------------------------

sub query_server_error
{
  my ($heap, $operation, $errnum, $errstr) = @_[HEAP, ARG0, ARG1, ARG2];

  warn "[GSA] ERROR: Could not start gamespy udp server: $operation error $errnum: $errstr\n";
  $_[KERNEL]->post($_[SESSION], 'shutdown');
}




# --------------------------------------------------------------------------------------------------
##
#### Master Server Events
##
# --------------------------------------------------------------------------------------------------

sub master_heartbeat_start
{
  my ($kernel, $heap, $server_addr, $server_port) = @_[KERNEL, HEAP, ARG0, ARG1];

  if (!defined ($heap->{'socket_handle'} = IO::Socket::INET->new(Proto => 'udp')))
  {
    plugin::console_output('[GSA] Error: Unable to create heartbeat socket...');
    return;
  }

  my $server_ip = inet_aton($server_addr);
  if (!$server_ip)
  {
     plugin::console_output('[GSA] Error: Unable to resolve hostname '.$server_addr.'...');
     return;
  }

  plugin::console_output('[GSA] Broadcasting to master server '.$server_addr.':'.$server_port);
  $heap->{'server_endpoint'} = pack_sockaddr_in($server_port, $server_ip);
  $kernel->yield('send_datagram');
  $kernel->select_read($heap->{'socket_handle'}, 'select_read');
}

# --------------------------------------------------------------------------------------------------

sub master_heartbeat_stop
{
  $_[KERNEL]->alarm_remove_all();
  if (defined($_[HEAP]->{'socket_handle'}))
  {
    if (defined($_[HEAP]->{'server_endpoint'}))
    {
      my $heartbeat = "\\heartbeat\\".$config{'query_port'}."\\gamename\\ccrenegade\\statechanged\\2";
      send($_[HEAP]->{'socket_handle'}, $heartbeat, 0, $_[HEAP]->{'server_endpoint'});
    }

    $_[KERNEL]->select_read($_[HEAP]->{'socket_handle'});
    undef $_[HEAP]->{'socket_handle'};
    delete $_[HEAP]->{'socket_handle'};
  }
}

# --------------------------------------------------------------------------------------------------

sub master_heartbeat_send
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];
  
  if (defined($heap->{'socket_handle'}))
  {
    my $heartbeat = "\\heartbeat\\".$config{'query_port'}."\\gamename\\ccrenegade";

    send($heap->{'socket_handle'}, $heartbeat, 0, $heap->{'server_endpoint'});
    $kernel->delay('send_datagram', 300);
  }
}




# --------------------------------------------------------------------------------------------------
##
#### Packet generation functions
##
# --------------------------------------------------------------------------------------------------

sub generate_basic
{
  return "\\gamename\\ccrenegade\\gamever\\838";
}

sub generate_info
{
  my $string;
  my $maxplayers = plugin::server_get_max_players();
  my $numplayers = plugin::server_get_current_players();

  $string .= "\\hostname\\" . plugin::server_get_name();
  $string .= "\\hostport\\" . plugin::server_get_gameport();
  
  my $map = plugin::get_map();
  $map =~ s/\.mix//g;
  $string .= "\\mapname\\" . $map;
  
  $string .= "\\gametype\\C&C";
  $string .= "\\numplayers\\" . $numplayers;
  $string .= "\\maxplayers\\" . $maxplayers;

  return $string;
}

sub generate_rules
{
  my $string;

# $string .= "\\BW\\1000000";
  $string .= "\\CSVR\\1";
  $string .= "\\DED\\1";
  $string .= "\\password\\" . plugin::server_has_password();
  $string .= "\\DG\\" . plugin::server_enforces_driver_gunner();
  $string .= "\\TC\\" . plugin::server_allows_team_changing();
  $string .= "\\FF\\" . plugin::server_allows_friendly_fire();
  $string .= "\\SC\\" . plugin::server_get_starting_credits();
  $string .= "\\SSC\\brenbot" . plugin::getBrVersion().'.'.plugin::getBrBuild();
  $string .= "\\timeleft\\" . plugin::match_get_time_remaining();

  foreach (@{$config{'custom_info'}})
  {
    $string .= "\\".$_->{'key'}."\\".$_->{'value'};
  }

  return $string;
}

sub generate_players
{
  my ($handle, $socket, $queryid, $index) = @_[0, 1, 2, 3];

  my %playerList = plugin::get_playerlist();
  my $numPlayers = scalar(keys %playerList);

  my $i = 0;
  my $string = "";
  while (my ($id, $player) = each(%playerlist))
  {
    $string .= "\\player_$i\\$player->{'name'}\\score_$i\\$player->{'score'}\\ping_$i\\$player->{'ping'}\\team_$i\\$player->{'side'}";
    if (0 == (++$i%20) and $i < $numPlayers)
    {
      $string .= "\\queryid\\".$queryid.'.'.$index++;
      send($handle, $string, 0, $socket);
      $string = "";
    }
  }

  send ($handle, $string."\\final\\\\queryid\\".$queryid .'.'.$index, 0, $socket);
}




# --------------------------------------------------------------------------------------------------
##
#### Utility functions
##
# --------------------------------------------------------------------------------------------------

# Checks the plugin configuration settings are valid
sub load_config
{
  if (!defined($config{'query_port'}) || $config{'query_port'} !~ m/^\d+$/)
  {
    plugin::console_output('[GSA] Config Error: Query port not defined or not numeric');
    return 0;
  }

  # We want to ensure $config always contains an array, regardless of how many entries there are
  my $rawMasterServers = $config{'master_servers'};
  $config{'master_servers'} = ();

  if (defined($rawMasterServers))
  {
    $rawMasterServers = [$rawMasterServers] if (ref $rawMasterServers ne 'ARRAY');

    foreach (@{$rawMasterServers})
    {
      $server = load_config_parse_master_server($_);
      push(@{$config{'master_servers'}}, $server) if defined $server;
    }
  }

  # We want to ensure $config always contains an array, regardless of how many entries there are
  my $rawCustomInfo = $config{'custom_info'};
  $config{'custom_info'} = ();

  if (defined($rawCustomInfo))
  {
    $rawCustomInfo = [$rawCustomInfo] if (ref $rawCustomInfo ne 'ARRAY');

    foreach (@{$rawCustomInfo})
    {
      $customInfo = load_config_parse_custom_info($_);
      push(@{$config{'custom_info'}}, $customInfo) if defined $customInfo;
    }
  }
  
  return 1;
}

# Checks a master server entry is correctly formed in the configuration and parses it from IP:Port
# into a hash of {ip=>ip,port=>port}
sub load_config_parse_master_server
{
  my $config_entry = shift;

  my $delimIdx = index($config_entry, ':');
  if (-1 == $delimIdx)
  {
    plugin::console_output('[GSA] Config Warning: Ignoring badly formed master server entry '.$config_entry);
    return undef;
  }

  my $masterServer = {
    'ip'    => substr($config_entry,0,$delimIdx),
    'port'  => substr($config_entry,$delimIdx+1)
  };

  if ($masterServer->{'port'} !~ m/^\d+$/)
  {
    plugin::console_output('[GSA] Config Warning: Ignoring master server entry '.$config_entry.' due to non-numeric port number');
    return undef;
  }

  return $masterServer;
}

sub load_config_parse_custom_info
{
  my $config_entry = shift;

  if ($config_entry =~ m/^([a-z0-9_]+)\s*=\s*(.+)$/i)
  {
    my $value = $2;
    $value =~ s!\\!/!g; # Replace any instances of \ with / since \ is the GSA protocol delimiter
    return {'key' => $1, 'value' => $value};
  }

  plugin::console_output('[GSA] Config Warning: Ignoring badly formed custom info entry '.$config_entry);
  return undef;
}

# Checks if a specified remote endpoint has been banned for flooding the server with queries
sub is_banned_for_flooding
{
  my ($remote_port, $remote_addr) = unpack_sockaddr_in(shift);

  # Check if the remote address is already banned
  foreach (@bans)
  {
    return 1 if ($_ eq $remote_addr);
  }

  # Clean up old entries in the flood protection array
  while ( (scalar(@flood) > 0) && ($flood[0]{'timestamp'} < (time() - 30)) )
    { shift(@flood); }

  # Check to see if we should ban them for flooding
  push (@flood, {'ip' => $remote_addr, 'timestamp' => time()});

  my $count=0;
  foreach (@flood)
  {
    if ($_->{'ip'} eq $remote_addr and ++$count >= 50)
    {
      push (@bans, $remote_addr);
      plugin::console_output('[GSA] Banned '.inet_ntoa($remote_addr).' for flooding the query handler');
      return 1;
    }
  }

  return 0;
}


# Plugin loaded OK
1;