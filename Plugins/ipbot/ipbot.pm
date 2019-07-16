#
# IPDB plugin for BRenBot 1.52 by Daniel Paul
# Reports player IP's to the IPDB server, and allows IRC users to query the server
#
# Version 1.15
#
package ipbot;

use POE;
use IO::Socket;
use plugin;

# Define additional events in the POE session
our %additional_events = ( "ipsearch" => "ipsearch",	"nicksearch" => "nicksearch",
"commonnicksearch" => "commonnicksearch",	"ipbot_stats" => "ipbot_stats",
"scanPlayers" => "scanPlayers",		"reportPlayerData" => "reportPlayerData",
"ping" => "ping" );

# BRenBot automatically sets the plugin name and imports config
our $plugin_name;
our %config;

my $pluginVersion		= 1.15;
my $protocolVersion		= 1.300;

# Global plugin variables
my @messageQueue;			# Queue for outgoing messages
my $serverOnline		= 0;
my $unsupportedProtocol	= 0;




# Used by plugins to check the server status and returns 1 if the server is OK and we are
# using a supported protocol or 0 otherwise. Can also print failure messages to IRC if a
# channel code is provided as the parameter to the function.
sub checkServerStatus
{
	my $ircChannelCode = shift;

	if ( $serverOnline == 0 )
	{
		if ( defined($ircChannelCode) )
			{ plugin::ircmsg ( "The IPDB server is currently offline...", $ircChannelCode ); }
		return 0;
	}

	if ( $unsupportedProtocol == 1 )
	{
		if ( defined($ircChannelCode) )
			{ plugin::ircmsg ( "This plugin is using an unsupported version of the IPDB protocol and must be updated before you can continue using the IPDB service.", $ircChannelCode ); }
		return 0;
	}

	return 1;
}



######################
## Functions for !commands
######################

# Request an ip search in the ipbot db
sub ipsearch
{
	my ( $kernel, $args ) = @_[ KERNEL, ARG0 ];
	my %args = %{$args};

	return if ( !checkServerStatus($args{'ircChannelCode'}) );

	if ( $args{arg1} =~ m/^\d{1,3}(\.\d{1,3}?){0,3}$/i )
	{
		my $nickname = $args{'nick'};
		$nickname =~ s/\@IRC//gi;
		my $requestID = getRequestId ( $nickname );
		sendToServer ( "703 $requestID:$args{arg1}", $kernel );
	}
	elsif ( $args{arg1} )
	{
		plugin::ircmsg ( "$args{arg1} is not a valid IP address", $args{'ircChannelCode'} );
	}
	else
	{
		my $syntaxvalue = $args{settings}->{syntax}->{value};
		plugin::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
	}
}


# Request a nickname search in the ipdb db
sub nicksearch
{
	my ( $kernel, $args ) = @_[ KERNEL, ARG0 ];
	my %args = %{$args};

	return if ( !checkServerStatus($args{'ircChannelCode'}) );

	if ( $args{arg} =~ m/\!\S+\s(.+)/ )
	{
		my $searchString = $1;
		my $nickname = $args{'nick'};
		$nickname =~ s/\@IRC//gi;
		my $requestID = getRequestId ( $nickname );
		sendToServer ( "704 $requestID:$searchString", $kernel );
	}
	else
	{
		my $syntaxvalue = $args{settings}->{syntax}->{value};
		plugin::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
	}
}



# Request a common nicknames search in the ipdb db
sub commonnicksearch
{
	my ( $kernel, $args ) = @_[ KERNEL, ARG0 ];
	my %args = %{$args};

	return if ( !checkServerStatus($args{'ircChannelCode'}) );

	if ( $args{arg} =~ m/\!\S+\s(.+)/ )
	{
		my $searchString = $1;
		my $nickname = $args{'nick'};
		$nickname =~ s/\@IRC//gi;
		my $requestID = getRequestId ( $nickname );
		sendToServer ( "707 $requestID:$searchString", $kernel );
	}
	else
	{
		my $syntaxvalue = $args{settings}->{syntax}->{value};
		plugin::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} );
	}
}


# Request stats from the ipdb
sub ipbot_stats
{
	my ( $kernel, $args ) = @_[ KERNEL, ARG0 ];
	my %args = %{$args};

	return if ( !checkServerStatus($args{'ircChannelCode'}) );

	my $nickname = $args{'nick'};
	$nickname =~ s/\@IRC//gi;
	my $requestID = getRequestId ( $nickname );
	sendToServer ( "701 $requestID", $kernel );
}


########### Event handlers

sub start
{
	my $kernel = $_[ KERNEL ];

	# Set our current version in the globals table
	plugin::set_global ( "version_plugin_ipbot", $pluginVersion );

	# Schedule a scan of the playerlist, so we can report the players which are currently
	# online. Need to give BRenBot time to get the playerlist sorted out
	$kernel->alarm( scanPlayers => (int( time() ) + 5) );

	# Start ping loop
	$kernel->alarm( ping => (int( time() ) + 5) );


	# Start send / recieve loops ( Only actually do anything when the socket is active )
	# Connect to the ipdb server
	POE::Session->create
	( inline_states =>
		{
			_start => sub
			{
				$_[HEAP]->{'server'} = 'ipdb.danpaul88.co.uk';
				$_[HEAP]->{'port'} = 51988;
				$_[HEAP]->{'connected'} = 0;
				$_[KERNEL]->alias_set( 'ipdbserver' );
				$_[KERNEL]->yield( 'attempt_connect' );
			},


			# Attempt to connect to the IPDB server
			attempt_connect => sub
			{
				modules::console_output ( '[IPDB] Attempting to connect to IPDB Server... ', 1 );
 				$_[HEAP]->{'socket'} = IO::Socket::INET->new(
 					PeerAddr => $_[HEAP]->{'server'},
 					PeerPort => $_[HEAP]->{'port'},
 					Proto => 'tcp' );


 				if ( $_[HEAP]->{'socket'} && $_[HEAP]->{'socket'}->connected() )
 				{
	 				$serverOnline = 1;
 					$_[HEAP]->{'connected'} = 1;
 					modules::console_output ( 'Success!', 3 );
 					plugin::ircmsg ( "Connected to the IPDB server.", "A" );

 					# Send protocol details
 					sendToServer ( "100 1.3" );

 					# Send login details
 					sendToServer ( "600 ".$config{'ipdbUser'}.":".$config{'ipdbPass'} );

 					# Register client ID
 					sendToServer ( "601 BRenBot ".plugin::getBrVersion().".".plugin::getBrBuild()." (".$pluginVersion.")" );

 					# Subscribe to notifications
 					if ( $config{'enableNickSpooferWarnings'} != '0' )
 					{
	 					sendToServer ( "300 1" );
 					}

 					# Create wheel to recieve input
 					$_[HEAP]->{'wheel'} = new POE::Wheel::ReadWrite
					(
						Handle     => $_[HEAP]->{'socket'},
						InputEvent => 'data_recieved',
						ErrorEvent => 'connection_error'
				    );

 					# Start the send loop
 					$_[KERNEL]->yield( "send_data_loop" );
 				}
 				else
 				{
 					modules::console_output ( 'Failed! Will retry in 5 minutes.', 3 );
 					$_[KERNEL]->alarm ( "attempt_connect" => (time()+300) );
 				}
			},


			# Send data to the IPDB server, re-calls itself indefinitely while connected
			send_data_loop => sub
			{
				return if ( $_[HEAP]->{'connected'} != 1 );

				# Limit message length to 1024 characters
				my $availableChars = 1024;
				my $sendString = "";

				# Send at least one message
				if ( $messageQueue[0] )
				{
					my $output = shift @messageQueue;
					$sendString .= $output;
					$availableChars -= length ( $output );

					# Keep sending messages until we hit our chars per second limit
					while ( $messageQueue[0] && ( length($messageQueue[0]) < $availableChars ) )
					{
						$output = shift @messageQueue;
						$sendString .= $output;
						$availableChars -= length ( $output );
					}
				}

				# If there's anything to send then send it
				if ( $sendString ) { $_[HEAP]->{'socket'}->send( $sendString ); }

			    # Come back to the send loop in 1 second
			   $_[KERNEL]->delay ( "send_data_loop", 1 );
			},


			# Recieved data from the server
			data_recieved => sub
			{
				my $input = $_[ ARG0 ];

				#open ( IPBOTDEBUGFILE, '>>ipbotdebug.txt' );
				#print IPBOTDEBUGFILE "RECEIVE: $input\n";
				#close IPBOTDEBUGFILE;

				# Do something with input
				parseInput ( $input );
			},


			# An error has occured in $_[HEAP]->{wheel} which means the connection to the server
			# has failed. Shut down the wheel and socket and schedule a reconnection attempt.
			connection_error => sub
			{
				my ( $error, $errorCode, $errorString ) = @_[ ARG0, ARG1, ARG2 ];
				modules::console_output ( '[IPDB] An error has occured with the server connection, resetting socket...' );
				plugin::ircmsg ( "Lost connection to the IPDB server", "A" );

				#open ( IPBOTDEBUGFILE, '>>ipbotdebug.txt' );
				#print IPBOTDEBUGFILE "ERROR: $error\n";
				#close IPBOTDEBUGFILE;

				# Set connection status to 0
				$_[HEAP]->{'connected'} = 0;
				$serverOnline = 0;

				# Shutdown socket and wheel
				$_[HEAP]->{'wheel'}->shutdown_input();
				$_[HEAP]->{'wheel'}->shutdown_output();
				delete $_[HEAP]->{'wheel'};
				shutdown ( $_[HEAP]->{'socket'}, 2 );

				# Schedule reconnection attempt
				$_[KERNEL]->alarm ( "attempt_connect" => (time()+60) );
			}
		}
	);
}


sub stop
{}


# Command event - Triggers on any !command which is in this plugins XML file
sub command
{
	my ( $kernel, $args ) = @_[ KERNEL, ARG0 ];
	my %args = %{$args};

	# Trigger the event with the same name as the command
	$kernel->yield ( $args{'command'} => \%args );
}


# Playerjoin event
sub playerjoin
{
	my ( $kernel, $args ) = @_[ KERNEL, ARG0 ];
	my %args = %{$args};

	# Schedule them to be reported to the server in 3 seconds
	# Gives BRenBot time to get their IP
	$kernel->alarm( reportPlayerData => (int(time()) +3) => $args{'nick'} );
}



####################################
##
# Data Input
#
# Parsing data recieved back from the server
##
####################################

# Parses data recieved from the IPDB server via the socket
sub parseInput
{
	my $input = shift;

	if ( $input =~ m/^200/ )
		{ plugin::console_output ( "[IPDB] This plugin is using an old version of the IPDB protocol, please check for an update to enable full functionality." ); }
	elsif ( $input =~ m/^201/ )
	{
		plugin::console_output ( "[IPDB] This plugin is using an unsupported version of the IPDB protocol, please check for an update to continue using the IPDB service." );
		$unsupportedProtocol = 1;
	}

	elsif ( $input =~ m/^400\s(.+)/ )
		{ process_400($1); }


	elsif ( $input =~ m/^650/ )
		{ plugin::console_output ( "[IPDB] Login to IPDB was successful." ); }
	elsif ( $input =~ m/^651/ )
		{ plugin::console_output ( "[IPDB] Login to IPDB failed, login limit for username has been reached!" ); }
	elsif ( $input =~ m/^652/ )
		{ plugin::console_output ( "[IPDB] Login to IPDB failed, username or password was invalid!" ); }
	elsif ( $input =~ m/^653/ )
		{ process_653($1); }

	elsif ( $input =~ m/^721\s(.+)/ )
		{ process_721($1); }
	elsif ( $input =~ m/^723\s(.+)/ )
		{ process_723($1); }
	elsif ( $input =~ m/^724\s(.+)/ )
		{ process_724($1); }
	elsif ( $input =~ m/^727\s(.+)/ )
		{ process_727($1); }
}


# Process 400 input ( Nick spoofer warning notification )
# 400 numNicks:player				Notification that the specified player might be a nick spoofer
sub process_400
{
	my $input = shift;

	if ( $input =~ m/(\d+)\:(\S+)/ )
	{
		plugin::ircmsg ( "[IPDB] Warning: $2 has been linked to $1 different nicknames within the last week and *might* be a nickname spoofer.", 'A' );
	}
}


# Process 653 input ( Request denied )
# 653 reqID							Request denied: Attempted to use feature that requires login
sub process_653
{
	my $input = shift;

	if ( $input =~ m/(\d+)/ )
	{
		my $ircUser = getRequestIdOwner ( $1 );
		if ( $ircUser )
		{
			plugin::ircnotice ( $ircUser, "IPDB REQUEST DENIED. Please ensure you are using a valid username and password to connect to the IPDB." );
		}
	}
}


# Process 721 input ( Stats response )
# 721 reqID:records:names:ips		Stats Response
sub process_721
{
	my $input = shift;

	if ( $input =~ m/(\d+)\:(\d+)\:(\d+)\:(\d+)/ )
	{
		my $ircUser = getRequestIdOwner ( $1 );
		if ( $ircUser )
		{
			plugin::ircnotice ( $ircUser, "There are currently $2 records in the IPDB database, consisting of $3 unique nicknames and $4 unique IPs" );
		}
	}
}


# Process 723 input ( IP Search Result )
# 723 reqID:found:sending ip Tstmp:name\tTstmp:name\0ip Tstmp:name\tTstmp:name\0	ip search result
sub process_723
{
	my $input = shift;

	if ( $input =~ m/(\d+)\:(\d+)\:(\d+)\s(.+)/ )
	{
		my $ircUser = getRequestIdOwner ( $1 );
		if ( $ircUser )
		{
			plugin::ircnotice ( $ircUser, "Found $3 results for your search, showing first $2..." );

			my $results = $4;
			while ( $results =~ m/\s*(\S+)\s([^\]+)((.+))?/ )
			{
				$results = defined($4) ? $4 : "";;
				# 1 = ip
				# 2 = group of names / timestamps
				my $message = "07$1: ( ";

				my $names = $2;
				while ( $names =~ m/\s*(\d+)\:([^\t]+)(\t.+)?/ )
				{
					$names = defined($3) ? $3 : "";
					$message .= "$2 (".modules::get_past_date_time ( "DD/MM/YY", $1 )."), ";
				}

				# Trim trailing ', '
				$message = substr ( $message, 0, -2 );

				$message .= " )";

				plugin::ircnotice ( $ircUser, $message );
			}
		}
	}
	elsif ( $input =~ m/(\d+)\:0\:0/ )
	{
		my $ircUser = getRequestIdOwner ( $1 );
		if ( $ircUser )
			{ plugin::ircnotice ( $ircUser, "No results found for your search" ); }
	}
}



# Process 724 input ( Nick Search Result )
# 724 reqID:found:sending name Tstmp:ip\tTstmp:ip\0name Tstmp:ip\tTstmp:ip\0	name search result
sub process_724
{
	my $input = shift;

	if ( $input =~ m/(\d+)\:(\d+)\:(\d+)\s(.+)/ )
	{
		my $ircUser = getRequestIdOwner ( $1 );
		if ( $ircUser )
		{
			plugin::ircnotice ( $ircUser, "Found $3 results for your search, showing first $2..." );

			my $results = $4;
			while ( $results =~ m/\s*([^\ ]+)\s([^\]+)((.+))?/ )
			{
				$results = defined($4) ? $4 : "";;
				# 1 = name
				# 2 = group of ips / timestamps
				my $message = "07$1: ( ";

				my $ips = $2;
				while ( $ips =~ m/\s*(\d+)\:([^\t]+)(\t.+)?/ )
				{
					$ips = defined($3) ? $3 : "";
					$message .= "$2 (".modules::get_past_date_time ( "DD/MM/YY", $1 )."), ";
				}

				# Trim trailing ', '
				$message = substr ( $message, 0, -2 );

				$message .= " )";

				plugin::ircnotice ( $ircUser, $message );
			}
		}
	}
	elsif ( $input =~ m/(\d+)\:0\:0/ )
	{
		my $ircUser = getRequestIdOwner ( $1 );
		if ( $ircUser )
			{ plugin::ircnotice ( $ircUser, "No results found for your search" ); }
	}
}



# Process 727 input ( Common Nick Search Result )
# 727 reqID:found:sending name\vname
sub process_727
{
	my $input = shift;

	if ( $input =~ m/(\d+)\:(\d+)\:(\d+)\s(.+)/ )
	{
		my $ircUser = getRequestIdOwner ( $1 );
		if ( $ircUser )
		{
			plugin::ircnotice ( $ircUser, "Found $3 results for your search, showing first $2..." );

			my $message = "";
			my $results = $4;

			while ( $results =~ m/\s*([^\ ]+)\(.+)?/ )
			{
				# Check message length, if message has become too long send
				# what we have and start an new blank message
				if ( length($message) + length($1) > 450 )
				{
					# Trim trailing ', '
					$message = substr ( $message, 0, -2 );
					plugin::ircnotice ( $ircUser, $message );

					# Start new blank message
					$message = "";
				}


				# Add result to message and grab remaining results
				$message .= "$1, ";
				$results = defined($2) ? $2 : "";;
			}

			# Trim trailing ', '
			$message = substr ( $message, 0, -2 );
			plugin::ircnotice ( $ircUser, $message );
		}
	}
	elsif ( $input =~ m/(\d+)\:0\:0/ )
	{
		my $ircUser = getRequestIdOwner ( $1 );
		if ( $ircUser )
			{ plugin::ircnotice ( $ircUser, "No results found for your search" ); }
	}
}




####################################
##
# Other Functions
#
# N/A
##
####################################

# Triggered by the timer on playerjoin event, gets the IP of the player ( if they
# are still ingame ) and reports it to the server
sub reportPlayerData
{
	my $playername = $_[ ARG0 ];

	# Get and send the info for the player
	my ( $result, %player ) = plugin::getPlayerData( $playername );
	if ( $result == 1 && $serverOnline == 1 && $player{'ip'} )
	{
		# Report them to the ipdb server - request ID 0 (we dont need a reply)
		sendToServer ( "702 00:" . $player{'ip'} . ":" . $player{'name'} );
	}
}

# Ping the server to prevent the connection from being killed
sub ping
{
	my $kernel = $_[ KERNEL ];

	if ( $serverOnline == 1 )
	{
		sendToServer ( "700 " );
	}

	# Schedule another ping in 30 seconds
	$kernel->alarm( ping => (int(time()) + 30) );
}

# Scan's and reports all players in game, used when the bot has just loaded so nobody
# gets missed out. Also starts regular scans for players.
sub scanPlayers
{
	my $kernel = $_[ KERNEL ];

	if ( $serverOnline == 1 )
	{
		my %playerlist = plugin::get_playerlist();
		while ( my ( $id, $player ) = each ( %playerlist ) )
		{
			# Report them to the ipdb server
			if ( $player->{'ip'} )
			{
				# Report them to the ipdb server - request ID 0 (we dont need a reply)
				sendToServer ( "702 00:" . $player->{'ip'} . ":" . $player->{'name'} );
			}
		}
	}

	# Schedule another scan in 10 minutes
	$kernel->alarm( scanPlayers => (int(time()) + 600) );
}


# Sends data to the ipdb server
sub sendToServer
{
	my $line = shift;
	push ( @messageQueue, "$line\n" );
}




####################################
##
# Request ID functions
#
# Allocates request ID's and remembers who they
# belong to
##
####################################

# Hash to hold request IDs
my %requestIds;

# Allocate a new request ID
sub getRequestId
{
	my $ircUser = shift;

	# Allocate a random request ID
	my $requestId = int(rand(99999));

	# If this ID is already allocated try another ID until we find a free one
	while ( $requestIds{$requestId} )
		{ $requestId = int(rand(99999)); }

	$requestIds{$requestId} = $ircUser;
	return $requestId;
}

# Get the name of the owner of a request ID
sub getRequestIdOwner
{
	my $requestId = shift;

	if ( $requestIds{$requestId} )
	{
		my $ircUser = $requestIds{$requestId};
		delete $requestIds{$requestId};
		return $ircUser;
	}

	return undef;
}




# Return true or the bot will not work properly...
1;