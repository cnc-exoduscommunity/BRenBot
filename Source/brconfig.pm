#!/usr/bin/perl

package brconfig;
use strict;

use modules;
use RenRem;
use File::HomeDir;							# For scripts.dll 4.0 when paths.ini is NOT set to UseRenFolder

our $starttime;
our $serverScriptsVersion                 = '0.0';
our $serverScriptsRevision                = '0';
our $configfile                           = "brenbot.cfg";
our $config_botmode;

# IRC basic settings
our $config_botname;
our $config_botfullname                   = "BRenBot " . main::BR_VERSION;
our $config_ircserver;
our $config_ircport;
our $irc_adminChannel;
our $irc_adminChannel_key                 = "";
our $irc_publicChannel                    = "";
our $irc_publicChannel_key                = "";
our $irc_charsPerSecond                   = 4000;
our $irc_prefixIRCMessages                = 0;    # Hidden config option
our $irc_showTeamMessages_PublicChan      = 0;

# IRC NickServ / Qauth settings
our $irc_nickserv_auth                    = "";
our $irc_nickserv_name                    = "Nickserv";
our $config_q_auth;
our $config_q_username;
our $config_q_password;
our $irc_operUser                         = "";
our $irc_operPass                         = "";

# GSA Settings
our $config_gamespyqueryport;
our $config_generate_gamespy_queries      = 0;
our $config_broadcast_to_gamespy          = 0;
our $config_gamespy_ip                    = 0;
our $config_gamespy_gameport;
our $config_gamespy_broadcast_website     = '';
our $config_gamespy_broadcast_irc         = '';
our $config_gamespy_broadcast_teamspeak   = '';
our $config_gamespy_broadcast_ventrilo    = '';


# Filename Settings
our $config_autoannouncefile              = "autoannounce.cfg";
our $config_messagesfile                  = "messages.cfg";
our $config_moderatorsfile                = "moderators.cfg";
our $config_presetsfile                   = "presets.cfg";
our $config_fdsconfigfile;
our $config_fdspath;
our $config_fdslogpath;
our $config_kicklogfile                   = "kicklog.log";
our $config_banlogfile                    = "banlog.log";
our $config_misclogfile                   = "misclog.log";

# Other Settings
our $config_autoannounceinterval          = "600";
our $config_enableladderlookup            = "0";
our $config_vehiclekick                   = "0";
our $config_renrem_host                   = "127.0.0.1";
our $config_renrem_port;
our $config_renrem_password;
our $config_reserved_slots;
our $config_reserved;
our $reserved_slots_active                = '0';

our $config_redirect_port;
our $config_redirect;
our $config_minimum_scripts_version       = '0';
our $config_force_bhs_dll_map             = '0';
our $enable_gamelog_loaded_check          = '1';
our $enableCmsg                           = '1';    # Enable CMSG paging

# Settings for moderators
our $config_moderators_force_auth         = '1';
our $config_moderator_symbols             = '1';
our $config_temp_mod_symbol               = '+';
our $config_half_mod_symbol               = '%';
our $config_full_mod_symbol               = '@';
our $config_admin_symbol                  = '&';
our $show_mod_join_message                = 1;

# Gamelog settings
our $gamelog_show_vehicle_purchase        = '1';
our $gamelog_show_vehicle_stolen          = '1';
our $gamelog_showCrateMsgs                = '1';
our $gamelog_showKillMsgs                 = '1';
our $gamelog_showVehicleKillMsgs          = '1';
our $gamelog_showBuildingKillMsgs         = '1';

# Voting settings
our $config_votingenabled                 = '1';
our $config_votingperiod                  = '60';
our $config_voting_allow_nextmap          = '1';
our $config_voting_allow_gameover         = '1';
our $config_voting_allow_kick             = '1';

# SSGM settings - read from ssgm.ini
our $ssgm_version                         = 0;
our $ssgm_logging_port                    = 8080;
our $gamelog_in_ssgm                      = 0;      # If this is set to 1 we don't need to tail gamelog, it's in ssgm instead
our $ssgmLogPrefix                        = "ssgm"; # Prefix for the ssgm logs

# Server settings - read from svrcfg_cnc.ini
our $server_timelimit                     = 0;      # If this is 0 we shouldn't enforce the 3 second restriction on setnextmap
our %server_rules;




our @messages;
our %halfMods;      # Hash to hold half moderators
our %fullMods;      # Hash to hold full moderators
our %admins;        # Hash to hold administrators
our @autoannounce;
our @maplist;
our @installed_maps;




# Loads all config data
sub init
{
  ReadConfig();
  read_server_configuration();
  read_ssgm_settings();
  ReadAutoAnnounce();
  ReadMessages();
  readMods();
  readServerSettings();
  GetAvailableMaps();

  #gamelog::loadAreaData();
  gamelog::loadPresets();

  modules::loadMapSettings();
  brTeams::read_config();

  checkBrenbotDll();
}



# Read server.ini
sub read_server_configuration
{
	open ( FILE, $config_fdspath . "server.ini" )  or die ( $config_fdspath . "server.ini not found!\n" );
	while ( <FILE> )
	{
		#AllowRemoteAdmin = true
		if ($_ =~ m/AllowRemoteAdmin\s*=\s*(.+)/)
		{
			if ( lc($1) ne 'true' && $1 ne '1' )
				{ modules::console_output ( '[Config] WARNING: AllowRemoteAdmin option in server.ini is not set to true. BRenBot will not be able to communicate properly with the server!' ); }
		}

		# RemoteAdminPassword = password
		if ($_ =~ m/RemoteAdminPassword\s*=\s*(.+)/)
		{
			if ( length( $1 ) != 8 )
				{ modules::console_output ( '[Config] WARNING: RemoteAdminPassword must be 8 characters long! BRenBot will not be able to communicate properly with the server!' ); }
			else
				{ $config_renrem_password = $1; }
		}

		# RemoteAdminPort = 4949
		if ($_ =~ m/RemoteAdminPort\s*=\s*(\d+)/)
		{
			$config_renrem_port = $1;
		}

		if ($_ =~ m/GameSpyGamePort\s*=\s*(\d+)/)
		{
			$config_gamespy_gameport = $1;
		}

		if ($_ =~ m/Port\s*=\s*(\d+)/)
		{
			# If we don't have a GSA gameport set use this port, if we later
			# find a GSA entry it will overwrite this setting.
			if ( !$config_gamespy_gameport)
			{
				$config_gamespy_gameport = $1;
			}
		}
	}


	# Check remote admin port and password were OK
	if ( !$config_renrem_port or !$config_renrem_password )
	{
		modules::console_output ( "[Config] ERROR: Unable to load RemoteAdminPort and/or RemoteAdminPassword from server.ini.\n\nUnable to continue loading." );
		sleep ( 10 );
		exit;
	}
}


# Read brenbot.cfg
sub ReadConfig
{
	my $fh;
	open ( $fh, $configfile ) or die "Config_File_Read: $!,";
	while ( <$fh> )
	{
		if ( $_ !~ m/^\#/ && $_ !~ m/^\s+$/ )		# If the line starts with a hash or is blank ignore it
		{
			if (/^\s*BotMode\s*=\s*(.+)/i)								{ $config_botmode = $1; chomp $config_botmode; }

			# IRC basic settings
			if (/^\s*BotName\s*=\s*(.+)/i)								{ $config_botname = $1; chomp $config_botname; }
			if (/^\s*BotFullName\s*=\s*(.+)/i)							{ $config_botfullname = $1; chomp $config_botfullname; }
			if (/^\s*IrcServer\s*\=\s*(\S+)/i)							{ $config_ircserver = $1; }
			if (/^\s*IrcPort\s*=\s*(\d+)/i)								{ $config_ircport = $1; }
			if (/^\s*ircAdminChannel\s*=\s*(\S+)/i ||
				/^\s*IrcChannel\s*=\s*(\S+)/i )							{ $irc_adminChannel = $1; }
			if (/^\s*ircAdminChannelKey\s*=\s*(\S+)/i ||
				/^\s*IrcChannelKey\s*=\s*(\S+)/i )						{ $irc_adminChannel_key = $1; }
			if (/^\s*ircPublicChannel\s*=\s*(\S+)/i)					{ $irc_publicChannel = $1; }
			if (/^\s*ircPublicChannelKey\s*=\s*(\S+)/i)					{ $irc_publicChannel_key = $1; }
			if (/^\s*ircCharsPerSecond\s*=\s*(\d+)/i)					{ $irc_charsPerSecond = $1; }
			if (/^\s*prefixIRCMessages\s*=\s*(1|0)/i)					{ $irc_prefixIRCMessages = $1; }
			if (/^\s*showTeamChatInPublicChan\s*=\s*(1|0)/i)			{ $irc_showTeamMessages_PublicChan = $1; }

			# IRC NickServ / Qauth settings
			if (/^\s*Nickservname\s*=\s*(\S+)/i)						{$irc_nickserv_name = $1; }
			if (/^\s*Nickservauth\s*=\s*(.+)/i)							{$irc_nickserv_auth = $1; }
			if (/^\s*Qauth\s*=\s*(1|0)/i)								{$config_q_auth = $1; }
			if (/^\s*Qusername\s*=\s*(\S+)/i)							{$config_q_username = $1; }
			if (/^\s*Qpassword\s*=\s*(\S+)/i)							{$config_q_password = $1; }

			if ( /^\s*operAuthUser\s*=\s*(\S+)/i )						{ $irc_operUser = $1; }
			if ( /^\s*operAuthPass\s*=\s*(\S+)/i )						{ $irc_operPass = $1; }

			# GSA Settings
			if (/^\s*Generate_Gamespy_Queries\s*=\s*(.+)/i)				{$config_generate_gamespy_queries = $1; }
			if (/^\s*Broadcast_Server_To_Gamespy\s*=\s*(.+)/i)			{$config_broadcast_to_gamespy = $1; }
			if (/^\s*Gamespy_IP\s*=\s*(.+)/i)							{$config_gamespy_ip = $1; }
			if (/^\s*GameSpyQueryPort\s*=\s*(\S+)/i)					{$config_gamespyqueryport = $1; }
			if (/^\s*GameSpy_Broadcast_Website\s*=\s*(.+)/i)			{$config_gamespy_broadcast_website = $1; }
			if (/^\s*GameSpy_Broadcast_IRC\s*=\s*(.+)/i)				{$config_gamespy_broadcast_irc = $1; }
			if (/^\s*GameSpy_Broadcast_Teamspeak\s*=\s*(.+)/i)			{$config_gamespy_broadcast_teamspeak = $1; }
			if (/^\s*GameSpy_Broadcast_Ventrilo\s*=\s*(.+)/i)			{$config_gamespy_broadcast_ventrilo = $1; }

			# Filename Settings
			if (/^\s*AutoAnnounceFile\s*=\s*(\S+)/i)					{ $config_autoannouncefile = $1; }
			if (/^\s*MessagesFile\s*=\s*(\S+)/i)						{ $config_messagesfile = $1; }
			if (/^\s*ModeratorsFile\s*=\s*(\S+)/i)						{ $config_moderatorsfile = $1; }
			if (/^\s*PresetsFile\s*=\s*(\S+)/i)							{ $config_presetsfile = $1; }
			if (/^\s*FDSConfigFile\s*=\s*(.+)/i)						{ $config_fdsconfigfile = $1; }
			if (/^\s*FDSLogFilePath\s*=\s*(.+)/i)						{ $config_fdspath = $1; }
			if (/^\s*KickLogFile\s*=\s*(\S+)/i)							{ $config_kicklogfile = $1; }
			if (/^\s*BanLogFile\s*=\s*(\S+)/i)							{ $config_banlogfile = $1; }
			if (/^\s*MiscLogFile\s*=\s*(\S+)/i)							{ $config_misclogfile = $1; }

			# Other Settings
			if (/^\s*AutoAnnounceInterval\s*=\s*(\d+)/i)				{$config_autoannounceinterval = $1; }
			if (/^\s*EnableLadderLookup\s*=\s*(0|1)/i)					{$config_enableladderlookup = $1; }
			if (/^\s*VehicleKick\s*=\s*(0|1)/i)							{$config_vehiclekick = $1; }
			if (/^\s*ReservedSlots\s*=\s*(.+)/i)						{$config_reserved_slots = $1; }
			if (/^\s*ReservedSlotsEnabled\s*=\s*(.+)/i)					{$config_reserved = $1; }
			if (/^\s*Redirect\s*=\s*(.+)/i)								{$config_redirect = $1; }
			if (/^\s*RedirectPort\s*=\s*(.+)/i)							{$config_redirect_port = $1; }
			if (/^\s*Minimum_Scripts_Version\s*=\s*(\d+(\.\d+)?)/i)		{$config_minimum_scripts_version = $1; }
			if (/^\s*Enable_Gamelog_Loaded_Checks\s*=\s*(1|0)/i)		{$enable_gamelog_loaded_check = $1; }
			if (/^\s*Enable_CMSG_Paging\s*=\s*(0|1)/i)					{ $enableCmsg = $1; }

			# Settings for moderators
			if (/^\s*Moderators_Force_Auth\s*=\s*(\d)/i)				{ $config_moderators_force_auth = $1; }
			if (/^\s*Moderators_Show_Symbols\s*=\s*(\d)/i)				{ $config_moderator_symbols = $1; }
			if (/^\s*Moderators_Temp_Mod_Symbol\s*=\s*(\S+)/i)			{ $config_temp_mod_symbol = $1; }
			if (/^\s*Moderators_Half_Mod_Symbol\s*=\s*(\S+)/i)			{ $config_half_mod_symbol = $1; }
			if (/^\s*Moderators_Full_Mod_Symbol\s*=\s*(\S+)/i)			{ $config_full_mod_symbol = $1; }
			if (/^\s*Moderators_Admin_Symbol\s*=\s*(\S+)/i)				{ $config_admin_symbol = $1; }
			if (/^\s*Moderators_Show_Join_Message\s*=\s*(0|1)/i)		{ $show_mod_join_message = $1; }

			# Gamelog settings
			if (/^\s*Gamelog_Show_Vehicle_Purchase\s*=\s*(\d)/i)		{ $gamelog_show_vehicle_purchase = $1; }
			if (/^\s*Gamelog_Show_Vehicle_Stolen\s*=\s*(\d)/i)			{ $gamelog_show_vehicle_stolen = $1; }
			if (/^\s*Gamelog_Show_Crate_Messages\s*=\s*(\d)/i)			{ $gamelog_showCrateMsgs = $1; }
			if (/^\s*Gamelog_Show_Kill_Messages\s*=\s*(\d)/i)			{ $gamelog_showKillMsgs = $1; }
			if (/^\s*Gamelog_Show_Vehicle_Kill_Messages\s*=\s*(\d)/i)	{ $gamelog_showVehicleKillMsgs = $1; }
			if (/^\s*Gamelog_Show_Building_Kill_Messages\s*=\s*(\d)/i)	{ $gamelog_showBuildingKillMsgs = $1; }

			# Voting settings
			if (/^\s*VotingEnabled\s*=\s*(\d)/i)						{ $config_votingenabled = $1; }
			if (/^\s*VotingPeriod\s*=\s*(\d+)/i)						{ $config_votingperiod = $1; }
			if (/^\s*Voting_Allow_Change_Nextmap \s*=\s*(\d)/i)			{ $config_voting_allow_nextmap = $1; }
			if (/^\s*Voting_Allow_Gameover \s*=\s*(\d)/i)				{ $config_voting_allow_gameover = $1; }
			if (/^\s*Voting_Allow_Kick \s*=\s*(\d)/i)					{ $config_voting_allow_kick = $1; }
		}
	}
  
  
  # Make GSA strings safe to broadcast (strip out \ characters)
  $config_gamespy_broadcast_website =~ s!\\!/!g;
  $config_gamespy_broadcast_irc =~ s!\\!/!g;
  $config_gamespy_broadcast_teamspeak =~ s!\\!/!g;
  $config_gamespy_broadcast_ventrilo =~ s!\\!/!g;


	# Give errors on variables which MUST be provided by the config file, and cannot
	# use default settings.
	my $config_error;
	$config_error .= "BotName " if (!$config_botname);
	$config_error .= "IrcServer " if (!$config_ircserver);
	$config_error .= "IrcPort " if (!$config_ircport);
	$config_error .= "ircAdminChannel " if (!$irc_adminChannel);
	$config_error .= "FDSConfigFile " if (!$config_fdsconfigfile);
	$config_error .= "FDSLogFilePath " if (!$config_fdspath);

	if (!$config_botmode)
	{
		$config_botmode = "LFDS";
	}

	if ( ($config_botmode ne "LFDS")  && ($config_botmode ne "WIN32") )
	{
		modules::console_output ( "[Config] ERROR: BotMode must be either LFDS or WIN32!" );
		sleep ( 10 );
		exit;
	}

	if ( ($config_botmode eq "LFDS") && ($^O eq "MSWin32") )
	{
		modules::console_output ( "[Config] ERROR: BotMode = LFDS and running Windows? Eh. No. n00b." );
		sleep ( 10 );
		exit;
	}

	if ( ($config_botmode eq "WIN32") && ($^O eq "linux") )
	{
		modules::console_output ( "[Config] ERROR: BotMode = WIN32 and running Linux? Eh. No. n00b." );
		sleep ( 10 );
		exit;
	}

	$config_error .= "Qauth " if (length($config_q_auth) == 0);
	if ($config_q_auth == 1)
	{
		$config_error .= "Qusername " if (!$config_q_username);
		$config_error .= "Qpassword " if (!$config_q_password);
	}

	if ($config_error)
	{
		modules::console_output ( "[Config] ERROR: Missing config file option(s): $config_error" );
		sleep ( 10 );
		exit;
	}

	close $fh;
}


# Reads the svrcfg_cnc.ini file
sub readServerSettings
{
	my $ServerConfigFile;

	# Clear out the maplist (rotation) prior to repopulating it
	@maplist = ();
  
  # Set default game rules for GSA
  $server_rules{'driver_gunner'} = 0;
  $server_rules{'friendly_fire'} = 0;
  $server_rules{'team_changing'} = 0;
  $server_rules{'credits'} = 0;


	# Set defaults
	serverStatus::updateIsPassworded ( 0 );

	open ( ServerConfigFile, $config_fdsconfigfile );
	while ( <ServerConfigFile> )
	{
		if ( /^bGameTitle\s*=\s*(.+)/ )
		{
			serverStatus::updateGameTitle ( $1 );
		}

		# svrcfg_cnc.ini map definitions are only used prior to SSGM 4.0
		if ( $ssgm_version < 4 && /^MapName(\d\d)\s*=\s*(\S+)/ )
		{
			chomp(my $mapname=$2);
			my %hash;
			$hash{'mapname'} = $mapname;
			$hash{'id'} = $1;
			push (@maplist, \%hash);
		}

		# svrcfg_cnc.ini map definitions are only used prior to SSGM 4.0
		if ( $ssgm_version < 4 && /^MapName\s*=\s*(\S+)/ )
		{
			serverStatus::updateStartMap ( $1 );
		}

		if ( /^MaxPlayers\s*=\s*(\d+)/ )
		{
			serverStatus::updateDefaultMaxPlayers ( $1 );
		}

		if ( /^IsPassworded\s*=\s*yes/ )
		{
			serverStatus::updateIsPassworded ( 1 );
		}

		# Read time limit		TimeLimitMinutes=30
		if ( /^TimeLimitMinutes\s*=\s*(\d+)/ )
		{
			$server_timelimit = $1;
		}

		if (/^DriverIsAlwaysGunner\s*=\s*yes/)
		{
			$server_rules{'driver_gunner'} = 1;
		}

		if (/^IsFriendlyFirePermitted\s*=\s*yes/)
		{
			$server_rules{'friendly_fire'} = 1;
		}

		if (/^IsTeamChangingAllowed\s*=\s*yes/)
		{
			$server_rules{'team_changing'} = 1;
		}

		if (/^StartingCredits\s*=\s*(\S+)/)
		{
			chomp(my $startingcredits = $1 );
			$server_rules{'credits'} = $startingcredits;
		}
		if (/^RadarMode\s*=\s*(\S+)/)
		{
			chomp(my $radarmode = $1 );
			serverStatus::updateRadarMode( $radarmode );
		}

	}
	close ( ServerConfigFile );



	# If using SSGM 4.0 then read the map rotation from the tt.cfg file
	if ( $ssgm_version >= 4 )
	{
		my $ttConfigFile;
		my $mapRotationIdx = -1;

		open ( ttConfigFile, $config_fdspath."/tt.cfg" );
		while ( <ttConfigFile> )
		{
			# Start of map rotation section?
			if ( /^rotation\:$/ )
			{
				$mapRotationIdx = 0;
			}

			# End of map rotation section?
			elsif ( $mapRotationIdx >= 0 && /^\];$/ )
			{
				$mapRotationIdx = -1;
			}

			elsif ( $mapRotationIdx >= 0 && /^\s*\"(.+)\"\,?$/ )
			{
				chomp(my $mapname=$1);
				my %hash;
				$hash{'mapname'} = $mapname;
				$hash{'id'} = $mapRotationIdx;
				push (@maplist, \%hash);

				# Increment map rotation def index
				$mapRotationIdx++;
			}
		}
		close ( ttConfigFile );
	}
}


# If using SSGM 4.0 this sends a RenRemCMD to get the list of available game definitions, otherwise
# it searches for available maps in the data folder
sub GetAvailableMaps
{
	@installed_maps = ();

	if ( $ssgm_version >= 4 )
	{
		# NB: We don't just read this from tt.cfg because the gamedefs can also include
		# things which are not listed in that config file. Use a short delay otherwise
		# the response comes back before we are listening for it
		RenRem::RenRemCMDtimed("listgamedefs",2);
	}
	else
	{
		my $datadir = $config_fdsconfigfile;
		use File::Basename;
		my $name;
		my $path;
		my $suffix;

		($name,$path,$suffix) = fileparse($datadir);

		unless(opendir(DATADIR, $path))
		{
			modules::console_output ( "[Config] Error getting available maps: Cannot read directory $path! Trying anyway.." );
		}

		@installed_maps = grep(/\.mix/i,readdir(DATADIR));
	}
}


# Reads the auto announce file
sub ReadAutoAnnounce
{
	# Set length of autoannouce array to -1 to clear it and destroy content
	$#autoannounce = -1;

	open (AAFile, $config_autoannouncefile);
	while (<AAFile>)
	{
		$_ =~ s/\n//g;
		$_ =~ s/\r//g;

		push (@autoannounce, $_);
	}

	close (AAFile);
}

sub ReadMessages
{
	# Set length of messages array to -1 to clear it and destroy content
	$#messages = -1;

	open ( MSGSFile, $config_messagesfile );
	while (<MSGSFile>)
	{
		$_ =~ s/\n//g;
		$_ =~ s/\r//g;

		push (@messages, $_);
	}

	close (MSGSFile);
}

sub readMods
{
	my $currentSection = 0;

	# Clear existing lists if they already exist
	%admins = ();
	%halfMods = ();
	%fullMods = ();

	eval
	{
		open ( MODSFILE, $config_moderatorsfile );
		while ( <MODSFILE> )
		{
			if ( $_ !~ m/^\#/ && $_ !~ m/^\s+$/ )		# If the line starts with a hash or is blank ignore it
			{
				if ( $_ =~ m/\[(|ADMINS|HALF_MODS|FULL_MODS)\]/i )
				{
					$currentSection = uc($1);
				}
				elsif ( $currentSection )
				{
					if ( $_ =~ m/(.+)/ )
					{
						my $lc_name = lc($1);
						if ( $currentSection eq "ADMINS" ) { $admins{$lc_name} = $1; }
						elsif ( $currentSection eq "HALF_MODS" ) { $halfMods{$lc_name} = $1; }
						elsif ( $currentSection eq "FULL_MODS" ) { $fullMods{$lc_name} = $1; }
					}
				}
			}
		}
		close ( MODSFILE );
	}
	or modules::display_error($@);
}



# Looks for ssgm.ini, and if found gets any settings we need from it
sub read_ssgm_settings
{
	my $ssgmini = 0;
	
	if ( -e $config_fdspath . "ssgm.ini" )
	{
		if ( -e $config_fdspath . "tt.cfg" )
			{ $ssgm_version = 4; }
		else
			{ $ssgm_version = 2; }
		$ssgmini = $config_fdspath . "ssgm.ini";
	}
	elsif ( -e $config_fdspath . "ssaow.ini" )
	{
		$ssgm_version = 1;
		$ssgmini = $config_fdspath . "ssaow.ini";
	}
	elsif ( -e $config_fdspath . "ssapb.ini" )
	{
		$ssgm_version = 1;
		$ssgmini = $config_fdspath . "ssapb.ini";
	}
  else
  {
    $ssgm_version = 0;
    $config_fdslogpath = $config_fdspath;
    modules::console_output ( "[Config] Unable to find any of ssgm.ini, ssaow.ini or ssapb.ini! Some functions may not work." );
    return;
  }

	modules::console_output ( "[Config] Detected SSGM version $ssgm_version\n" );


	# Open ssgm.ini, or bail out
	my $ssgm_ini_section = "";
	open ( SSGMFILE, $ssgmini ) or return(0);
	while ( <SSGMFILE> )
	{
		if ( $ssgm_version >= 4 && $_ =~ m/^\[(.+)\]$/i )
		{
			$ssgm_ini_section = lc($1);
			next;
		}


		# Write_Gamelog_to_SSAOWlog=1
		# Renamed to WriteGamelogtoSSGMlog in ssgm 2.0
		if ( $_ =~ m/^Write_Gamelog_to_SSAOWlog\s?=\s?(\d)/i
			|| $_ =~ m/^WriteGamelogtoSSGMlog\s?=\s?(\d)/i )
		{
			$gamelog_in_ssgm = $1;
		}


		# Enable_Gamelog=1
		# Renamed to EnableGamelog in ssgm 2.0
		# Enable_NewGamelog=1
		# Renamed to EnableNewGamelog in ssgm 2.0
		# EnableLog
		if ( $_ =~ m/(Enable_NewGamelog)\s?=\s?0/i
			|| $_ =~ m/(EnableNewGamelog)\s?=\s?0/i
			|| $_ =~ m/(Enable_Gamelog)\s?=\s?0/i
			|| $_ =~ m/(EnableGamelog)\s?=\s?0/i
			|| $_ =~ m/(EnableLog)\s?=\s?0/i )
		{
			modules::console_output ( "[Config] WARNING: $1 option in $ssgmini is disabled, the gamelog and ssgmlog modules may not work correctly." );
		}


		# FDSLogRoot=ssgm
		if( $_ =~ m/FDSLogRoot\s?=\s?(.+)/i )
		{
			$ssgmLogPrefix = $1;
		}


		# Port=#
		# Port number for SSGM 4.0 TCP logging
		if( $ssgm_version >= 4 && $ssgm_ini_section eq 'general'
			&& $_ =~ m/Port\s?=\s?(\d+)/i )
		{
			$ssgm_logging_port = $1;
		}
	}
	close ( SSGMFILE );





	# If SSGM 4.0 or higher is installed look for data/paths.ini. If it exists this
	# will determine where to look for log and results files...
	if ( $ssgm_version >= 4 && open ( FILE, $config_fdspath . "/data/paths.ini" )  )
	{
		modules::console_output ( "[Config] Found data/paths.ini, reading logfile path... ", 1 );
		my $pathsSection = "";
		my $filebase = "";
		my $filefds = "";
		my $useRenFolder = 0;

		# Parse INI file
		while ( <FILE> )
		{
			if ( $_ =~ m/\[(\S+)\]/ )
			{
				$pathsSection = $1;
			}
			elsif ( $pathsSection eq "paths" )
			{
				if ($_ =~ m/FileBase\s*=\s*(.+)/)
				{
					$filebase = $1;
				}
				elsif ($_ =~ m/FileFDS\s*=\s*(.+)/)
				{
					$filefds = $1;
				}
				elsif ($_ =~ m/UseRenFolder\s*=\s*(true|false)/i)
				{
					$useRenFolder = (lc($1) eq 'true') ? 1 : 0;
				}
			}
		}

		# Determine fds logfiles path
		$config_fdslogpath = ($useRenFolder == 1)
			? $config_fdspath.$filebase.'/'.$filefds.'/'
			: File::HomeDir->my_documents.'/'.$filebase.'/'.$filefds.'/';

		modules::console_output ( $config_fdslogpath, 3 );
	}
	elsif ( $ssgm_version >= 4 )
	{
		# No paths.ini, assume default location for Renegade FDS
		# ( <FDS ROOT>/Renegade/FDS/ )
		modules::console_output ( "[Config] Unable to find data/paths.ini, assuming default logfile path... ", 1 );
		$config_fdslogpath = $config_fdspath.'Renegade/FDS/';
		modules::console_output ( $config_fdslogpath, 3 );
	}
	else
	{
		# Not using SSGM or using a version older than 4.0, logs are in FDS root
		$config_fdslogpath = $config_fdspath;
	}
}






# Check if BRenBot.dll exists, and if so enable support for it
sub checkBrenbotDll
{
	# Set default state
	modules::set_module( "BRenBot_dll", 0 );

	if ( -f $config_fdspath . "BRenBot.dll")
	{
		modules::console_output ( "[Config] BRenBot.dll library found. Enabling support." );
		modules::set_module( "BRenBot_dll", 1 );
	}
}

1;
