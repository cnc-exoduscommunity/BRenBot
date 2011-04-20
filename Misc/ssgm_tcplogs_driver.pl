#!/usr/bin/perl -w

use IO::Socket;

# This simple driver connects to the port for the ssgm log server and attempts
# to communicate with it

my $socket = IO::Socket::INET->new( 
	PeerAddr => '192.168.0.10', 
	PeerPort => '23366',
	Proto => 'tcp' );


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


print "Send 100 null\n";
$socket->send ( "100 null\n" );

print "Send 105 msg test\n";
$socket->send ( "105 msg test\n" );

#print "Send 704 111:danpaul88\n";
#$socket->send ( "704 111:danpaul88\n" );

#print "Send 704 111:heimkind\n";
#$socket->send ( "704 111:heimkind\n" );



my $recvTxt;
$| = 1;	#autoflush
while ( $socket->recv ( $recvTxt, 1024 ) )
{
	print "recv $recvTxt\n";
}