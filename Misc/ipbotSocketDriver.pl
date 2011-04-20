#!/usr/bin/perl -w

use IO::Socket;

# This simple driver connects to the port for the ipbot server and attempts
# to communicate with it

#my $socket = IO::Socket::INET->new( 
#	PeerAddr => '192.168.0.10', 
#	PeerPort => '51988',
#	Proto => 'tcp' );

my $socket = IO::Socket::INET->new( 
	PeerAddr => 'IPDB.aohost.co.uk', 
	PeerPort => '51988',
	Proto => 'tcp' );

#my $socket = IO::Socket::INET->new( 
#	PeerAddr => '74.86.87.164', 
#	PeerPort => '51988',
#	Proto => 'tcp' );


die "ERROR: $!\n" unless $socket;


if ( $socket->connected() )
{
	print "Connected OK.\n";
}
else
{
	print "Connection failed.\n";
	exit (1);
}


print "Send 600 danpaul88:password\n";
$socket->send ( "600 danpaul88:password\n" );

print "Send 703 101:88.\n";
$socket->send ( "703 101:88.\n" );

print "Send 704 111:danpaul88\n";
$socket->send ( "704 111:danpaul88\n" );

print "Send 704 111:heimkind\n";
$socket->send ( "704 111:heimkind\n" );



my $recvTxt;
$| = 1;	#autoflush
while ( $socket->recv ( $recvTxt, 1024 ) )
{
	print "recv $recvTxt\n";
}