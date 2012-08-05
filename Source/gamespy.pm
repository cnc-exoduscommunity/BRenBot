#!/usr/bin/perl

package gamespy;
use strict;

use POE qw/Wheel::FollowTail/;
use POE::Component::Server::TCP;
use IO::Socket;

use renlog;
use modules;

sub DATAGRAM_MAXLEN () { 1024 }

my $port;
my $query_port;
my $queryid = 10;

my @flood;
my @bans;

$| = 1;


# udp server for gamespy query port emulation
sub init
{
	$query_port = $brconfig::config_gamespyqueryport;
	$port = $brconfig::config_gamespy_gameport;

	if (!$query_port)
	{
		modules::console_output ( "[GSA] ERROR: No Gamespy Query Port defined, unable to broadcast to GSA network!" );
		modules::set_module ( "gamespy_players", -1 );
		return;
	}

	if (!$port)
	{
		modules::console_output ( "[GSA] ERROR: No WOL or GSA gameport found in server.ini, unable to broadcast to GSA network!" );
		modules::set_module ( "gamespy_players", -1 );
		return;
	}

  my $ip;
	if ( $brconfig::config_gamespy_ip )
	{
		$ip = $brconfig::config_gamespy_ip;
	}
	else
	{
		$ip = modules::get_ip();
	}

	if (!$ip)
	{
		modules::console_output ( "[GSA] ERROR: Unable to detect server IP, set Gamespy_IP = <server ip> in brenbot.cfg!" );
		modules::set_module ( "gamespy_players", -1 );
		return;
	}
  
  # \todo Is this IP actually used anywhere? Doesn't seem to be... possibly redundant?


	# Create UDP server socket and session to respond to user queries
	POE::Session->create
	(
		inline_states =>
		{
			_start          => \&udp_server_start,
			_stop           => \&udp_server_stop,
			select_read     => \&udp_server_receive,
			socket_made     => \&udp_server_socket,
			socket_error    => \&udp_server_error,
		},
		args => [ $query_port ],
		options => { debug => 1 },
	);

	# Broadcast to GSA? If so, create sockets and sessions to broadcast
	# server information to GSA server listings
	if ($brconfig::config_broadcast_to_gamespy == 1)
	{
		POE::Session->create
		(
			inline_states =>
			{
				_start            => \&udp_heartbeat_start_gsa,
				_stop             => \&udp_heartbeat_stop,
				select_read       => \&udp_heartbeat_receive,
				send_datagram     => \&udp_heartbeat_send,
			},
			args => [ 'master.gamespy.com', 27900 ],
			options => { debug => 1 },
		);
	}

	modules::set_module ( "gamespy_players", 1 );
}

sub shutdown
{
	$poe_kernel->post( 'gsa_udp_server', '_stop' );
	$poe_kernel->post( 'gsa_heartbeat', '_stop' );
	modules::set_module ( "gamespy_players", 0 );
}


sub generate_basic
{
	return "\\gamename\\ccrenegade\\gamever\\838";
}

sub generate_info
{
	my $string;
	my $maxplayers = serverStatus::getMaxPlayers();
	my $numplayers = serverStatus::getCurrentPlayers();
	my $reserved_slots = $brconfig::config_reserved_slots;

	if ($brconfig::config_reserved==1)
	{
		my $adjustment=0;
		if ($numplayers > ($maxplayers - $brconfig::config_reserved_slots))
		{
			# already over normal limit!
			$adjustment = $numplayers - ($maxplayers - $brconfig::config_reserved_slots);
			my $test = $maxplayers - $brconfig::config_reserved_slots + $renlog::used_slots + $adjustment;
		}
		$maxplayers = ($maxplayers - $brconfig::config_reserved_slots + $renlog::used_slots) + $adjustment;
	}

	if ($brconfig::config_redirect==1)
	{
		if ( ($numplayers >= 20) && ($maxplayers > 0) )
		{
			# okay, lets redirect to our second server
			$maxplayers++;
			$port = $brconfig::config_redirect_port;
		}
	}

	$string .= "\\hostname\\" . serverStatus::getGameTitle();
	$string .= "\\hostport\\" . $port;
	if ( serverStatus::getMap() )
	{
		$string .= "\\mapname\\" . serverStatus::getMap();
	}
	else
	{
		$string .= "\\mapname\\" . serverStatus::getStartMap();
	}
	$string =~ s/\.mix//g;
	$string .= "\\gametype\\C&C";
	$string .= "\\numplayers\\" . $numplayers;
	$string .= "\\maxplayers\\" . $maxplayers;

	return $string;
}

sub generate_rules
{
	my $string;

#	$string .= "\\BW\\1000000";
	$string .= "\\CSVR\\1";
	$string .= "\\DED\\1";
	$string .= "\\password\\" . serverStatus::getIsPassworded();
	$string .= "\\DG\\" . $brconfig::server_rules{'driver_gunner'};
	$string .= "\\TC\\" . $brconfig::server_rules{'team_changing'};
	$string .= "\\FF\\" . $brconfig::server_rules{'friendly_fire'};
	$string .= "\\SC\\" . $brconfig::server_rules{'credits'};
	$string .= "\\SSC\\brenbot" . main::BR_VERSION;
	$string .= ( length($brconfig::config_gamespy_broadcast_website) > 0 ) ? "\\Website\\" . $brconfig::config_gamespy_broadcast_website : '';
	$string .= ( length($brconfig::config_gamespy_broadcast_irc) > 0 ) ? "\\IRC\\" . $brconfig::config_gamespy_broadcast_irc : '';
	$string .= ( length($brconfig::config_gamespy_broadcast_teamspeak) > 0 ) ? "\\Teamspeak\\" . $brconfig::config_gamespy_broadcast_teamspeak : '';
	$string .= ( length($brconfig::config_gamespy_broadcast_ventrilo) > 0 ) ? "\\Ventrilo\\" . $brconfig::config_gamespy_broadcast_ventrilo : '';
	$string .= "\\timeleft\\" . serverStatus::getTime();
	return $string;
}

sub generate_players
{
	my ( $handle, $socket, $query, $index ) = @_[ 0, 1, 2, 3 ];

	my $string;

	if ( serverStatus::getCurrentPlayers() > 0 )
	{
		my $maxplayers = serverStatus::getMaxPlayers();

		my $i = 0;			my $j = 0;
		my %playerData = playerData::getPlayerList();
		while ( my ( $id, $player ) = each ( %playerData ) )
		{
			$string .= "\\player_$i\\$player->{'name'}\\score_$i\\$player->{'score'}\\ping_$i\\$player->{'ping'}\\team_$i\\$player->{'side'}";
			if ($j == 19)
			{
				if (($i+1) < $maxplayers)
				{
					$string .= "\\queryid\\" . $query . "." . $index;
					send ( $handle, $string, 0, $socket );
					$index++;
					$string = "";
					$j = 0;
				}
			}

			# Increment counters
			$i++;		$j++;
		} # end of while
	} # end of if player count > 0
	$string .= "\\final\\\\queryid\\" . $query . "." . $index;
	send ($handle, $string, 0, $socket);
}

sub udp_server_start
{
	my ($kernel, $heap, $port) = @_[KERNEL, HEAP, ARG0];

	$kernel->alias_set("gsa_udp_server");
	if (defined ($heap->{socket_handle} = IO::Socket::INET->new( Proto => 'udp', LocalPort => $port )))
	{
		$kernel->select_read($heap->{socket_handle}, 'select_read');
		modules::console_output ( "[GSA] Opening gamespy query port $port..." );
	}
	else
	{
		warn "port: " . $port . ", server: error " . ($!+0) . " creating socket: " . $! . "\n";
	}
}

#------------------------------------------------------------------------------

sub udp_server_stop
{
	delete $_[HEAP]->{socket_handle};
}

#------------------------------------------------------------------------------

sub udp_server_receive
{
	my ($kernel, $heap, $socket) = @_[KERNEL, HEAP, ARG0];

	my $remote_socket = recv( $heap->{socket_handle}, my $message = '', 2048, 0 );
	if (defined $remote_socket)
	{
		my ($remote_port, $remote_addr) = unpack_sockaddr_in($remote_socket);
		my $human_addr = inet_ntoa($remote_addr);
		my $reply;

		# Clean up old entries in the flood protection array
		while ( (scalar(@flood) > 0) && ($flood[0]{'timestamp'} < (time() - 30)) )
			{ shift(@flood); }

		# Check if sender is banned / should ban them
		my %hash;
		$hash{'ip'}        = "$human_addr:$remote_port";
		$hash{'timestamp'} = time();
		push (@flood, \%hash);
		my $count=0;

		foreach (@bans)
		{
			return if ($_ eq $human_addr);
		}

		foreach (@flood)
		{
			if ( ($_->{ip} eq "$human_addr:$remote_port") && ($_->{timestamp} >= time()-30 ) )
				{ $count++; }
		}

		if ($count >= 50)
		{
			push (@bans, $human_addr);
			modules::console_output ( "[GSA] Banned $human_addr:$remote_port for flooding the BRenBot GSA Query handler" );
			return;
		}
		$queryid++;

		if ($message eq "\\basic\\")
		{
			$reply = generate_basic();
			$reply .= "\\final\\\\queryid\\" . $queryid . ".1";
			send ($heap->{socket_handle}, $reply, 0, $remote_socket);
		}
		if ($message eq "\\info\\")
		{
			$reply = generate_info();
			$reply .= "\\final\\\\queryid\\" . $queryid . ".1";
			send ($heap->{socket_handle}, $reply, 0, $remote_socket);
		}
		if ($message eq "\\rules\\")
		{
			$reply = generate_rules();
			$reply .= "\\final\\\\queryid\\" . $queryid . ".1";
			send ($heap->{socket_handle}, $reply, 0, $remote_socket);
		}
		if ($message eq "\\players\\")
		{
			generate_players($heap->{socket_handle}, $remote_socket, $queryid, 1);
		}
		if ($message eq "\\status\\")
		{
			$reply = generate_basic();
			$reply .= generate_info();
			$reply .= generate_rules();
			$reply .= "\\queryid\\" . $queryid . ".1";
			send ($heap->{socket_handle}, $reply, 0, $remote_socket);

			generate_players($heap->{socket_handle}, $remote_socket, $queryid, 2);
		}

		if ($message =~ m/\\echo\\(.+)/)
		{
			$reply = "\\echo\\$1";
			$reply .= "\\final\\\\queryid\\" . $queryid . ".1";
			send ($heap->{socket_handle}, "$reply", 0, $remote_socket);
		}
	}
}

#------------------------------------------------------------------------------

sub udp_server_error
{
	my ($heap, $operation, $errnum, $errstr) = @_[HEAP, ARG0, ARG1, ARG2];

	warn "ERROR: Could not start gamespy udp server: $operation error $errnum: $errstr\n";
	delete $heap->{socket_handle};
}

#------------------------------------------------------------------------------

sub udp_heartbeat_start_gsa
{
	my ($kernel, $heap, $server_addr, $server_port) = @_[KERNEL, HEAP, ARG0, ARG1];

	$kernel->alias_set("gsa_heartbeat");
	my $socket = IO::Socket::INET->new( Proto => 'udp' );

	if (defined $socket)
	{
		modules::console_output ( "[GSA] Broadcasting on $server_addr:$server_port" );
		$heap->{socket_handle} = $socket;
		$heap->{server_ip} = inet_aton($server_addr);
		if ( $heap->{server_ip} )
		{
			$heap->{server} = pack_sockaddr_in($server_port, $heap->{server_ip});
			$kernel->yield('send_datagram');
			$kernel->select_read($socket, 'select_read');
		}
		else
			{ modules::console_output ( "[GSA] Error: Unable to resolve hostname ".$server_addr."..." ); }
	}
	else
		{ modules::console_output ( "[GSA] Error: Unable to create heartbeat socket..." ); }
}

#------------------------------------------------------------------------------

sub udp_heartbeat_stop
{
	my ($kernel, $heap) = @_[KERNEL, HEAP];
	my $heartbeat = "\\heartbeat\\$query_port\\gamename\\ccrenegade\\statechanged\\2";

	send( $heap->{socket_handle}, "$heartbeat", 0, $heap->{server} );
	delete $heap->{socket_handle};
}

#------------------------------------------------------------------------------

sub udp_heartbeat_send
{
	my ($kernel, $heap) = @_[KERNEL, HEAP];
	my $heartbeat = "\\heartbeat\\$query_port\\gamename\\ccrenegade";

	send( $heap->{socket_handle}, "$heartbeat", 0, $heap->{server} );
	$kernel->delay( 'send_datagram', 300 );
}

#------------------------------------------------------------------------------

sub udp_heartbeat_receive
{
	my ($kernel, $heap, $socket) = @_[KERNEL, HEAP, ARG0];
	my $message = '';
	my $remote_socket = recv( $heap->{socket_handle}, $message, DATAGRAM_MAXLEN, 0 );

	if (defined $remote_socket)
	{
		my ($remote_port, $remote_addr) = unpack_sockaddr_in($remote_socket);
		my $human_addr = inet_ntoa($remote_addr);
	}
}

#------------------------------------------------------------------------------

sub udp_heartbeat_error
{
	my ($heap, $operation, $errnum, $errstr) = @_[HEAP, ARG0, ARG1, ARG2];

	warn "Gamespy Heartbeat Error: $operation error $errnum: $errstr\n";
	delete $heap->{socket_handle};
}

#------------------------------------------------------------------------------

1;
