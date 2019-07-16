#
# Jukebox plugin for BRenBot 1.52 by danpaul88
# Plays tracks from always.dat
#

package jukebox;
use POE;
use plugin;
use strict;

# Name and config are defined by BRenBot's plugin interface
our %additional_events = ( "mainStart" => "mainStart", "playNext" => "playNext", 
	"nexttrack" => "playTrack", "settrack" => "setTrack", "music" => "music" );
our $plugin_name;
our %config;

my $pluginVersion = 1.0;

my $enabledTracks = 0;
my $nowPlaying = undef;
my $nextTrackStart = 0;
my %tracks = (
	"0" => "ammoclip.mp3",						"1" => "command&conquer.mp3",			"2" => "defunkt.mp3",
	"3" => "in the line of fire.mp3",			"4" => "level0_pt1_music.mp3",			"5" => "level 0 hero.mp3",
	"6" => "level 0 nod base.mp3",				"7" => "level 0 tank.mp3",				"8" => "level 0 tiberium.mp3",
	"9" => "mechmansrevenge.mp3",				"10" => "moveit.mp3",					"11" => "onyourfeet.mp3",
	"12" => "raveshaw_act on instinct.mp3",		"13" => "renegadejungle.mp3",			"14" => "sakura battle theme.mp3",
	"15" => "sakura_dogfight.mp3",				"16" => "sneakattack.mp3",				"17" => "sniper.mp3",
	"18" => "stopthemagain.mp3"
);
my %trackLengths = (
	"0" => "193",								"1" => "175",							"2" => "163",
	"3" => "235",								"4" => "26",							"5" => "31",
	"6" => "54",								"7" => "51",							"8" => "47",
	"9" => "277",								"10" => "121",							"11" => "234",
	"12" => "148",								"13" => "141",							"14" => "240",
	"15" => "280",								"16" => "228",							"17" => "196",
	"18" => "234"
);




########### Event handlers

# Runs when BRenBot loads the plugin
sub start
{
	my ( $kernel ) = @_[KERNEL];
	
	# Set our current version in the globals table
	plugin::set_global ( "version_plugin_jukebox", $pluginVersion );
	
	# Check there is at least one track that is not disabled in options
	my $i;
	for ( $i = 0; $i < 19; $i++ ) { if ( $config{$tracks{$i}} != 0 ) { $enabledTracks++; } }
	
	if ( $enabledTracks == 0 ) { print "JUKEBOX PLUGIN: All tracks are disabled! Plugin disabled."; }
	
	# Trigger the mainStart event in 5 seconds (give brenbot enough time to get the playerlist)
	$kernel->delay ( "mainStart", 5 );
}

# Runs 5 seconds after loading - initialises everything
sub mainStart
{
	# Get the number of GDI and Nod players, if either is >0 then start music
	my ( undef, undef, $gdiPlayers, undef, $nodPlayers, undef, undef, undef, undef, undef ) = plugin::getGameStatus();
	if ( $gdiPlayers > 0 || $nodPlayers > 0 )
	{
		# Set default state for all players (might not have bhs version number yet)
		my %playerlist = plugin::get_playerlist();
		while ( my ( $id, $player ) = each ( %playerlist ) )
		{
			playerData::setKeyValue ( $id, 'playMusic', $config{'defaultState'} );
		}
		
		# Start playing music
		playTrack();
	}
}


# Runs when BRenBot shuts down
sub stop
{
	# Stop all music
	my %playerlist = plugin::get_playerlist();
	while ( my ( $id, $player ) = each ( %playerlist ) )
	{
		if ( $player->{'bhsVersion'} >= 2.0 && $player->{'playMusic'} != 0 )
			{ plugin::RenRemCMD ( "NOMUSICP $id" ); }
	}
}

# Map loaded - start new track after 5 second delay
sub mapload
{
	# Get the number of GDI and Nod players, if either is >0 then start music
	my ( undef, undef, $gdiPlayers, undef, $nodPlayers, undef, undef, undef, undef, undef ) = plugin::getGameStatus();
	if ( $gdiPlayers > 0 || $nodPlayers > 0 )
	{ playTrack(5); }
	
	# Otherwise set $nowPlaying to null
	else
	{ undef $nowPlaying; }
}


# Player joined - set their music state to the default state
sub playerjoin
{
	my ( $kernel, $args ) = @_[ KERNEL, ARG0 ];
	my %args = %{$args};
	
	# If music is not running then start it after 2 seconds
	if ( !defined($nowPlaying) ) { playTrack(2); }
	
	playerData::setKeyValue ( $args{'nick'}, 'playMusic', $config{'defaultState'} );
	
	# If default state is enabled start playing the current track (it will end early, but
	# its either that or wait till the next track starts for them to hear any music...)
	if ( $config{'defaultState'} == 1 && defined($nowPlaying) )
	{
		my ( $result, %player ) = plugin::getPlayerData ( $args{'nick'} );
		if ( $result == 1 && $player{'bhsVersion'} >= 2.0 )
			{ plugin::RenRemCMDtimed ( "MUSICP $player{id} $tracks{$nowPlaying}", 1 ); }
	}
}


# Command event - Triggers on any !command which is in this plugins XML file
sub command
{
	my ( $kernel, $args ) = @_[ KERNEL, ARG0 ];
	my %args = %{$args};
	
	# Trigger the event with the same name as the command
	$kernel->yield ( $args{'command'} => \%args );
}






########### Command functions

# Plays a specific track
sub setTrack
{
	my ( $kernel, $args ) = @_[ KERNEL, ARG0 ];
	my %args = %{$args};
	
	if ( $args{'arg1'} )
	{
		# Play track by ID
		if ( $args{'arg1'} =~ m/^\d+$/i )
		{
			if ( $1 < 19 && $1 >= 0 ) { playTrack(0,$1); }
			return;
		}
		
		# Play track by name
		else
		{
			for ( my $i = 0; $i < 19; $i++ )
			{
				if ( $tracks{$i} =~ m/$args{arg1}/i ) { playTrack(0,$i); return; }
			}
			
			if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( "There are no tracks with $args{arg1} in the name", $args{'ircChannelCode'} ); }
			else { plugin::pagePlayer ( $args{'nick'}, "BRenBot", "There are no tracks with $args{arg1} in the name" ); }
		}
	}
	else
	{
		if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( "Usage: !setTrack <id/track>", $args{'ircChannelCode'} ); }
		else { plugin::pagePlayer ( $args{'nick'}, "BRenBot", "Usage: !setTrack <id/track>" ); }
	}
}


# Music command, turns music on or off for the player using it
sub music
{
	my ( $kernel, $args ) = @_[ KERNEL, ARG0 ];
	my %args = %{$args};
	
	# Return if used from IRC, or there is no track playing (IE: Nothing TO play)
	return if ( $args{'nicktype'} == 1 );
	return if ( !(defined($nowPlaying)) );
	
	my ( $result, %player ) = plugin::getPlayerData ( $args{'nick'} );
	return if ( $result != 1 );
	
	if ( lc($args{'arg1'}) eq 'on' )
	{
		if ( $player{'bhsVersion'} >= 2.0 )
		{
			playerData::setKeyValue ( $player{'id'}, 'playMusic', 1 );
			plugin::RenRemCMDtimed ( "MUSICP $player{id} $tracks{$nowPlaying}", 1 );
			plugin::pagePlayer ( $player{'id'}, "BRenBot", "The jukebox has been enabled for you." );
		}
		else { plugin::pagePlayer ( $player{'id'}, "BRenBot", "You must have scripts.dll 2.0 or higher to use the jukebox!" ); }
	}
	elsif ( lc($args{'arg1'}) eq 'off' )
	{
		playerData::setKeyValue ( $player{'id'}, 'playMusic', 0 );
		plugin::RenRemCMDtimed ( "NOMUSICP $player{id}" );
		plugin::pagePlayer ( $player{'id'}, "BRenBot", "The jukebox has been disabled for you." );
	}
	else
	{
		plugin::pagePlayer ( $player{'id'}, "BRenBot", "Usage: !music <on/off>" );
	}
}






###### playNext();
###### Called by an alarm signal from the POE kernel. Will play a new track
###### if the times for the next track to start match the one in this call
sub playNext
{
	my ( $scheduledTime ) = @_[ARG0];
	
	# Get the number of GDI and Nod players
	my ( undef, undef, $gdiPlayers, undef, $nodPlayers, undef, undef, undef, undef, undef ) = plugin::getGameStatus();
	
	# If times dont match the map changed, so wait for the next alarm. Otherwise
	# play a new track. Also only run if there is a player ingame.
	if ( $nextTrackStart == $scheduledTime && ( $gdiPlayers > 0 || $nodPlayers > 0 ) )
		{ playTrack(); }
}



###### playTrack()
###### Randomly picks a track to play from the tracks list, or plays the track specified
sub playTrack
{
	my $delay = shift;
	my $track = shift;
	if ( !(defined($delay)) ) { $delay = 0; }
	
	# Return if $enabledTracks == 0
	return if ($enabledTracks == 0);
	
	# Now pick a number between 0 and 18 (19 possible numbers in total)
	srand();		# Seed random number generator
	my $trackNumber = ( defined ($track) ) ? $track : int(rand(19));
	
	# Loop until we find a non-disabled track that does not match the last played
	# track (unless there is only 1 track enabled). Do not loop if $trackNumber is defined.
	while ( !(defined($track)) && $config{$tracks{$trackNumber}} == 0 && ( $enabledTracks == 1 || $trackNumber != $nowPlaying ) )
	{ $trackNumber = int(rand(19)); }
	
	# Play track
	$nowPlaying = $trackNumber;
	plugin::RenRemCMDtimed ( "msg [BR Jukebox] Now Playing: $tracks{$trackNumber}", $delay );
	
	# Play for CP1 and above clients only
	my %playerlist = plugin::get_playerlist();
	while ( my ( $id, $player ) = each ( %playerlist ) )
	{
		if ( $player->{'bhsVersion'} >= 2.0 && $player->{'playMusic'} != 0 )
			{ plugin::RenRemCMDtimed ( "MUSICP $id $tracks{$trackNumber}", $delay ); }
	}
	
	# Schedule a new track for when this one finishes
	$nextTrackStart = int(time()+$trackLengths{$trackNumber});
	$poe_kernel->alarm ( "playNext" => $nextTrackStart => $nextTrackStart );
}