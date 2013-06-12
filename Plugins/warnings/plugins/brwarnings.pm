#
# Warnings plugin for BRenBot 1.54 by Daniel Paul
#
# Version 1.6
#
package brwarnings;

use POE;
use plugin;
use modules;
use POSIX;

my $currentVersion = '1.6';

# Check bot compatibility
if ( !defined(plugin::getBrVersion) || plugin::getBrVersion() < 1.53
  || (plugin::getBrVersion() == 1.53 && plugin::getBrBuild() < 14 ) )
{
  print " == Warnings Plugin Error ==\nThis version of the plugin is not compatible with BRenBot"
          ." versions older than 1.53.14";
  return 0;
}

# --------------------------------------------------------------------------------------------------

# BRenBot supplies these on plugin startup
our $plugin_name;
our %config;

# Define additional events in the POE session
our %additional_events =
(
  # other functions
  "greetPlayer" => "greetPlayer",
  "greetPlayerBadName" => "greetPlayerBadName",
  "checkOldWarnings" => "checkOldWarnings",

  # !command functions
  "showWarnings" => "showWarnings",
  "showAllWarnings" => "showAllWarnings",
  "warnings" => "warnings",
  "warnPlayer" => "warnPlayer",
  "words" => "words",
  "resetWarnings" => "resetWarnings",
  "warning_stats" => "warning_stats",
  "autoWarnings" => "autoWarnings",
  "flushStats" => "flushStats",
  "mostWarnedWords" => "mostWarnedWords",
  "reloadWords" => "reloadWords",
  "add_autoKB" => "add_autoKB",
  "remove_autoKB" => "remove_autoKB",
  "list_autoKB" => "list_autoKB"
);

my %autowarnWords;         # Hash to hold autowarnWords
my $autowarnWordsList;     # Scalar to hold a list of all autowarnWords
my $dbc;                   # Database connection
my %autoKB;

# --------------------------------------------------------------------------------------------------

########### Functions for !commands

# Function for displaying all current warnings for players in the server
sub showWarnings
{
  my %args = %{@_[ ARG0 ]};

  my %warnings = getAllWarnings();
  my ($warningList, $playerRef);

  my %playerList = plugin::get_playerlist();
  while ( my ( $id, $player ) = each ( %playerlist ) )
  {
    if ( $warnings{$player->{name}} ) { $warningList .= "$player->{name} ($warnings{$player->{name}}), "; }
  }

  if ( $warningList )
  {
    $warningList = substr ( $warningList, 0, -2 );
    if ( $args{nick} =~ m/\@IRC$/ ) { plugin::ircmsg ( "The following players currently have warnings: $warningList", $args{ircChannelCode} ); }
    else { plugin::RenRemCMD("msg The following players currently have warnings: $warningList"); }
  }
  else
  {
    if ( $args{nick} =~ m/\@IRC$/ ) { plugin::ircmsg ( "There are no warnings issued at the moment.", $args{ircChannelCode} ); }
    else { plugin::RenRemCMD("msg There are no warnings issued at the moment."); }
  }
}

# Function for all current warnings for players in and out of the server, and irc users
sub showAllWarnings
{
  my %args = %{@_[ ARG0 ]};

  my $warningList;
  my %warnings = getAllWarnings();

  while ( my ($key, $value) = each(%warnings) ) { $warningList .= "$key ($value), "; }
  if ( $warningList )
  {
    $warningList = substr ( $warningList, 0, -2 );
    plugin::ircmsg ( "The following players currently have warnings: $warningList", $args{ircChannelCode} );
  }
  else
  {
    plugin::ircmsg ( "There are no warnings issued at the moment.", $args{ircChannelCode} );
  }
}

# Function for all current warnings for a specific person
sub warnings
{
  my %args = %{@_[ ARG0 ]};

  my $queryName = ( $args{arg1} ) ? $args{arg1} : $args{nick};
  my $warnings = getWarnings ( $queryName );

  if ( $warnings )
  {
    my $suffix = ( $warnings == 1 ) ? '' : 's';
    if ( $args{nicktype} == 1 ) { plugin::ircmsg ( "$queryName currently has $warnings warning$suffix.", $args{ircChannelCode} ); }
    else { plugin::RenRemCMD("msg $queryName currently has $warnings warning$suffix."); }
  }
  else
  {
    if ( $args{nicktype} == 1 ) { plugin::ircmsg ( "$queryName does not have any warnings.", $args{ircChannelCode} ); }
    else { plugin::RenRemCMD("msg $queryName does not have any warnings."); }
  }
}

# Function for warning a player
sub warnPlayer
{
  my %args = %{@_[ ARG0 ]};

  if ( $args{arg} =~ m/\S+\s\S+\s(.+)/ )
  {
    # Run giveWarning(), note that only players actually in the server can be warned.
    my $result = giveWarning ( $args{'arg1'}, "server", $1, $args{'nick'}, $args{'ircChannelCode'} );
  }
  else
  {
    # No reason given for the warning
    if ( $args{'nick'} =~ m/\@IRC$/ ) { plugin::ircmsg ( "$args{nick}, you must give a reason for the warning. Usage : !warn <player> <reason>", $args{ircChannelCode} ); }
    else { plugin::RenRemCMD("msg $args{nick}, you must give a reason for the warning. Usage : !warn <player> <reason>"); }
  }
}

# Function for displaying the list of autowarnWords
sub words
{
  my %args = %{@_[ ARG0 ]};
  plugin::ircmsg ( "The following words and/or phrases are disallowed: $autowarnWordsList", $args{'ircChannelCode'} );
}

# Function for resetting a players warnings
sub resetWarnings
{
  my %args = %{@_[ ARG0 ]};

  if ( $args{arg1} )
  {
    my $result = deleteWarnings ( $args{arg1} );

    if ( $result == 1 )
    {
      if ( $args{nick} =~ m/\@IRC$/ ) { plugin::ircmsg ( "Warnings have been reset to 0 for $args{arg1}.", $args{ircChannelCode} ); }
      else { plugin::RenRemCMD("msg Warnings have been reset to 0 for $args{arg1}."); }
    }
    else
    {
      if ( $args{nick} =~ m/\@IRC$/ ) { plugin::ircmsg ( "$args{arg1} does not have any warnings to reset!.", $args{ircChannelCode} ); }
      else { plugin::RenRemCMD("msg $args{arg1} does not have any warnings to reset!."); }
    }
  }
  else
  {
    if ( $args{nicktype} == 1 ) { plugin::ircmsg ( "You must specify the player name to reset warnings for. USAGE: !reset_warnings <playername>", $args{ircChannelCode} ); }
    else { plugin::RenRemCMD("msg You must specify the player name to reset warnings for. USAGE: !reset_warnings <playername>"); }
  }
}

# Function for showing todays stats
sub warning_stats
{
  my %args = %{@_[ ARG0 ]};

  my ( $timeFrame, $warnings, $autoWarnings, $qkicks, $kicks, $bans, $ircKicks );
  if ( $args{arg1} eq "month" )
  {
    ( $warnings, $autoWarnings, $qkicks, $kicks, $bans, $ircKicks ) = getMonthlyStats();
    $timeFrame = strftime "%B", localtime();
  }
  elsif ( $args{arg1} eq "total" )
  {
    ( $warnings, $autoWarnings, $qkicks, $kicks, $bans, $ircKicks ) = getTotalStats();
    $timeFrame = "all time";
  }
  else
  {
    ( $warnings, $autoWarnings, $qkicks, $kicks, $bans, $ircKicks ) = getDailyStats();
    $timeFrame = strftime "the %d of %B", localtime();
  }

  plugin::ircmsg ( "Warnings plugin stats for $timeFrame", $args{ircChannelCode} );
  plugin::ircmsg ( "Warnings Issued: $warnings, Automatic Warnings: $autoWarnings, Qkicks: $qkicks, Kicks: $kicks, Bans: $bans, IRC Kicks: $ircKicks", $args{ircChannelCode} );
}

# Function for displaying, and changing status of automatic warnings.
sub autoWarnings
{
  my %args = %{@_[ ARG0 ]};

  my $startStatus = ( $config{autoWarnings} == 1 ) ? "enabled" : "disabled";
  if ( ( $args{arg1} ne "on" ) && ( $args{arg1} ne "off" ) )
  {
    if ( $args{nick} =~ m/\@IRC$/ ) { plugin::ircmsg ( "Automatic warnings in the server are currently $startStatus.", $args{ircChannelCode} ); }
    else { plugin::RenRemCMD("msg Automatic warnings are currently $startStatus."); }
  }

  elsif ( ( $config{autoWarnings} == 1 && $args{arg1} eq "on" ) || ( $config{autoWarnings} == 0 && $args{arg1} eq "off" ) )
  {
    if ( $args{nick} =~ m/\@IRC$/ ) { plugin::ircmsg ( "Automatic warnings in the server are already $startStatus.", $args{ircChannelCode} ); }
    else { plugin::RenRemCMD("msg Automatic warnings are already $startStatus."); }
  }

  else
  {
    $config{autoWarnings} = ( $args{arg1} eq "on" ) ? 1 : 0;
    my $newStatus = ( $config{autoWarnings} == 1 ) ? "enabled" : "disabled";

    my $duration = ".";
    if ( $args{arg2} =~ m/^\d+$/ )
    {
      # Create a copy of $args to send with the alarm, and set the new parameters
      my %args2 = %{$args};
      $args2{arg1} = ( $args{arg1} eq "on" ) ? "off" : "on";
      delete $args2{arg2};

      # Set alarm to disable again after the specified duration
      my $disableTime = int( time() ) + $args{arg2};
      $_[KERNEL]->alarm( "autoWarnings" => $disableTime => \%args2 );

      my $seconds = 0;
      my $minutes = 0;
      while ( $args{arg2} >= 60 ) { $minutes++; $args{arg2} = $args{arg2}-60; }
      $seconds = $args{arg2};

      $duration = ( $seconds ) ? " for the next $minutes minutes and $seconds seconds." : " for the next $minutes minutes.";
    }

    # Output message
    plugin::RenRemCMD( "msg Automatic warnings are now $newStatus$duration" );
  }
}

# Function for flushing out the statistics in the database
sub flushStats
{
  my %args = %{@_[ ARG0 ]};

  DBflushStats();

  plugin::ircmsg ( "All database statistics for the warnings plugin have been cleared!", $args{'ircChannelCode'} );
}

# Function for getting the 5 most frequent words the autowarnings system has warned people for
sub mostWarnedWords
{
  my %args = %{@_[ ARG0 ]};

  my $words = DBgetFrequentWords(5);

  if ( $words ) { plugin::ircmsg ( "The following words have been warned for the most: $words", $args{'ircChannelCode'} ); }
  else { plugin::ircmsg ( "There is no data available yet.", $args{'ircChannelCode'} ); }
}

# Function for reloading the warnings_words.cfg file
sub reloadWords
{
  my %args = %{@_[ ARG0 ]};

  my $result = loadautowarnWords();
  
  if ( $result ) { plugin::ircmsg ( "The plugins/warnings_words.cfg file has been reloaded.", $args{ircChannelCode} ); }
  else { plugin::ircmsg ( "4An error occured while reloading the plugins/warnings_words.cfg file! Automatic warnings may have been disabled!", $args{ircChannelCode} ); }
}

# Function for adding users to the auto KB list
sub add_autoKB
{
  my %args = %{@_[ ARG0 ]};

  my $message;

  if ( $args{arg} =~ m/\!autoKB\s(\S+)\s(.+)/i )
  {
    my $name = $1;				$name =~ s/"/\'/;
    my $reason = $2;			$reason =~ s/"/\'/;
    if ( $autoKB{lc($name)} )
      { $message = "$name is already on the autoKB list"; }
    else
    {
      $dbc->do ( "INSERT INTO autoKB ( name, banner, reason ) VALUES ( \"$name\", \"$args{nick}\", \"$reason\" )" );
      $autoKB{lc($name)} = 1;
      $message = "$name has been added to the autoKB list for $reason";
    }
  }
  else { $message = 'Usage: !autoKB <playername> <reason>'; }

  if ( $args{nicktype} == 1 ) { plugin::ircmsg ( $message, $args{ircChannelCode} ); }
  else { plugin::RenRemCMD ( "msg $message" ); }
}

# Function for removing users from the auto KB list
sub remove_autoKB
{
  my %args = %{@_[ ARG0 ]};

  my $name = $args{arg1};				$name =~ s/"/\'/;
  my $message;

  if ( $args{arg1} )
  {
    if ( $autoKB{lc($name)} )
    {
      $dbc->do ( "DELETE FROM autoKB WHERE LOWER(name) = \"" . lc($name) . "\"" );
      delete $autoKB{lc($name)};
      $message = "$name has been removed from the autoKB list";
    }
    else { $message = "There is nobody called $name on the autoKB list"; }
  }
  else { $message = 'You must specify the player to remove from the auto KB list.'; }

  if ( $args{nicktype} == 1 ) { plugin::ircmsg ( $message, $args{ircChannelCode} ); }
  else { plugin::RenRemCMD ( "msg $message" ); }
}

# Function for listing users on the auto KB list
sub list_autoKB
{
  my %args = %{@_[ ARG0 ]};

  my $autoKBlist;

  while ( my ($player, $value) = each( %autoKB ) ) { $autoKBlist .= "$player, "; }

  if ( $autoKBlist )
  {
    $autoKBlist = substr ( $autoKBlist, 0, -2 );
    plugin::ircmsg ( "The following players will be banned on sight: $autoKBlist", $args{ircChannelCode} );
  }
  else { plugin::ircmsg ( "There are no players on the auto KB list at this time.", $args{ircChannelCode} ); }
}



########### Event handlers

sub start
{
  my %args = %{@_[ ARG0 ]};

  # Set our current version in the globals table
  plugin::set_global ( "version_plugin_brwarnings", $currentVersion );

  # Load the list of autowarnWords if autoWarnings is enabled
  if ( $config{autoWarnings} ) { loadautowarnWords(); }

  # Check the values of some settings in config, and overwrite them if nessicary
  if ( $config{greetPlayerDelay} !~ m/^\d+$/ ) { print "WARNINGS PLUGIN :: greetPlayerDelay option is not set or non numerical. Defaulting to 10 seconds.\n"; $config{greetPlayerDelay} = 10; }
  if ( $config{qkick_warnings} !~ m/^\d+$/ ) { print "WARNINGS PLUGIN :: qkick_warnings option is not set or non numerical. Defaulting to 2.\n"; $config{qkick_warnings} = 2; }
  if ( $config{kick_warnings} !~ m/^\d+$/ ) { print "WARNINGS PLUGIN :: kick_warnings option is not set or non numerical. Defaulting to 3.\n"; $config{kick_warnings} = 3; }
  if ( $config{kick_warnings} < $config{qkick_warnings} ) { print "WARNINGS PLUGIN :: kick_warnings cannot be lower than qkick_warnings. Setting kick_warnings to " . ($config{qkick_warnings}+1); $config{kick_warnings} = $config{qkick_warnings}+1; }
  if ( $config{ban_warnings} !~ m/^-?\d+$/ ) { print "WARNINGS PLUGIN :: ban_warnings option is not set or non numerical. Defaulting to 10.\n"; $config{ban_warnings} = 10; }
  if ( $config{ban_warnings} < $config{kick_warnings} && $config{ban_warnings} != -1 ) { print "WARNINGS PLUGIN :: ban_warnings cannot be lower than kick_warnings. Setting ban_warnings to " . ($config{kick_warnings}+5); $config{ban_warnings} = $config{kick_warnings}+5; }
  if ( $config{expire_time} !~ m/^-?\d+$/ ) { print "WARNINGS PLUGIN :: expire_time option is not set or non numerical. Defaulting to 14400.\n"; $config{expire_time} = 14400; }
  if ( $config{irc_kick_warnings} !~ m/^\d+$/ ) { print "WARNINGS PLUGIN :: irc_kick_warnings option is not set or non numerical. Defaulting to 3.\n"; $config{irc_kick_warnings} = 3; }
  if ( $config{irc_expire_time} !~ m/^-?\d+$/ ) { print "WARNINGS PLUGIN :: irc_expire_time option is not set or non numerical. Defaulting to 14400.\n"; $config{irc_expire_time} = 14400; }
  if ( $config{warningsCheckFrequency} !~ m/^\d+$/ ) { print "WARNINGS PLUGIN :: warningsCheckFrequency option is not set or non numerical. Defaulting to 1800.\n"; $config{warningsCheckFrequency} = 1800; }

  # Now connect to, and if necessary create, the database
  my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$dbTime,$ctime,$blksize,$blocks) = stat('warnings_plugin.dat');

  if ( $^O eq "MSWin32" )
  {
    $dbc = DBI->connect("dbi:SQLite2:dbname=warnings_plugin.dat","","",{RaiseError => 1});
  }
  else	# Use alternative SQLite driver for linux
  {
    $dbc = DBI->connect("dbi:SQLite:dbname=warnings_plugin.dat","","",{RaiseError => 1});
  }

  if( !$dbTime )
  {
    print "WARNINGS PLUGIN :: Database does not exist, creating fresh database\n";

    $dbc->do(
      "CREATE TABLE warnings
      (name				char(128)	PRIMARY KEY
      ,warnings			int
      ,lastWarnTime		int)"
    );

    $dbc->do(
      "CREATE TABLE statistics
      (day				char(6)		PRIMARY KEY
      ,warnings			int
      ,autoWarnings		int
      ,qkicks				int
      ,kicks				int
      ,bans				int
      ,ircKicks			int)"
    );

    $dbc->do(
      "CREATE TABLE badword_statistics
      (word				char(128)	PRIMARY KEY
      ,timesCaught		int)"
    );

    $dbc->do (
      "CREATE TABLE autokb
      ( name				CHAR(128)	PRIMARY KEY
      ,banner				CHAR(128)
      ,reason				CHAR(256) )"
    );

    $dbc->do( "CREATE TABLE warnings_plugin ( version int PRIMARY KEY)" );

    $dbc->do( "INSERT INTO warnings_plugin(version) VALUES ($currentVersion)" );
  }
  else
  {
    my $dbVersion = $dbc->selectrow_array ( "SELECT version FROM warnings_plugin" );

    if ( $dbVersion != $currentVersion )
    {
      print "WARNINGS PLUGIN :: Database is out of date. DB is $dbVersion, current is $currentVersion. Updating to new version\n";

      if ( $dbVersion < 1.2 )
      {
        print "WARNINGS PLUGIN :: Updating db to 1.2....\n";

        print "  Adding table autokb\n";
        $dbc->do ( "CREATE TABLE autokb ( name CHAR(128) PRIMARY KEY )" );
      }

      if ( $dbVersion < 1.33 )
      {
        print "WARNINGS PLUGIN :: Updating db to 1.33....\n";

        # Scan for players on the autokb list who are already banned
        print "  Removing banned players from autoKB list\n";
        my $query = $dbc->prepare ( "SELECT name FROM autokb" );
        $query->execute();

        my @row = $query->fetchrow_array;
        while ( defined(@row[0]) )
        {
          my $autokbname = lc($row[0]);

          my @array = plugin::execute_query( "SELECT * FROM banlist WHERE LOWER(name) = \"$autokbname\"" );
          if ( scalar(@array) > 0 )
          {
            # Already banned, remove from autoKB list
            $dbc->do ( "DELETE FROM autokb WHERE LOWER(name) = \"$autokbname\"" );
          }
          @row = $query->fetchrow_array;
        }
      }

      if ( $dbVersion < 1.4 )
      {
        print "WARNINGS PLUGIN :: Updating db to 1.4....\n";

        # Move autoKB data to a temporary table, and recreate the autoKB table
        print "  Adding banner and reason columns to the autoKB table\n";

        # Create temp table and move data
        $dbc->do ( "CREATE TABLE autokb_temp ( name CHAR(128) PRIMARY KEY )" );
        $dbc->do ( "INSERT INTO autokb_temp SELECT name FROM autokb" );
        $dbc->do ( "DROP TABLE autokb" );

        # Recreate autoKB table
        $dbc->do (
          "CREATE TABLE autokb
          ( name				CHAR(128)	PRIMARY KEY
          ,banner				CHAR(128)
          ,reason				CHAR(256) )"
        );

        my $query = $dbc->prepare ( "SELECT name FROM autokb_temp" );
        $query->execute();

        my @row = $query->fetchrow_array;
        while ( defined(@row[0]) )
        {
          my $autokbname = lc($row[0]);

          my @array = plugin::execute_query( "SELECT * FROM banlist WHERE LOWER(name) = \"$autokbname\"" );
          if ( scalar(@array) == 0 )
          {
            # Not banned yet, copy them back across
            $dbc->do ( "INSERT INTO autokb (name, banner, reason) VALUES ( \"$row[0]\", \"BRenBot\", \"being on autoKB list.\" )" );
          }
          @row = $query->fetchrow_array;
        }

        $dbc->do ( "DROP TABLE autokb_temp" );
      }

      if ( $dbVersion < 1.5 )
      {
        print "WARNINGS PLUGIN :: Updating db to 1.50....\n";

        # Copy existing logs to brenbot's logging system, then delete logs table
        print "  Moving logs from logs table to brenbot.dat... this may take a few minutes...\n";
        my $query = $dbc->prepare ( "SELECT name, content, timestamp FROM logs" );
        $query->execute();

        my @row = $query->fetchrow_array;
        while ( defined(@row[0]) )
        {
          my $log = "$row[0]: $row[1]";
          brdatabase::execute_query ( "INSERT INTO logs ( logType, content, timestamp ) VALUES ( 11, \"$log\", $row[2] )", 1 );
          @row = $query->fetchrow_array;
        }

        print "  Deleting redundant table logs\n";
        $dbc->do ( "DROP TABLE logs" );
      }

      $dbc->do ( "UPDATE warnings_plugin SET version = $currentVersion" );
    }
  }

  # Load autoKB list
  load_autoKB_list();

  # Run a check for old warnings to expire, which will also handle
  # scheduling future checks
  $_[KERNEL]->yield( "checkOldWarnings" => \%args );
}

sub stop
{
	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];

	# Comamnds to run when BRenBot quits
	$dbc->disconnect;

}

sub command
{
  # trigger on !commands
  my $kernel = @_[KERNEL];
  my %args = %{$args};

  # each command from IRC/ingame comes here first. have to trigger the approriate functions from here
  if ( $args{command} eq "show_warnings" )
  {
    $kernel->yield("showWarnings" => \%args);
  }
  elsif ( $args{command} eq "show_all_warnings" )
  {
    $kernel->yield("showAllWarnings" => \%args);
  }
  elsif ( $args{command} eq "warnings" )
  {
    $kernel->yield("warnings" => \%args);
  }
  elsif ( $args{command} eq "warn" )
  {
    $kernel->yield("warnPlayer" => \%args);
  }
  elsif ( $args{command} eq "words" )
  {
    $kernel->yield("words" => \%args);
  }
  elsif ( $args{command} eq "reset_warnings" )
  {
    $kernel->yield("resetWarnings" => \%args);
  }
  elsif ( $args{command} eq "warning_stats" )
  {
    $kernel->yield("warning_stats" => \%args);
  }
  elsif ( $args{command} eq "autowarnings" )
  {
    $kernel->yield("autoWarnings" => \%args);
  }
  elsif ( $args{command} eq "clearwarningstats" )
  {
    $kernel->yield("flushStats" => \%args);
  }
  elsif ( $args{command} eq "mostwarnedwords" )
  {
    $kernel->yield("mostWarnedWords" => \%args);
  }
  elsif ( $args{command} eq "reload_autowarn_words" )
  {
    $kernel->yield("reloadWords" => \%args);
  }
  elsif ( $args{command} eq "autokb" )
  {
    $kernel->yield("add_autoKB" => \%args);
  }
  elsif ( $args{command} eq "del_autokb" )
  {
    $kernel->yield("remove_autoKB" => \%args);
  }
  elsif ( $args{command} eq "autokb_list" )
  {
    $kernel->yield("list_autoKB" => \%args);
  }
}


sub text
{
	# trigger on any text ingame or irc
	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
	my %args = %{$args};

	if ( ( $config{autoWarnings} && ( $args{messagetype} eq "public" || $args{messagetype} eq "team" ) ) || ( $args{messagetype} eq "irc_public" && $config{IRCautoWarnings} ) )
	{
		while ( my ($key, $value) = each(%autowarnWords) )
		{
			# The regex is setup by loadAutowarnwords, so just stick it into the m/ /i
			if ( $args{message} =~ m/$value/i )
			{
				# We found a disallowed word, now warn user and end the loop
				keys %autowarnWords;				# Reset autowarnWords hash
				my $nickLocation = ( $args{messagetype} eq "public" || $args{messagetype} eq "team" ) ? "server" : "irc";

				# Check if the message was paged
				if ( $args{nick} =~ m/^\[Page\] (.+)$/i )
				{
					# Someone is paging swearwords to the server... lets see if they
					# are in the server
          my ( $result, %player ) = plugin::getPlayerData ( $1 );
          if ( $result == 1 )
          {
            # Oh look, they are in the server... lets surprise them!
            plugin::call_command ( "BRenBot", "kick $player{name} Paging abuse to the server. Bye Bye." );
          }

					else
					{
						# Shame, lets just add them to the autoKB list then
						my $name = $1;				$name =~ s/"/\'/;
						if ( !$autoKB{lc($name)} )
						{
							$dbc->do ( "INSERT INTO autokb ( name, banner, reason ) VALUES ( \"$name\", \"BRenBot\", \"Paging abuse to the server.\" )" );
							$autoKB{lc($name)} = 1;
							plugin::ircmsg ( "$name has been automatically added to the autoKB list for paging abuse to the server.", $args{ircChannelCode} );
						}
					}
				}

				else
				{
					giveWarning ( $args{nick}, $nickLocation, "using a disallowed word or phrase", "BRenBot", $args{ircChannelCode} );
					updateWordCount ( $key );     # Update the database with how many times this word has been detected
				}
				last;         # End the while loop, already found a disallowed word
			}
		}
	}
}



sub playerjoin
{
	# triggers on players joining
	my ( $kernel, $session, $heap, $args ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
	my %args = %{$args};

	# Check them against the autoKB list
	if ( $autoKB{lc($args{nick})} )
	{
		my @row = $dbc->selectrow_array ( "SELECT banner, reason FROM autokb WHERE LOWER(name) = \"".lc($args{nick})."\"" );
		my ( $banner, $reason ) = @row;
		plugin::call_command ( "BRenBot", "kb $args{nick} placed on the Automatic KICK-BAN list by $banner for '$reason'." );
		$dbc->do ( "DELETE FROM autoKB WHERE LOWER(name) = \"".lc($args{nick})."\"" );
	}

	# Check for swearwords in their username if enabled
	elsif ( $config{checkPlayerNames} )
	{
		while ( my ($key, $value) = each(%autowarnWords) )
		{
			# The regex is setup by loadAutowarnwords, so just stick it into the m/ /i
			if ( $args{message} =~ m/$value/i )
			{
				# We found a disallowed word, now send them a page and set qkick timer ticking
				keys %autowarnWords;			# Reset autowarnWords hash position back to start

        my ( $result, %player ) = plugin::getPlayerData ( $args{nick} );
        if ( $result == 1 )	{ plugin::RenRemCMD ( "ppage $player{id} Your name contains the word '$key', which is not allowed on this server. Please come back with a different name." ); }

				my $next_time = int( time() ) + 5;
				$_[KERNEL]->alarm( greetPlayerBadName => $next_time => \%args );
				last;					# End the while loop
			}
		}
	}


	# Send a message to the player if enabled in the config, after the
	# specified delay
	elsif ( $config{greetPlayers} )
	{
		my $next_time = int( time() ) + $config{greetPlayerDelay};
		$_[KERNEL]->alarm( greetPlayer => $next_time => \%args );
	}
}




########### Other Functions

# Function for greeting players when they join the server, if enabled
sub greetPlayer
{
  my %args = %{@_[ ARG0 ]};

  my ( $result, %player ) = plugin::getPlayerData ( $args{nick} );
  if ( $result == 1 )
  {
    my $warnings = getWarnings ( $player{name} );
    if ( !$warnings ) { $warnings = 0; }
    my $message = $config{greetPlayerMessage};
    # Replace %warnings with number of warnings
    $message =~ s/%warnings/$warnings/gi;

    plugin::RenRemCMD ("ppage $player{id} $message");
  }
}


# Function for qkicking people with disallowed usernames
sub greetPlayerBadName
{
  my %args = %{@_[ ARG0 ]};

  my ( $result, %player ) = plugin::getPlayerData ( $args{nick} );
  if ( $result == 1 ) { plugin::call_command( "BRenBot", "qkick $player{'name'} a disallowed word in their username." ); }
}


# Function for warning a player, and, if nessicary, qkicking or kicking them
sub giveWarning
{
	my ( $nickname, $nickLocation, $reason, $warnedBy, $channelCode ) = @_[ 0, 1, 2, 3, 4 ];

	# Check if it is a player in the server
	if ( $nickLocation eq "server" )
	{
		# Check player is in the server
		my ( $result, %player ) = plugin::getPlayerData ( $nickname );

		if ( $result == 1 )
		{
			# Store warning in database, recieve old warnings as return value
			my $oldWarnings = dbStoreWarning( $player{'name'} );

			my $suffix = ( $oldWarnings == 0 ) ? '' : 's';
			plugin::RenRemCMD ( "msg $player{name} has been warned by $warnedBy for '$reason'. They now have " . ( $oldWarnings+1 ) . " warning$suffix." );

			# Write the warning log
			brdatabase::writeLog ( 11, "[WARNINGS PLUGIN] $player{name} was warned by $warnedBy for '$reason'." );

			my $isAutoWarning = ( $warnedBy eq "BRenBot" ) ? 1 : 0;

			# Check if they are at the !ban limit, and if banning is enabled
			if ( ( ( $oldWarnings+1 ) >= $config{ban_warnings} ) && $config{ban_warnings} != -1 ) { plugin::call_command( "BRenBot", "kb $player{'name'} having $config{ban_warnings} or more warnings." ); updateStats ( 1, $isAutoWarning, 0, 0, 1, 0 ); brdatabase::writeLog ( 11, "[WARNINGS PLUGIN] $player{name} was banned from the server for reaching $config{ban_warnings} warnings." ); }
			# Check if they are at the !kick limit
			elsif ( ( $oldWarnings+1 ) >= $config{kick_warnings} ) { plugin::call_command( "BRenBot", "kick $player{'name'} having $config{kick_warnings} or more warnings." ); updateStats ( 1, $isAutoWarning, 0, 1, 0, 0 ); brdatabase::writeLog ( 11, "[WARNINGS PLUGIN] $player{name} was kicked from the server for reaching $config{kick_warnings} warnings." ); }
			# Check if they are at the !qkick limit
			elsif ( ( $oldWarnings+1 ) >= $config{qkick_warnings} ) { plugin::call_command( "BRenBot", "qkick $player{'name'} having $config{qkick_warnings} or more warnings." ); updateStats ( 1, $isAutoWarning, 1, 0, 0, 0 ); brdatabase::writeLog ( 11, "[WARNINGS PLUGIN] $player{name} was Qkicked from the server for reaching $config{qkick_warnings} warnings." ); }
			# Check if punishModerators is on
			elsif ( $config{punishModerators} )
			{
				# Check if they are a mod
				if ( modules::IsTempMod ( $player{'name'} ) ) { plugin::call_command ( "BRenBot", "dtm $player->{'name'}" ); plugin::RenRemCMD( "msg $player{name} has had their ATM rights revoked for being warned." ); updateStats ( 1, $isAutoWarning, 0, 0, 0, 0 ); brdatabase::writeLog ( 11, "[WARNINGS PLUGIN] $player{name} had their ATM rights revoked for recieving a warning." ); }
				elsif ( modules::IsAdmin ( $player{'name'} ) || modules::IsFullMod ( $player{'name'} ) || modules::IsHalfMod ( $player{'name'} ) ) { plugin::call_command ( "BRenBot", "qkick $player{'name'} for being warned as a moderator." ); updateStats ( 1, $isAutoWarning, 1, 0, 0, 0 ); brdatabase::writeLog ( 11, "[WARNINGS PLUGIN] $player{name} was Qkicked from the server for being warned as a moderator." ); }
				else
				{
					updateStats ( 1, $isAutoWarning, 0, 0, 0, 0 );
					plugin::RenRemCMD ( "pamsg $player{id} You have been warned by $warnedBy for '$reason'. You now have " . ( $oldWarnings+1 ) . " warning$suffix." );
				}
			}
			else
			{
				updateStats ( 1, $isAutoWarning, 0, 0, 0, 0 );
				plugin::RenRemCMD ( "pamsg $player{id} You have been warned by $warnedBy for '$reason'. You now have " . ( $oldWarnings+1 ) . " warning$suffix." );
			}
		}
		elsif ( $result == 2 )
		{
			if ( $warnedBy =~ m/\@IRC$/ ) { plugin::ircmsg ( "4$nickname is not unique, please be more specific.", $channelCode ); }
			else { plugin::RenRemCMD( "msg $nickname is not unique, please be more specific." ); }
		}
		else
		{
			if ( $warnedBy =~ m/\@IRC$/ ) { plugin::ircmsg ( "4$nickname was not found in the server.", $channelCode ); }
			else { plugin::RenRemCMD( "msg $nickname was not found in the server." ); }
		}
	}
	elsif ( $nickLocation eq "irc" )
	{
		# Store warning in database, recieve old warnings as return value
		my $oldWarnings = dbStoreWarning( $nickname );

		my $suffix = ( $oldWarnings == 0 ) ? '' : 's';
		plugin::ircmsg ( "4$nickname has been warned by $warnedBy for '$reason'. They now have " . ( $oldWarnings+1 ) . " warning$suffix.", $channelCode );

		# Write the warning log
		brdatabase::writeLog ( 11, "[WARNINGS PLUGIN] $player{name} was warned by $warnedBy for '$reason'" );

		my $isAutoWarning = ( $warnedBy eq "BRenBot" ) ? 1 : 0;

		# Check if they are at the irc kick limit
		if ( ($oldWarnings+1) >= $config{irc_kick_warnings} )
		{
			#Work out nickname for kick actions
			$nickname =~ m/(\S+)\@IRC$/;
			$_[KERNEL]->post ( IRC => kick => CHANNEL, $1, "You were automatically kicked by BRenBot for for having $config{irc_kick_warnings} or more warnings.");
			brdatabase::writeLog ( 11, "[WARNINGS PLUGIN] $player{name} was kicked from the IRC channel for having $config{irc_kick_warnings} or more warnings." );
			updateStats ( 1, $isAutoWarning, 0, 0, 0, 1 );
		}
		else { updateStats ( 1, $isAutoWarning, 0, 0, 0, 0 ); }
	}
}


# Function for reading the list of bad words from the warnings_words.cfg file
# into the %autowarnWords hash
sub loadautowarnWords
{
	# Initialise variables
	my ($fileHandle, $line);
	my $status =  1;

	print "WARNINGS PLUGIN :: Beginning to load list of disallowed words\n";

	if ( !open ( $fileHandle, 'plugins/warnings_words.cfg' ) )
	{
		print "WARNINGS PLUGIN :: Failed to open plugins/warnings_words.cfg! Disabling automatic warnings.\n";
		$config{autoWarnings} = 0;			$config{IRCautoWarnings} = 0;
		$status = 0;
	}
	else
	{
		# Start from a blank hash and list
		%autowarnWords = ();
		$autowarnWordsList = "";

		while( $line = <$fileHandle> )
		{
			$line = lc($line);
			if ( $line =~ m/\n/ ) { chop ( $line ); }
			# Check if the line starts with a #, if it does ignore it as a comment
			if ( $line !~ m/^\#/ && $line ne "" )
			{
				my $value = generateSearchString ($line);
				$autowarnWords{$line} = $value;
			}
		}

		if ( !close ( $fileHandle ) ) { print ( "WARNINGS PLUGIN :: Failed to close plugins/warnings_words.cfg!\n" ); }

		print ( "WARNINGS PLUGIN :: Finished loading list of disallowed words\n" );
	}

	# Create the $autowarnWordsList scalar so we don't have to go through the hash each
	# time the command is called.
	while ( my ($key, $value) = each(%autowarnWords) ) { $autowarnWordsList .= "$key, "; }
	$autowarnWordsList = substr ( $autowarnWordsList, 0, -2 );	# Trim trailing , of the list

	# Return 1 on success, 0 on failure
	return $status;
}


# Generates a searching string for disallowed words
sub generateSearchString
{
	my $string = @_[0];
	my $uniqueMode = 0;
	my $searchString;

	my @splitString = split ( / */, $string );

	my $pos = 0;
	my $endPos = @splitString;
	while ( $pos < $endPos )
	{
		# Look for specific things to match, and add the correct output onto searchString
		my $temp = $splitString[$pos];

		if ( $temp eq ' ' ) { $searchString .= ' '; $pos++; next; }		# Check if this is a space

		# Handle & at the front of the string
		if ( $temp eq '&' && $pos == 0 ) { $uniqueMode = 1; $pos++; next; }

		# Check for any *, ., + etc
		if ( $temp eq '*' ) { $searchString .= '\*'; $pos++; next; }
		if ( $temp eq '.' ) { $searchString .= '\.'; $pos++; next; }
		if ( $temp eq '+' ) { $searchString .= '\+'; $pos++; next; }
		if ( $temp eq '?' ) { $searchString .= '\?'; $pos++; next; }

		# Check for 1337 speak crap
		if ( $temp eq 'o' ) { $temp = 'o|0'; }
		elsif ( $temp eq 'a' ) { $temp = 'a|4'; }
		elsif ( $temp eq 'e' ) { $temp = 'e|3'; }
		elsif ( $temp eq 't' ) { $temp = 't|7'; }
		elsif ( $temp eq 'l' ) { $temp = 'l|1'; }
		elsif ( $temp eq 'i' ) { $temp = 'i|!'; }
		elsif ( $temp eq 's' ) { $temp = 's|\$'; }

		# Only look for *, _ etc on lines other than first and last
		if ( ( $pos != ( $endPos -1 ) ) && ( $pos != 0 ) ) { $searchString .= '(' . $temp . '|\*|_|\.)'; }
		else { $searchString .= '(' . $temp . ')'; }

		$pos++;
	}

	# If we are in uniqueMode add the spaces to either side
	if ( $uniqueMode ) { $searchString = '^(.*\s)?' . $searchString . '(\s.*)?$'; }

	return $searchString;
}


# Function for loading the list of autoKB players
sub load_autoKB_list
{
	my $query = $dbc->prepare ( "SELECT name FROM autokb" );
	$query->execute;

	my @row = $query->fetchrow_array;
	while ( defined(@row[0]) )
	{
		$autoKB{lc($row[0])} = 1;
		@row = $query->fetchrow_array;
	}
}


# Function for checking if we need to run reduceOldWarnings
sub checkOldWarnings
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};

	if ( ( $config{expire_time} != -1 ) || ( $config{irc_expire_time} != -1 ) )
	{
		# At least one of the two is enabled, so run the reduce warnings process
		my $result = reduceOldWarnings();
		if ( $result ) { print "WARNINGS PLUGIN :: $result warnings have expired.\n"; }

		# Schedule another execution
		my $next_time = int( time() ) + $config{warningsCheckFrequency};
		$_[KERNEL]->alarm( "checkOldWarnings" => $next_time => \%args );
	}
}






########## Functions for accessing and updating database


# Put a warning into the database
sub dbStoreWarning
{
	my $name = @_[0];			$name =~ s/"/\'/;

	my $oldWarnings = $dbc->selectrow_array ( "SELECT warnings FROM warnings WHERE name = \"$name\"" );
	if ( $oldWarnings ) { $dbc->do ( "UPDATE warnings SET warnings = warnings+1, lastWarnTime = " . time() . " WHERE name = \"$name\"" ); }
	else { $dbc->do ( "INSERT INTO warnings ( warnings, name, lastWarnTime ) VALUES ( 1, \"$name\", " . time() . " )" ); }

	if ( $oldWarnings ) { return $oldWarnings; }
	else { return 0; }
}


# Increment today's statistics
sub updateStats
{
	my ( $incrementWarnings, $incrementAutoWarnings, $incrementQKicks, $incrementKicks, $incrementBans, $incrementIRCKicks ) = @_[ 0, 1, 2, 3, 4, 5 ];

	# Work out the integer representing the day
	my @time = localtime(time());
	my $day = sprintf("%02d", $time[3]) . sprintf("%02d", $time[4] +1) . sprintf("%02d", $time[5] % 100);

	my @oldStats = $dbc->selectrow_array ( "SELECT warnings, autoWarnings, qkicks, kicks, bans, ircKicks FROM statistics WHERE day = '$day'" );

	my $newWarnings = ( $incrementWarnings ) ? @oldStats[0] +1 : 0+ @oldStats[0];
	my $newAutoWarnings = ( $incrementAutoWarnings ) ? @oldStats[1] +1 : 0+ @oldStats[1];
	my $newQKicks = ( $incrementQKicks ) ? @oldStats[2] +1 : 0+ @oldStats[2];
	my $newKicks = ( $incrementKicks ) ? @oldStats[3] +1 : 0+ @oldStats[3];
	my $newBans = ( $incrementBans ) ? @oldStats[4] +1 : 0+ @oldStats[4];
	my $newIRCKicks = ( $incrementIRCKicks ) ? @oldStats[5] +1 : 0+ @oldStats[5];

	if ( @oldStats ) { $dbc->do( "UPDATE statistics SET warnings = $newWarnings, autoWarnings = $newAutoWarnings, qkicks = $newQKicks, kicks = $newKicks, bans = $newBans, ircKicks = $newIRCKicks WHERE day = '$day'" ) }
	else { $dbc->do( "INSERT INTO statistics ( day, warnings, autoWarnings, qkicks, kicks, bans, ircKicks ) VALUES ( '$day', $newWarnings, $newAutoWarnings, $newQKicks, $newKicks, $newBans, $newIRCKicks )" ); }
}


# Get todays stats
sub getDailyStats
{
	# Work out the integer representing the day
	my @time = localtime(time());
	my $day = sprintf("%02d", $time[3]) . sprintf("%02d", $time[4] +1) . sprintf("%02d", $time[5] % 100);

	my @stats = $dbc->selectrow_array ( "SELECT warnings, autoWarnings, qkicks, kicks, bans, ircKicks FROM statistics WHERE day = '$day'" );
	if ( !@stats ) { @stats = ( 0, 0, 0, 0, 0, 0 ); }
	return @stats;
}


# Get this months stats
sub getMonthlyStats
{
	# Work out the integer representing the month
	my @time = localtime(time());
	my $month = sprintf("%02d", $time[4] +1) . sprintf("%02d", $time[5] % 100);

	my @stats = $dbc->selectrow_array ( "SELECT SUM(warnings), SUM(autoWarnings), SUM(qkicks), SUM(kicks), SUM(bans), SUM(ircKicks) FROM statistics WHERE day LIKE '%$month'" );
	if ( !@stats ) { @stats = ( 0, 0, 0, 0, 0, 0 ); }
	return @stats;
}


# Get total stats
sub getTotalStats
{
	my @stats = $dbc->selectrow_array ( "SELECT SUM(warnings), SUM(autoWarnings), SUM(qkicks), SUM(kicks), SUM(bans), SUM(ircKicks) FROM statistics" );
	if ( !@stats ) { @stats = ( 0, 0, 0, 0, 0, 0 ); }
	return @stats;
}


# Function for reducing warnings where nessicary
sub reduceOldWarnings
{
	my $result = 0;
	my $result2 = 0;

	# If expire time and irc expire time are the same save time by just doing
	# one query. This should only be run if at least one of them is enabled, so
	# no need to check them against -1 yet.
	if ( $config{expire_time} == $config{irc_expire_time} )
	{ $result = $dbc->do ( "UPDATE warnings SET warnings = warnings-1, lastWarnTime = lastWarnTime + $config{expire_time} WHERE lastWarnTime <= " . ( time() - $config{expire_time} ) ); }
	else
	{
		if ( $config{expire_time} != -1 ) { $result = $dbc->do ( "UPDATE warnings SET warnings = warnings-1, lastWarnTime = lastWarnTime + $config{expire_time} WHERE lastWarnTime <= " . ( time() - $config{expire_time} ) . " AND name NOT LIKE '%\@IRC'" ); }
		if ( $config{irc_expire_time} != -1 ) { $result2 = $dbc->do ( "UPDATE warnings SET warnings = warnings-1, lastWarnTime = lastWarnTime + $config{irc_expire_time} WHERE lastWarnTime <= " . ( time() - $config{irc_expire_time} ) . " AND name LIKE '%\@IRC'" ); }
	}

	# Cleanup the database by removing records where warnings is now =0
	if ( $result eq '0E0' ) { $result = 0; }
	if ( $result2 eq '0E0' ) { $result2 = 0; }
	if ( ($result+$result2) > 0 ) { $dbc->do ( "DELETE FROM warnings WHERE warnings =0" ); }

	return ($result+$result2);
}


# Function for getting the number of warnings for a specific name
sub getWarnings
{
	my $name = lc(@_[0]);			$name =~ s/"/\'/;

	my $result = $dbc->selectrow_array ( "SELECT warnings FROM warnings WHERE LOWER(name) = \"$name\"" );
	if ( $result eq '0E0' ) { $result = 0; }

	return $result;
}


# Function for getting all the warnings currently in the database
# Returns a hash of name->warnings.
sub getAllWarnings
{
	my %result;
	my $query;
	my @row;

	$query = $dbc->prepare ( "SELECT name, warnings FROM warnings" );
	$query->execute();

	@row = $query->fetchrow_array;
	while ( defined(@row[0]) )
	{
		$result{$row[0]} = $row[1];
		@row = $query->fetchrow_array;
	}


	if ( $result eq '0E0' ) { $result = 0; }
	return %result;
}


# Function for deleting all of a players warnings
sub deleteWarnings
{
	my $name = lc(@_[0]);			$name =~ s/"/\'/;

	my $result = $dbc->do ( "DELETE FROM warnings WHERE lower(name) = \"$name\"" );
	if ( $result eq '0E0' ) { $result = 0; }
	return $result;
}


# Function for incrementing the number of times a word has been detected by the
# autowarnings function
sub updateWordCount
{
	my $word = @_[0];		$word =~ s/"/\'/;

	# Try to update the existing word count
	my $result = $dbc->do ( "UPDATE badword_statistics SET timesCaught = timesCaught+1 WHERE word = \"$word\"" );

	if ( $result eq "0E0" ) {
		# The word was not already in the database, so lets go and add it
		$result = $dbc->do ( "INSERT INTO badword_statistics ( word, timesCaught ) VALUES ( \"$word\", 1 )" );
	}
}


# Function for flushing out all the statistics in the database
sub DBflushStats
{
	$dbc->do ( "DELETE FROM badword_statistics" );
	$dbc->do ( "DELETE FROM statistics" );
}


# Function for getting the 5 most frequently warned for words from the database
sub DBgetFrequentWords
{
	my $limit = ( @_[0] > 0 ) ? @_[0] : 5;
	my ($words, $query);
	my @row;

	$query = $dbc->prepare ( "SELECT word, timesCaught FROM badword_statistics ORDER BY timesCaught DESC LIMIT 0,$limit" );
	$query->execute();

	@row = $query->fetchrow_array;
	while ( defined(@row[0]) )
	{
		$words .= "$row[0] ($row[1]), ";
		@row = $query->fetchrow_array;
	}
	$words = substr ( $words, 0, -2 );			# Trim trailing ', '

	return $words;
}


# return true
1;