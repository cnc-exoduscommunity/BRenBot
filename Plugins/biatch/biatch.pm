#
# BIATCH plugin for BRenBot 1.51 by Daniel Paul
# Interface for the BIATCH dll
#
# Version 1.031
#
package biatch;

use POE;
use plugin;

our %additional_events =
(
	# !command functions
	"trust" => "trust",
	"untrust" => "untrust",
	"antiaimbot" => "antiaimbot",
	"rehashbiatch" => "rehashbiatch",
	"biatchMessage" => "biatchMessage"
);

# BRenBot automatically sets the plugin name, and imports config from the xml file
our $plugin_name;
our %config;
my $pluginVersion = 1.031;		# Plugin version


########### Functions for !commands

# Trust command
sub trust
{
	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
	my %args = %{$args};
	
	if ( $args{arg} =~ m/^\!\S+\s(.+)$/i )
	{
		my ( $result, %player ) = plugin::getPlayerData ( $1 );
		if ( $result == 1 )
		{
			# Send to FDS console
			plugin::RenRemCMD ( "trust $player{id}" );
			plugin::ircmsg ( "$player{name} is now trusted", $args{ircChannelCode} );
		}
		else { plugin::ircmsg ( "$1 was not found ingame, or is not unique", $args{ircChannelCode} ); }
	}
	else
	{
		plugin::ircmsg ( "Usage: !trust <playername>/<id>", $args{ircChannelCode} );
	}
}

# Untrust command
sub untrust
{
	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
	my %args = %{$args};
	
	if ( $args{arg} =~ m/^\!\S+\s(.+)$/i )
	{
		my ( $result, %player ) = plugin::getPlayerData ( $1 );
		if ( $result == 1 )
		{
			# Send to FDS console
			plugin::RenRemCMD ( "distrust $player{id}" );
			plugin::ircmsg ( "$player{name} is no longer trusted", $args{ircChannelCode} );
		}
		else { plugin::ircmsg ( "$1 was not found ingame, or is not unique", $args{ircChannelCode} ); }
	}
	else
	{
		plugin::ircmsg ( "Usage: !untrust <playername>/<id>", $args{ircChannelCode} );
	}
}

# Antiaimbot command
sub antiaimbot
{
	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
	my %args = %{$args};
	
	if ( $args{arg} =~ m/^\!\S+\s(.+)$/i )
	{
		my ( $result, %player ) = plugin::getPlayerData ( $1 );
		if ( $result == 1 )
		{
			# Send to FDS console
			plugin::RenRemCMD ( "antiaimbot $player{id}" );
			plugin::ircmsg ( "$player{name} now has the antiaimbot script attached.", $args{ircChannelCode} );
		}
		else { plugin::ircmsg ( "$1 was not found ingame, or is not unique", $args{ircChannelCode} ); }
	}
	else
	{
		plugin::ircmsg ( "Usage: !antiaimbot <playername>/<id>", $args{ircChannelCode} );
	}
}

# Rehashbiatch command
sub rehashbiatch
{
	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
	my %args = %{$args};
	
	# Send to FDS console
	plugin::RenRemCMD ( "rehashbiatch" );
	plugin::ircmsg ( "BIATCH configuration files have been reloaded", $args{ircChannelCode} );
}


########## Renlog Regex Hook events

sub biatchMessage
{
	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
	my %args = %{$args};
	
	if ( $args{line} =~ m/^\s*\[BIATCH\]\s(.+)/i )
	{
		my $message = replaceWarheadNumbers( $1 );
		plugin::ircmsg ( "14[BIATCH] $message", "A" );
	}
}

# Replaces 'Warhead: <num>' with 'Warhead: <num> (<name>)'
sub replaceWarheadNumbers
{
	my $line = shift;
	
	$line =~ s/Warhead:\s0/Warhead:\s0\s(None)/gi;
	$line =~ s/Warhead:\s1/Warhead:\s1\s(Steel)/gi;
	$line =~ s/Warhead:\s2/Warhead:\s2\s(Steel_NoBuilding)/gi;
	$line =~ s/Warhead:\s3/Warhead:\s3\s(Shrapnel)/gi;
	$line =~ s/Warhead:\s4/Warhead:\s4\s(Explosive)/gi;
	$line =~ s/Warhead:\s5/Warhead:\s5\s(Explosive_NoBuilding)/gi;
	$line =~ s/Warhead:\s6/Warhead:\s6\s(Shell)/gi;
	$line =~ s/Warhead:\s7/Warhead:\s7\s(Shell_NoBuilding)/gi;
	$line =~ s/Warhead:\s8/Warhead:\s8\s(Flamethrower)/gi;
	$line =~ s/Warhead:\s9/Warhead:\s9\s(TiberiumRaw)/gi;
	$line =~ s/Warhead:\s10/Warhead:\s10\s(TiberiumBullet)/gi;
	$line =~ s/Warhead:\s11/Warhead:\s11\s(TiberiumShrapnel)/gi;
	$line =~ s/Warhead:\s12/Warhead:\s12\s(C4)/gi;
	$line =~ s/Warhead:\s13/Warhead:\s13\s(Laser)/gi;
	$line =~ s/Warhead:\s14/Warhead:\s14\s(Laser_NoBuilding)/gi;
	$line =~ s/Warhead:\s15/Warhead:\s15\s(Repair)/gi;
	$line =~ s/Warhead:\s16/Warhead:\s16\s(IonCannon)/gi;
	$line =~ s/Warhead:\s17/Warhead:\s17\s(Nuke)/gi;
	$line =~ s/Warhead:\s18/Warhead:\s18\s(Fire)/gi;
	$line =~ s/Warhead:\s19/Warhead:\s19\s(Chem)/gi;
	$line =~ s/Warhead:\s20/Warhead:\s20\s(Electric)/gi;
	$line =~ s/Warhead:\s21/Warhead:\s21\s(Visceroid)/gi;
	$line =~ s/Warhead:\s22/Warhead:\s22\s(Earth)/gi;
	$line =~ s/Warhead:\s23/Warhead:\s23\s(RegenHealth)/gi;
	$line =~ s/Warhead:\s24/Warhead:\s24\s(BlamoKiller)/gi;
	$line =~ s/Warhead:\s25/Warhead:\s25\s(Death)/gi;
	$line =~ s/Warhead:\s26/Warhead:\s26\s(Harmless)/gi;
	$line =~ s/Warhead:\s27/Warhead:\s27\s(CNC_Flamethrower)/gi;
	$line =~ s/Warhead:\s28/Warhead:\s28\s(CNC_Chem)/gi;
	
	return $line;
}



########### Event handlers

# Runs when BRenBot loads
sub start
{
	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
	my %args = %{$args};
	
	# Set our current version in the globals table
	plugin::set_global ( "version_plugin_biatch", $pluginVersion );
}

# Runs when BRenBot exits
sub stop
{
	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
	my %args = %{$args};
}

# Runs when one of this plugins commands is used
sub command
{
	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
	my %args = %{$args};
	
	# Any commands from IRC or ingame come here
	# From here we should trigger the appropriate subroutine
	if ( $args{command} eq "trust" )
	{
		$kernel->yield( "trust" => \%args );
	}
	elsif ( $args{command} eq "untrust" )
	{
		$kernel->yield( "untrust" => \%args );
	}
	elsif ( $args{command} eq "antiaimbot" )
	{
		$kernel->yield( "antiaimbot" => \%args );
	}
}



# Return true or the bot will not work properly...
1;