#**
# Logs serial hashes for players automatically in the database, and provides IRC notifications
# when a users hash changes frequently
#
# \author Daniel Paul (danpaul88@yahoo.co.uk)
# \version 1.02
#*

package seen;

use POE;
use plugin;

my $currentVersion = '1.02';
my $loaded_ok = undef;

# Check bot compatibility
if ( !defined(plugin::getBrVersion) || plugin::getBrVersion() < 1.53
  || (plugin::getBrVersion() == 1.53 && plugin::getBrBuild() < 20 ) )
{
  print ' == SerialHashLogger Plugin Error ==\n'
      . 'This version of the plugin is not compatible with BRenBot versions older than 1.53.20\n';
  return 0;
}

# --------------------------------------------------------------------------------------------------

# BRenBot supplies these on plugin startup
our $plugin_name;
our %config;

# Define additional events in the POE session
our %additional_events =
(
  'findSerials'   => 'findSerials'
);

# Forward declarations
sub logSerial($);




# --------------------------------------------------------------------------------------------------
##
#### Bot Events
##
# --------------------------------------------------------------------------------------------------

sub start
{
  return ($loaded_ok = 0) if ( db_update() != 1 );

  plugin::set_global("version_plugin_serialHashLogger", $currentVersion);

  return ($loaded_ok = 1);
}


sub stop
{
}




# --------------------------------------------------------------------------------------------------
##
#### Game Events
##
# --------------------------------------------------------------------------------------------------

sub command
{
  return if ($loaded_ok == 0);

  my %args = %{$_[ARG0]};
  $_[KERNEL]->yield($args{'command'} => \%args);
}

sub playerjoin
{
  return if ($loaded_ok == 0);

  my %args = %{$_[ARG0]};
  $_[KERNEL]->alarm(logSerial => int(time())+5 => $args{'nick'});
}




# --------------------------------------------------------------------------------------------------
##
#### Commands
##
# --------------------------------------------------------------------------------------------------

# !findSerials command
sub findSerials
{
  my %args = %{$_[ARG0]};

  # Only supported in IRC
  return if ($args{'nicktype'} != 1);

  # Check they supplied a name to search for
  if ( !$args{'arg1'} )
  {
    show_syntax_error(@_);
    return;
  }

  # Get command user string (trim the @IRC off)
  my $ircnick = $args{'nick'};
  $ircnick =~ s/\@IRC//gi;

  # Get target name (might contain spaces)
  $args{'arg'} =~ m/^\!\S+\s(.+)$/i;
  my $playername = $1;

  # Search database for serials the specified player has used
  my @results = plugin::execute_query("SELECT serial, seenCount, lastSeen FROM serialHashLog WHERE LOWER(name) = '".lc($playername)."'" );

  # If no results were show no results message
  if (scalar(@results) == 0)
  {
    plugin::ircnotice($ircnick, "No serial logs were found for $playername.");
    return;
  }

  # Print results
  plugin::ircnotice($ircnick, "Found ".scalar(@results)." results for $playername, showing ".((scalar(@results) > 8)?'first 8':'all results' ));

  # Create output format string
  my $format = "%-15s %-15s %s";

  # Print results header
  my $line = sprintf($format, "Times Used", "Last Used", "Serial Hash");
  plugin::ircnotice($ircnick, "1,15$line");

  # Now print out up to 8 results
  for (my $i = 0; $i < 8 && $i < scalar(@results); ++$i)
  {
    my $lastSeen = plugin::strftimestamp("%d %h %Y", $results[$i]->{'lastSeen'});
    $line = sprintf($format, $results[$i]->{'seenCount'}, $lastSeen, $results[$i]->{'serial'});
    plugin::ircnotice($ircnick, $line);
  }
}




# --------------------------------------------------------------------------------------------------
##
#### Utility Functions
##
# --------------------------------------------------------------------------------------------------

# Logs the specified players serial if it exists
sub logSerial
{
  my $playername = shift;

  # Search for player ingame
  my ($result, %player) = plugin::getPlayerData($playername);
  if ($result == 1 && $player{'serial'})
  {
    # Check if this serial exists in the database
    my @result = plugin::execute_query("SELECT id FROM serialHashLog WHERE LOWER(name) = '".lc($player{'name'})."' AND serial = '".$player{'serial'}."'");

    # Update database entry if they have used this serial hash before
    if ( scalar(@result) > 0 )
      { plugin::execute_query("UPDATE serialHashLog SET seenCount = seenCount+1, lastSeen = ".time()." WHERE id = ".$result[0]->{'id'}); }

    # Otherwise create new database entry
    else
      { plugin::execute_query("INSERT INTO serialHashLog ( name, serial, seenCount, lastSeen ) VALUES ( '".$player{'name'}."', '".$player{'serial'}."', 1, ".time()." )"); }



    # Check for an excessive number of different serials within the last month (3 within 30 days)
    my @result2 = plugin::execute_query("SELECT COUNT(*) FROM serialHashLog WHERE LOWER(name) = '".lc($player{'name'})."' AND lastSeen >= ".time()-2592000);
    if ( scalar(@result2) >= 3 )
      { plugin::ircmsg("05WARNING: Player ".$player{'name'}." has used more 3 or more different serials in the last month, they may be cheating!", 'A'); }
  }
}

sub show_syntax_error()
{
  my %args = %{$_[ ARG0 ]};
  my $syntax = 'Usage: '.$args{'settings'}->{'syntax'}->{'value'};

  if ( $args{'nicktype'} == 0 )
    { plugin::pagePlayer( $args{'nick'}, 'BRenBot', $syntax ); }
  elsif ( $args{'nicktype'} == 1 )
    { plugin::ircmsg( $syntax, $args{'ircChannelCode'} ); }
  else
    { plugin::console_output('A plugin used incorrect command syntax for '.$args{'command'}); }
}




# --------------------------------------------------------------------------------------------------
##
#### Database configuration
##
# --------------------------------------------------------------------------------------------------

sub db_update
{
  my $db_version = plugin::get_global ( "version_plugin_serialHashLogger" );
  if ( defined($db_version) and $db_version > $currentVersion )
  {
    plugin::console_output("[SerialHashLogger] The database has been modified by a newer version of"
        ." this plugin. To avoid potential data corruption the plugin will now stop");
    return 0;
  }

  # Current table definitions
  my %tables = (
    serialHashLog => "CREATE TABLE serialHashLog ( id INTEGER PRIMARY KEY, name TEXT, serial TEXT, seenCount INTEGER DEFAULT 0, lastSeen INTEGER DEFAULT 0)"
  );

  # Check which tables already exist...
  my @db_tables = plugin::execute_query( "SELECT name FROM sqlite_master" );
  foreach (@db_tables)
    { delete $tables{$_->{'name'}}; }

  # Create any missing tables
  while ( my($table,$definition) = each %tables )
  {
    plugin::console_output("[SerialHashLogger] Creating missing table " . $table);
    plugin::execute_query( $definition, 1 );
    delete $tables{$table};
  }


  # Nothing to update at the moment...
  return 1;
}


# Plugin loaded OK
1;