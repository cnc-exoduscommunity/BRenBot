#!/usr/bin/perl

package RenRem;
use strict;

use POE;

use modules;
use brconfig;

my $chill = 0;

my $renRemSocket = 0;

sub initRenRemSocket_win32
{
	my $ip = $brconfig::config_renrem_host;
	my $port = $brconfig::config_renrem_port;
	$renRemSocket = IO::Socket::INET->new( Proto => 'udp', PeerAddr => $ip, PeerPort => $port ) or die "socket: $@";
}

sub RenRemEncodeData ($$)
{
	# Special thanks to Scorpio9a And Silent_Kane for cracking the RenRem protocol.
	# Special thanks to Jeff T. Parsons aka bynari (Jeff.Parsons@Webgeeks.co.uk) for porting the bulk of the RenRem code to Perl.
	# Adapted to brenbot by Charles Jones aka Blazer0x.

	my ($data) = @_;
	my $password=$brconfig::config_renrem_password;
	die "Error. RenRemLinuxPassword must be exactly 8 characters in length\n."
	unless length($password) == 8;

	my (@msgbuf,		## This will be used when encrypting.
	$msgbuf,			## This will be used when calculating the checksum and for the final data.
		$i,				## Counter.
		$length,  		## Length of msg + checksum;
		$len,			## Length of just the msg. Used for pack().
		$chksum,		## The checksum.
		@password,		## Password array for convenience.
		$j,				## Holder used when calculating checksum.
		$bl,			## Bytes left at the end of the data when calculating the checksum if it doesn't divide evenly by 4.
		$buflen,
		$tempbuf
		);


	## Structure of data.
	## | 4 byte checksum | 4 null bytes | msg |
	$length = length($data) + 5; ## 4 for the null 0's and 1 for the null terminator.
	$len	= $length - 4;
	$chksum = 0;


	## Convert password and data to ascii values because we'll be manipulating the ascii
	## codes when encrypting.
	@msgbuf   = unpack("C8 C$len", pack("x8 a$len x", $data)); ## @msgbuf contains full data structure. Checksum, null 0's and data.
	@password = map { ord } split (//, $password);


	## Encrypt the message.
	for ($i = 0 ; $i < $length ; $i++) {
	$password[$i % 8] ^= ($msgbuf[$i + 4] = ((((0xff << 8) | ($msgbuf[$i + 4] + $i)) - 0x32) & 0xff) ^ $password[$i % 8]);
	}

	## Convert from array to packed structure.
	$msgbuf = pack("C8 C$len", @msgbuf);


	## Calculate the checksum.
	for ($i = 0 ; $i < $length ; $i += 4) {

	$chksum = ($chksum >> 0x1f) + $chksum * 2;

	if ($i + 4 > $length) {
	$bl = $length % 4;
	$buflen = length($msgbuf);
	$tempbuf = pack("C" x ($buflen + 3), unpack("C$buflen",$msgbuf), 0, 0, 0);

	$chksum += unpack("x4 x$i I", $tempbuf);
	} else {
	$chksum += unpack("x4 x$i I", $msgbuf);
	}

	## Checksum should never be over 32 bits. The lefmost 32bits are always used.
	while ($chksum > (2**32)) {
	$chksum -= 2**32;
	}
	}


	## Add in the checksum.
	$msgbuf = pack (" C4 C$length", unpack("C4", pack('I', $chksum)), unpack("x4 C$length", $msgbuf));


	## Return the encoded structure.
		return $msgbuf;
}

sub RenRemDecodeData ($$) {
	# Special thanks to Scorpio9a And Silent_Kane for cracking the RenRem protocol.
	# Special thanks to Jeff T. Parsons aka bynari (Jeff.Parsons@Webgeeks.co.uk) for porting the bulk of the RenRem code to Perl.
	# Adapted to brenbot by Charles Jones aka Blazer0x.
	my ($data) = @_;
	my $password=$brconfig::config_renrem_password;

	my (	$length, # Same as $length in encodeData.
		@msgbuf,
		@password,
		$p,
		$i
	   );

	@password = map { ord } split (//, $password);
	$length = length($data) - 4; ## -4 because we don't care about the encapsulated checksum.

	@msgbuf = unpack("C4 C$length", $data);

	for ($i = 0 ; $i < $length ; $i++) {
	$p = $password[$i % 8];
	$password[$i % 8] = $msgbuf[$i + 4] ^ $password[$i % 8];
	($msgbuf[$i + 4] = ( unpack("c", pack("C",($msgbuf[$i + 4] ^ $p))) - $i + 50));
	}

	return join '', map { chr } @msgbuf[8 .. $#msgbuf];
}



sub win32_renrem
{
	if ( $renRemSocket == 0 ) { initRenRemSocket_win32(); }

	# Special thanks to Scorpio9a And Silent_Kane for cracking the RenRem protocol.
	# Special thanks to Jeff T. Parsons aka bynari (Jeff.Parsons@Webgeeks.co.uk) for porting the bulk of the RenRem code to Perl.
	# Adapted to brenbot by Charles Jones aka Blazer0x
	my $command=shift;
	my $encrypted_password=RenRemEncodeData($brconfig::config_renrem_password,$brconfig::config_renrem_password);
	my $encrypted_command = RenRemEncodeData($command,$brconfig::config_renrem_password);
# 	my $ip = $brconfig::config_renrem_host;
# 	my $port = $brconfig::config_renrem_port;
# 	my $handle = IO::Socket::INET->new( Proto => 'udp', PeerAddr => $ip, PeerPort => $port ) or die "socket: $@";

	#$handle->send($encrypted_password);
	#$handle->send($encrypted_command);
	$renRemSocket->send($encrypted_password);
	$renRemSocket->send($encrypted_command);
	#print "DEBUG: Encrypted RenRem Command Sent.\n";
}

sub linux_renrem
{
	# Written by mac@onehsell...thanks Mac!
	# sends linux renegade console command to mac's renrem TCP server
	my $command = shift;

	POE::Session->create
	( inline_states =>
		{ _start => sub
			{
				#print "Sending $command\n";
				$_[KERNEL]->post("renrem", "send_command", $command); # call other session's function reset

				if ($command =~ m/^msg\s(.+)/g)
				{
					brIRC::ircmsg ( "Host: $1", 1 );
				}

				if ($command =~ m/^amsg\s(.+)/g)
				{
					brIRC::ircmsg ( "Host (amsg): $1", 1 );
				}
			},
		} # end of inline states
	);
}	# End of linux_renrem

sub RenRemCMDtimed
{
	my $cmd = shift;
	my $time = shift;

	POE::Session->create
	( inline_states =>
	{ _start => sub {
			$_[HEAP]->{next_alarm_time} = int( time() ) + $time;
			$_[KERNEL]->alarm( tick => $_[HEAP]->{next_alarm_time} );
		},
		tick => sub {
			RenRemCMD ($cmd);
			},

		},
	);

}


sub RenRemCMD
{
	my $message = shift;
	$chill=1;	# To make sure we arent/wont be doing anything else until we are done with this sub.

	$message =~ s///g;
	$message =~ s/\d*(,\d*)//g;

	if ($brconfig::config_botmode eq "WIN32")
	{
		win32_renrem($message);
	}
	else
	{
		linux_renrem($message);
	}

	$chill=0;
}

1;