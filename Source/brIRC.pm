# brIRC.pm
#
# Connects to an IRC server and manages the sending and receiving of data on the
# IRC network.

package brIRC;
use strict;

use IO::Socket;
use POE;

use brAuth;

# Variables
my $socket;
my @priorityMessageQueue;	# Queue for high priority outgoing messages
my @messageQueue;			# Queue for outgoing messages

my %adminChannelUsers;		# Permission flags for admin channel users
my %publicChannelUsers;		# Permission flags for public channel users


# Connect to the IRC server, and join channels
sub init
{
	# Create IRC session
	POE::Session->create
	( inline_states =>
		{
			_start => sub
			{
				my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
				$kernel->alias_set( "IRC" );

				# Public and admin IRC channels cannot be the same
				if ( lc($brconfig::irc_publicChannel) eq lc($brconfig::irc_adminChannel) ) { $brconfig::irc_publicChannel = ""; };

				$socket = IO::Socket::INET->new( PeerAddr => $brconfig::config_ircserver,
					PeerPort => $brconfig::config_ircport,
					Proto => 'tcp' );


				if ( $socket && $socket->connected() )
				{
					modules::console_output ( "[IRC] Connected to $brconfig::config_ircserver." );

					# Identify ourself to the server
					sendToServer ( "NICK $brconfig::config_botname" );
					sendToServer ( "USER $brconfig::config_botname * * :BRenBot ".main::BR_VERSION." build ".main::BR_BUILD );

					# Store current IRC nickname (used when resolving 433 (nick in use) problems)
					$heap->{'ircNick'} = $brconfig::config_botname;

					# Start receiving
					$kernel->yield( "receiveloop" );
					$kernel->yield( "sendloop" );
				}
				else
				{
					modules::console_output ( "[IRC] Failed to connect to $brconfig::config_ircserver, retrying in 5 seconds." );
					$kernel->alarm ( "reconnect" => (time()+5) );
				}
			},
			reconnect => sub
			{
				my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];

				$socket = IO::Socket::INET->new( PeerAddr => $brconfig::config_ircserver,
					PeerPort => $brconfig::config_ircport,
					Proto => 'tcp' );

				if ( $socket && $socket->connected() )
				{
					modules::console_output ( "[IRC] Connected to $brconfig::config_ircserver." );

					# Identify ourself to the server
					sendToServer ( "NICK $brconfig::config_botname" );
					sendToServer ( "USER BRenBot_$brconfig::config_botname * * :BRenBot ".main::BR_VERSION." build ".main::BR_BUILD );

					# Store current IRC nickname (used when resolving 433 (nick in use) problems)
					$heap->{'ircNick'} = $brconfig::config_botname;

					# Start receiving
					$kernel->yield( "receiveloop" );
					$kernel->yield ( "sendloop" );
				}
				else
				{
					modules::console_output ( "[IRC] Failed to connect to $brconfig::config_ircserver, retrying in 30 seconds." );
					$kernel->alarm ( "reconnect" => (time()+30) );
				}
			},
			receiveloop => sub
			{
				my $heap = $_[ HEAP ];

				$heap->{'socket'} = new POE::Wheel::ReadWrite
				(
					Handle     => $socket,
					InputEvent => 'gotline',
					ErrorEvent => 'goterror',
			    );
			},
			sendloop => sub
			{
				my $kernel = $_[ KERNEL ];
				my $availableChars = $brconfig::irc_charsPerSecond;
				my $sendString = "";

				# Send at least one message
				if ( $priorityMessageQueue[0] )
				{
					my $output = shift @priorityMessageQueue;
					$sendString .= $output;
					$availableChars -= length ( $output );
				}
				elsif ( $messageQueue[0] )
				{
					my $output = shift @messageQueue;
					$sendString .= $output;
					$availableChars -= length ( $output );
				}

				# Keep sending messages until we hit out chars per second limit
				while ( $priorityMessageQueue[0] && ( length($priorityMessageQueue[0]) < $availableChars ) )
				{
					my $output = shift @priorityMessageQueue;
					$sendString .= $output;
					$availableChars -= length ( $output );
				}

				while ( $messageQueue[0] && ( length($messageQueue[0]) < $availableChars ) )
				{
					my $output = shift @messageQueue;
					$sendString .= $output;
					$availableChars -= length ( $output );
				}

				if ( $sendString )
				{
					$socket->send( $sendString );
				}

			    # Come back to the send loop in 1 second
			    $kernel->delay ( "sendloop", 1 );
			},
			gotline => sub
			{
				my ( $heap, $input ) = @_[ HEAP, ARG0 ];

				#open ( IRCDEBUGFILE, '>>ircdebug.txt' );
				#print IRCDEBUGFILE "RECEIVE: $input\n";
				#close IRCDEBUGFILE;

				if ( $input =~ m/^PING\s(.+)$/i )
					{ sendToServer ( "PONG $1", 1 ); return; }

				if ( $input =~ m/^\:(\S+)\s001\s/ )
				{
					# If we have a NickServ auth line send it to the server
					if ( $brconfig::irc_nickserv_name && $brconfig::irc_nickserv_auth )
						{ ircpm ( $brconfig::irc_nickserv_name, $brconfig::irc_nickserv_auth ); }

					# If operAuth is enabled then send it off
					if ( $brconfig::irc_operUser && $brconfig::irc_operPass )
						{ sendToServer ( "OPER $brconfig::irc_operUser $brconfig::irc_operPass" ); }

					if ( $brconfig::irc_publicChannel ne "" )
					{
						modules::console_output ( "[IRC] Joining channel $brconfig::irc_publicChannel..." );
						sendToServer ( "JOIN $brconfig::irc_publicChannel $brconfig::irc_publicChannel_key" );
					}
					modules::console_output ( "[IRC] Joining channel $brconfig::irc_adminChannel..." );
					sendToServer ( "JOIN $brconfig::irc_adminChannel $brconfig::irc_adminChannel_key" );

					# Send messages to both irc channels and the FDS
					ircmsg ( "BRenBot ".main::BR_VERSION." reporting for duty! Type !help for a list of commands." );
					RenRem::RenRemCMD( "msg BRenBot ".main::BR_VERSION." starting up. Type !help for a list of commands" );
				}

				# Reply to NAMES (353)
				elsif ( $input =~ m/^\:(\S+)\s353\s/ )
					{ names ( $input ); }

				# PRIVMSG
				elsif ( $input =~ m/PRIVMSG/ )
					{ privmsg ( $input ); }

				# MODE
				elsif ( $input =~ m/MODE/ )
					{ mode ( $input ); }

				# JOIN
				elsif ( $input =~ m/JOIN/ )
					{ ircjoin ( $input ); }

				# PART
				elsif ( $input =~ m/PART/ )
					{ part ( $input ); }

				# NICK
				elsif ( $input =~ m/NICK/ )
					{ nick ( $input ); }


				# Nickname in use (433)
				elsif ( $input =~ m/^\:(\S+)\s433\s/ )
				{
					modules::console_output ( "[IRC] Nickname ".$heap->{'ircNick'}." is already in use, retrying with ".$heap->{'ircNick'}."_1" );
					$heap->{'ircNick'} = $heap->{'ircNick'}."_1";
					sendToServer ( "NICK ".$heap->{'ircNick'} );
					sendToServer ( "USER ".$heap->{'ircNick'}." * * :BRenBot ".main::BR_VERSION." build ".main::BR_BUILD );
				}
			},
			goterror => sub
			{
				# Means we are disconnected
				my ( $kernel, $heap, $error ) = @_[ KERNEL, HEAP, ARG0 ];

				#open ( IRCDEBUGFILE, '>>ircdebug.txt' );
				#print IRCDEBUGFILE "ERROR: $error\n";
				#close IRCDEBUGFILE;

				# Shutdown socket and wheel
				$heap->{'socket'}->shutdown_input();
				$heap->{'socket'}->shutdown_output();
				delete $heap->{'socket'};
				shutdown ( $socket, 2 );

				modules::console_output ( "[IRC] ERROR: $error" );
				modules::console_output ( "[IRC] Disconnect detected, attemping to reconnect in 10 seconds." );
				$kernel->alarm ( "reconnect" => (time()+10) );
			},
			privmsg => sub
			{
				# Duplicates old IRC functionality to allow older plugins to work. Most
				# will not use channel codes, but we will add the parameter anyway
				my ( $recipient, $message, $channelCode ) = @_[ ARG0, ARG1, ARG2 ];

				if ( $recipient !~ m/^\#/ )
					{ ircpm ( $recipient, $message ); }
				else
					{ ircmsg ( $message, $channelCode ); }
			}
		}
	);
}


# Send a line to the server
sub sendToServer
{
	my $line			= shift;
	my $highPriority	= shift;

	if ( $highPriority )
	{
		#open ( IRCDEBUGFILE, '>>ircdebug.txt' );
		#print IRCDEBUGFILE "Priority SEND: $line\n";
		#close IRCDEBUGFILE;

		push ( @priorityMessageQueue, "$line\r\n" );
	}
	else
	{
		#open ( IRCDEBUGFILE, '>>ircdebug.txt' );
		#print IRCDEBUGFILE "SEND: $line\n";
		#close IRCDEBUGFILE;

		push ( @messageQueue, "$line\r\n" );
	}
}


# Process incoming messages
sub privmsg
{
	my $line = shift;

	if ( $line =~ m/\:(.+)\!(.+)\@(.+)\sPRIVMSG\s(\#?\S+)\s\:(.+)/ )
	{
		my $nick			= $1;
		my $nick_fullname	= $2;
		my $nick_location	= $3;
		my $channel			= $4;
		my $message			= $5;

		if ( $channel !~ m/^\#/ )
		{
			privmsg_pm ( $message, $nick );
			return;
		}

		my $channelCode;
		if ( lc($channel) eq lc($brconfig::irc_publicChannel) || lc($channel) eq lc($brconfig::irc_adminChannel) )
			{ $channelCode = ( lc($channel) eq lc($brconfig::irc_adminChannel) ) ? "A" : "P"; }
		else
			{ return; }

		#print "$nick ( $nick_fullname @ $nick_location ) said '$message' on $channel\n";

		if ($message =~ /(^\!\w+)\s*(\w*).*/)
		{
			eval { commands::parsearg( $message, "$nick\@IRC", "N", $channelCode ) };
			modules::display_error($@) if $@;
		}

		# Process plugin events
		my @plugins = plugin::get_plugin_event("text");
		my %args;
		$args{nick}			= "$nick\@IRC";
		$args{nicktype}		= 1;
		$args{message}		= $message;
		$args{messagetype}	= "irc_public";
		$args{channelCode}	= $channelCode;

		foreach (@plugins)
		{
			my $plugin = $_;
			my $alias = "plugin_" . $plugin;

			$poe_kernel->post( $alias => "text" => \%args );
		}
	}
}


# Handle private messages from users
sub privmsg_pm
{
	my $message		= shift;
	my $sender		= shift;

	if ( $message =~ m/^\!register/i )
		{ register ( $message, $sender ); }
	elsif ( $message =~ m/^\!auth/i )
		{ auth ( $message, $sender ); }
	elsif ( $message =~ m/^\!alias/i )
		{ alias ( $message, $sender ); }
	elsif ( $message =~ m/^\!delregister/i )
		{ delregister ( $message, $sender ); }
	elsif ( $message =~ m/^\!help/i )
	{
		ircpm ( $sender, "Valid Commands:" );
		ircpm ( $sender, "!register <playername> <password>" );
		ircpm ( $sender, "!alias <existing playername> <password> <new playername>" );
		ircpm ( $sender, "!delregister <playername> <password>" );
		ircpm ( $sender, "!auth <playername> <password>" );
	}

	# Hidden command to force bot to rejoin default channels (useful if channel was somehow
	# locked when bot attempted to connect)
	elsif ( $message =~ m/^\!joinchannel/i )
	{
		modules::console_output ( "[IRC] Joining channel $brconfig::irc_adminChannel..." );
		sendToServer ( "JOIN $brconfig::irc_adminChannel $brconfig::irc_adminChannel_key" );

		if ( $brconfig::irc_publicChannel ne "" )
		{
			modules::console_output ( "[IRC] Joining channel $brconfig::irc_publicChannel..." );
			sendToServer ( "JOIN $brconfig::irc_publicChannel $brconfig::irc_publicChannel_key" );
		}
	}


	# Send plugin events
	my @plugins = plugin::get_plugin_event( "text" );
	my %args;
	$args{nick}			= "$sender\@IRC";
	$args{nicktype}		= 1;
	$args{message}		= $message;
	$args{messagetype}	= "irc_privmsg";

	foreach (@plugins)
	{
		my $plugin = $_;
		my $alias = "plugin_" . $plugin;

		$poe_kernel->post( $alias => "text" => \%args );
	}
}


# Handle mode changes
sub mode
{
	my $input = shift;
	if ( $input =~ m/\:\S+\sMODE\s(\S+)\s(\+|\-)((o|v|h|q|a)+)\s(.+)/ )
	{
		my $channel		= $1;
		my $plusminus	= $2;
		my $modes		= $3;
		my $names		= $5;

		#open ( IRCDEBUGFILE, '>>ircdebug.txt' );
		#print IRCDEBUGFILE "Got mode change on channel $channel, $plusminus $modes for $names\n";
		#close IRCDEBUGFILE;

		while ( $names =~ m/^(\S+)(\s(.+))?/ )
		{
			my $name = $1;
			$names = $3;

			$modes =~ m/^(\S)(\S+)?/;
			my $flag = $1;
			$modes = $2;

			if ( lc($channel) eq lc($brconfig::irc_adminChannel) )
			{
				if ( $plusminus eq '-' ) { setUserFlag ( $name, 'A', $flag, 0 ); }
				elsif ( $plusminus eq '+' ) { setUserFlag ( $name, 'A', $flag, 1 ); }
			}
			elsif ( lc($channel) eq lc($brconfig::irc_publicChannel) )
			{
				if ( $plusminus eq '-' ) { setUserFlag ( $name, 'P', $flag, 0 ); }
				elsif ( $plusminus eq '+' ) { setUserFlag ( $name, 'P', $flag, 1 ); }
			}
		}
	}
}


# Process JOIN
sub ircjoin
{
	my $input = shift;
	if ( $input =~ m/\:(.+)\!(.+)\@(.+)\sJOIN\s\:(\S+)/ )
	{
		modules::console_output ( "[IRC] $1 joined channel $4" );

		#open ( IRCDEBUGFILE, '>>ircdebug.txt' );
		#print IRCDEBUGFILE "$1 joined channel $4\n";
		#close IRCDEBUGFILE;

		if ( lc($4) eq lc($brconfig::irc_adminChannel) )
			{ addUser ( $1, 'A' ); }
		elsif ( lc($4) eq lc($brconfig::irc_publicChannel) )
			{ addUser ( $1, 'P' ); }
	}
}


# Process PART
sub part
{
	my $input = shift;
	if ( $input =~ m/\:(.+)\!(.+)\@(.+)\sPART\s(\S+)/ )
	{
		modules::console_output ( "[IRC] $1 left channel $4" );

		#open ( IRCDEBUGFILE, '>>ircdebug.txt' );
		#print IRCDEBUGFILE "$1 left channel $4\n";
		#close IRCDEBUGFILE;

		# Delete permissions
		if ( lc($4) eq lc($brconfig::irc_adminChannel) )
			{ deleteUser( $1, 'A' ); }
		elsif ( lc($4) eq lc($brconfig::irc_publicChannel) )
			{ deleteUser( $1, 'P' ); }
	}
}


# Process NICK
sub nick
{
	my $input = shift;
	if ( $input =~ m/\:(.+)\!(.+)\@(.+)\sNICK\s\:(\S+)/ )
	{
		modules::console_output ( "[IRC] $1 is now known as $4" );

		#open ( IRCDEBUGFILE, '>>ircdebug.txt' );
		#print IRCDEBUGFILE "$1 is now known as $4\n";
		#close IRCDEBUGFILE;

		# Copy permissions across
		if ( exists ( $adminChannelUsers{lc($1)} ) )
		{
			$adminChannelUsers{lc($4)} = {
				'name' => lc($4),
				'voice' => $adminChannelUsers{lc($1)}->{'voice'},
				'halfop' => $adminChannelUsers{lc($1)}->{'halfop'},
				'op' => $adminChannelUsers{lc($1)}->{'op'},
				'founder' => $adminChannelUsers{lc($1)}->{'founder'},
				'protected' => $adminChannelUsers{lc($1)}->{'protected'}
			};
			deleteUser ( $1, 'A' ); }
		if ( exists ( $publicChannelUsers{lc($1)} ) )
		{
			$publicChannelUsers{lc($4)} = {
				'name' => lc($4),
				'voice' => $publicChannelUsers{lc($1)}->{'voice'},
				'halfop' => $publicChannelUsers{lc($1)}->{'halfop'},
				'op' => $publicChannelUsers{lc($1)}->{'op'},
				'founder' => $publicChannelUsers{lc($1)}->{'founder'},
				'protected' => $publicChannelUsers{lc($1)}->{'protected'}
			};
			deleteUser ( $1, 'P' );
		}
	}
}


# Process names list
sub names
{
	my $input = shift;
	if ( $input =~ m/\:\S+\s353\s\S+\s.\s(\S+)\s\:(.+)/ )
	{
		my $channel = $1;
		my $names = $2;

		while ( defined($names) && $names =~ m/^(\@|\%|\+|\&|\~)?(\S+)(\s(.+))?/ )
		{
			$names = $4;
			if ( lc($channel) eq lc($brconfig::irc_adminChannel) && $1 )
			{
				#open ( IRCDEBUGFILE, '>>ircdebug.txt' );
				#print IRCDEBUGFILE "$2 has status $1 on admin channel\n";
				#close IRCDEBUGFILE;

				if ( !exists ( $adminChannelUsers{lc($2)} ) ) { addUser ( $2, 'A' ); }
				setUserFlag ( $2, 'A', $1, 1 );
			}
			elsif ( lc($channel) eq lc($brconfig::irc_publicChannel) && $1 )
			{
				#open ( IRCDEBUGFILE, '>>ircdebug.txt' );
				#print IRCDEBUGFILE "$2 has status $1 on public channel\n";
				#close IRCDEBUGFILE;

				if ( !exists ( $publicChannelUsers{lc($2)} ) ) { addUser ( $2, 'P' ); }
				setUserFlag ( $2, 'P', $1, 1 );
			}
		}
	}
}



###################################################
####
## General functions for outputting messages to the
## IRC channel
####
###################################################


# Channel codes determine which channels get the message.
# A = Only admin channel
# P = Only public channel
# Anything else goes to both channels
sub ircmsg
{
	my $message		= shift;
	my $channelCode	= shift;

	if ( $brconfig::irc_prefixIRCMessages == 1 )
		{ $message = "[BR] " . $message; }

	if ( !defined($channelCode) or $channelCode ne "P" )
		{ sendToServer ( "PRIVMSG $brconfig::irc_adminChannel :$message" ); }
	if ( (!defined($channelCode) or $channelCode ne "A") && $brconfig::irc_publicChannel ne "" )
		{ sendToServer ( "PRIVMSG $brconfig::irc_publicChannel :$message" ); }
}


# Send a message to a user
sub ircpm
{
	my $recipient	= shift;
	my $message		= shift;

	sendToServer ( "PRIVMSG $recipient :$message" );
}


# Send a notice to a user
sub ircnotice
{
	my $recipient	= shift;
	my $message		= shift;

	sendToServer ( "NOTICE $recipient :$message" )
}


###################################################
####
## Functions for the registration system
####
###################################################

sub register
{
	my $message = shift;
	my $sender = shift;

	eval
	{
		if ( $message =~ m/^\!register\s(.+)\s(\S+)$/ )
		{
			my $nick = $1;
			my $pass = $2;

			my $return = modules::user_exists( $nick );
			if ($return == 0)
			{
				modules::add_user( $nick, $pass );
				ircpm ( $sender, "Registered playername $nick." );
			}
			else
				{ ircpm ( $sender, "User $nick already exists." ); }
		}
		else
			{ ircpm ( $sender, "Usage: !register <playername> <password>" ); }
	}
	or modules::display_error($@);
}

sub auth
{
	my $message = shift;
	my $sender = shift;

	eval
	{
		if ( $message =~ m/^\!auth\s(.+)\s(\S+)$/ )
		{
			my $authResult = brAuth::AuthenticateByPassword( $1, $2 );
			if ( $authResult == 1 )
				{ ircpm ( $sender, "Authentification granted." ); }
			elsif ( $authResult == 4 )
				{ ircpm ( $sender, "You are not on the server. You can\'t authenticate yourself." ); }
			elsif ( $authResult != 2 )	# Ignore re-authentication attempts
				{ ircpm ( $sender, "Access denied, nickname does not exist or password is invalid." ); }
		}
		else
			{ ircpm ( $sender, "Usage: !auth <playername> <password>" ); }
	}
	or modules::display_error($@);
}

sub alias
{
	my $message = shift;
	my $sender = shift;

	eval
	{
		if ( $message =~ m/^\!alias\s(.+)\s(\S+)\s(.+)$/ )
		{
			my $nick = $1;
			my $pass = $2;
			my $newnick = $3;

			if ( brAuth::CheckAuthPassword( $nick, $pass ) )
			{
				ircpm ( $sender, "Added Alias $newnick." );
				modules::add_user( $newnick, $pass );
			}
			else
				{ ircpm ( $sender, "Access denied." ); }

		}
		else
			{ ircpm ( $sender, "Usage: !alias <existing playername> <password> <new playername>" ); }
	}
	or modules::display_error($@);
}

sub delregister
{
	my $message = shift;
	my $sender = shift;

	eval
	{
		if ( $message =~ m/^\!delregister\s(.+)\s(\S+)$/ )
		{
			my $nick = $1;
			my $pass = $2;

			if ( brAuth::CheckAuthPassword( $nick, $pass ) )
			{
				modules::del_user( $nick );
				ircpm ( $sender, "Registration of the name $nick has been deleted." );
			}
			else
				{ ircpm ( $sender, "No such nickname, or invalid password." ); }
		}
		else
			{ ircpm ( $sender, "Usage: !delregister <playername> <password>" ); }
	}
	or modules::display_error($@);
}




###################################################
####
## Code for managing irc users data
####
###################################################

sub addUser
{
	my $username = lc(shift);
	my $userchannel = shift;

	if ( $userchannel eq 'A' && !exists ( $adminChannelUsers{$username} ) )
	{
		$adminChannelUsers{$username} = {
			'name' => $username,
			'voice' => 0,
			'halfop' => 0,
			'op' => 0,
			'founder' => 0,
			'protected' => 0
		};
	}
	elsif ( $userchannel eq 'P' && !exists ( $publicChannelUsers{$username} ) )
	{
		$publicChannelUsers{$username} = {
			'name' => $username,
			'voice' => 0,
			'halfop' => 0,
			'op' => 0,
			'founder' => 0,
			'protected' => 0
		};
	}
}


sub deleteUser
{
	my $username = lc(shift);
	my $userchannel = shift;

	if ( $userchannel eq 'A' && exists ( $adminChannelUsers{$username} ) )
	{
		foreach my $k ( keys %{$adminChannelUsers{$username}} )
		{ delete $adminChannelUsers{$username}->{$k}; }
		delete $adminChannelUsers{$username};
	}
	elsif ( $userchannel eq 'P' && exists ( $publicChannelUsers{$username} ) )
	{
		foreach my $k ( keys %{$publicChannelUsers{$username}} )
		{ delete $publicChannelUsers{$username}->{$k}; }
		delete $publicChannelUsers{$username};
	}
}


sub setUserFlag
{
	my $username = lc(shift);
	my $userchannel = shift;
	my $flag = lc(shift);
	my $flagState = shift;

	#print "setting flag $flag to $flagState for $username on $userchannel\n";

	if ( $userchannel eq 'A' && exists ( $adminChannelUsers{$username} ) )
	{
		if ( $flag eq "+" || $flag eq "v" ) { $adminChannelUsers{$username}->{'voice'} = $flagState; }
		if ( $flag eq "%" || $flag eq "h" ) { $adminChannelUsers{$username}->{'halfop'} = $flagState; }
		if ( $flag eq "@" || $flag eq "o" ) { $adminChannelUsers{$username}->{'op'} = $flagState; }
		if ( $flag eq "~" || $flag eq "q" ) { $adminChannelUsers{$username}->{'founder'} = $flagState; }
		if ( $flag eq "&" || $flag eq "a" ) { $adminChannelUsers{$username}->{'protected'} = $flagState; }
	}
	elsif ( $userchannel eq 'P' && exists ( $publicChannelUsers{$username} ) )
	{
		if ( $flag eq "+" || $flag eq "v" ) { $publicChannelUsers{$username}->{'voice'} = $flagState; }
		if ( $flag eq "%" || $flag eq "h" ) { $publicChannelUsers{$username}->{'halfop'} = $flagState; }
		if ( $flag eq "@" || $flag eq "o" ) { $publicChannelUsers{$username}->{'op'} = $flagState; }
		if ( $flag eq "~" || $flag eq "q" ) { $publicChannelUsers{$username}->{'founder'} = $flagState; }
		if ( $flag eq "&" || $flag eq "a" ) { $publicChannelUsers{$username}->{'protected'} = $flagState; }
	}
}



sub getUserPermissions
{
	my $username = lc(shift);
	my $userchannel = shift;

	# Strip @IRC from username if it exists
	$username =~ s/\@IRC//gi;

	if ( $userchannel eq "A" && exists ( $adminChannelUsers{$username} ) )
	{
		if ( $adminChannelUsers{$username}->{'protected'} == 1 )
			{ return 'irc_protected'; }
		if ( $adminChannelUsers{$username}->{'founder'} == 1 )
			{ return 'irc_founder'; }
		if ( $adminChannelUsers{$username}->{'op'} == 1 )
			{ return 'irc_op'; }
		if ( $adminChannelUsers{$username}->{'halfop'} == 1 )
			{ return 'irc_halfop'; }
		if ( $adminChannelUsers{$username}->{'voice'} == 1 )
			{ return 'irc_voice'; }
	}
	elsif ( $userchannel eq "P" && exists ( $publicChannelUsers{$username} ) )
	{
		if ( $publicChannelUsers{$username}->{'protected'} == 1 )
			{ return 'irc_protected'; }
		if ( $publicChannelUsers{$username}->{'founder'} == 1 )
			{ return 'irc_founder'; }
		if ( $publicChannelUsers{$username}->{'op'} == 1 )
			{ return 'irc_op'; }
		if ( $publicChannelUsers{$username}->{'halfop'} == 1 )
			{ return 'irc_halfop'; }
		if ( $publicChannelUsers{$username}->{'voice'} == 1 )
			{ return 'irc_voice'; }
	}

	# Default
	return "irc_normal";
}



# Return true
1;