#**
# A plugin that reports the last time a specific player was seen in the server, based on the !seen
# function which existed in BRenBot 1.41 and earlier
#
# \author Daniel Paul (danpaul88@yahoo.co.uk)
# \version 1.05
#*

package seen;

use POE;
use plugin;

my $currentVersion = '1.05';
my $loaded_ok = undef;

# Check bot compatibility
if ( !defined(plugin::getBrVersion) || plugin::getBrVersion() < 1.53
  || (plugin::getBrVersion() == 1.53 && plugin::getBrBuild() < 18 ) )
{
  print ' == Seen Plugin Error ==\n'
      . 'This version of the plugin is not compatible with BRenBot versions older than 1.53.18\n';
  return 0;
}

# --------------------------------------------------------------------------------------------------

# BRenBot supplies these on plugin startup
our $plugin_name;
our %config;

# Define additional events in the POE session
our %additional_events =
(
  'seen'        => 'seen',
  'clearSeen'   => 'clearSeen'
);

# Forward declarations
sub get_seen($)
sub get_time_difference($$)




# --------------------------------------------------------------------------------------------------
##
#### Bot Events
##
# --------------------------------------------------------------------------------------------------

sub start
{
  return ($loaded_ok = 0) if ( db_update() != 1 );

  plugin::set_global("version_plugin_seen", $currentVersion);

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
  updateTime ( $args{'nick'} );
}

sub playerleave
{
  return if ($loaded_ok == 0);
  
  my %args = %{$_[ARG0]};
  updateTime ( $args{'nick'} );
}




# --------------------------------------------------------------------------------------------------
##
#### Commands
##
# --------------------------------------------------------------------------------------------------

# !seen command
sub seen
{
  my %args = %{$_[ARG0]};

  # Check they supplied a name to search for
  if ( !$args{'arg1'} )
  {
    show_syntax_error(@_);
    return;
  }

  my $message;

  # Check if the player is in the game
  my ($result, %player) = plugin::getPlayerData($args{'arg1'});
  if ($result == 1)
  {
    if ($player{'name'} eq $args{'nick'})
      { $message = "Go look in the mirror, $args{nick}."; }
    else
      { $message = "$player{'name'} is right with you on this server!"; }
  }

  else
  {
    my ($seen_result, $timestamp, $name) = get_seen($args{'arg1'});

    if ($seen_result == 1)
      { $message = "$name was last seen on this server ".get_time_difference(time(),$timestamp)." ago"; }

    elsif ($seen_result == 2)
      { $message = "More than one match found for \"$args{arg1}\". Please be more precise in your query!"; }

    else
      { $message = "I do not recall seeing $args{arg1} here..."; }
  }

  # Output whatever message we now have
  if ( $args{'nicktype'} == 1 )
    { plugin::ircmsg($message, $args{'ircChannelCode'}); }
  else
    { plugin::serverMsg($message); }
}




# --------------------------------------------------------------------------------------------------
##
#### Utility Functions
##
# --------------------------------------------------------------------------------------------------

sub updateTime
{
  # Convert to lowercase and strip out any ""
  my $name = lc(shift);
  $name =~ s/"/\'/g;

  # Check if the record exists in the database
  my @result = plugin::execute_query("SELECT timestamp FROM seen WHERE LOWER(name) = '$name'");
  if (scalar(@result) == 1)
    { plugin::execute_query('UPDATE seen SET timestamp = '.time()." WHERE LOWER(name) = '$name'",1); }
  else
    { plugin::execute_query('INSERT INTO seen (timestamp, name) VALUES ('.time().", '$name')",1); }
}

# Function for getting the last time a specified player was seen
#
# PARAM   name    Full or partial name of player to find
#
# RETURN $result, $timestamp, $name
# 0 = Not found
# 1 = Found unique match
# 2 = Found multiple matches
sub get_seen($)
{
  # Convert to lowercase and strip out any ""
  my $name = lc(shift);
  $name =~ s/"/\'/g;
  
  # Try an exact match first
  my @result = plugin::execute_query("SELECT name, timestamp FROM seen WHERE LOWER(name) = '$name'");
  if (scalar(@result) == 1)
  {
    return (1,$result[0]->{'timestamp'},$result[0]->{'name'});
  }
  
  # Try a wildcard match
  my @result = plugin::execute_query("SELECT name, timestamp FROM seen WHERE LOWER(name) LIKE \"%$name%\"");
  if (scalar(@result) == 1)
  {
    return (1,$result[0]->{'timestamp'},$result[0]->{'name'});
  }
  
  return (scalar(@result)>1) ? 2 : 0;
}

sub get_time_difference($$)
{
  my $difference = abs(shift - shift);

  # All calculations will assume a month = 30 days, and a year = 365 days
  my ($years, $months, $weeks, $days, $hours, $minutes) = (0, 0, 0, 0, 0, 0);

  $years = int($difference/30758400);
  $difference -= $years*30758400;

  $months = int($difference/2592000);
  $difference -= $months*2592000;

  return "$years years" . (($months>0) ? " and $months months" : "") if ($years > 0);

  $weeks = int($difference/604800);
  $difference -= $weeks*604800;

  return "$months months" . (($weeks>0) ? " and $weeks weeks" : "") if ($months > 0);

  $days = int($difference/86400);
  $difference -= $days*86400;

  return "$weeks weeks" . (($days>0) ? " and $days days" : "") if ($weeks > 0);

  $hours = int($difference/3600);
  $difference -= $hours*3600;

  return "$days days" . (($hours>0) ? " and $hours hours" : "") if ($days > 0);

  $minutes = int($difference/60);
  $difference -= $minutes*60;

  $string = "";
  $string .= "$hours hours" if ($hours > 0);
  $string .= (($string ne"")?", ":"")."$minutes minutes" if ($minutes > 0);
  $string .= (($string ne"")?"and ":"")."$difference seconds" if ($difference > 0);

  return $string;
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
  my $db_version = plugin::get_global ( "version_plugin_seen" );
  if ( defined($db_version) and $db_version > $currentVersion )
  {
    plugin::console_output("[Seen] The database has been modified by a newer version of"
        ." this plugin. To avoid potential data corruption the plugin will now stop");
    return 0;
  }

  # Current table definitions
  my %tables = (
    plugin_seen => "CREATE TABLE plugin_seen(id INT PRIMARY KEY, name CHAR(128), timestamp INT)"
  );

  # Check which tables already exist...
  my @db_tables = plugin::execute_query( "SELECT name FROM sqlite_master" );
  foreach (@db_tables)
    { delete $tables{$_->{'name'}}; }

  # Create any missing tables
  while ( my($table,$definition) = each %tables )
  {
    plugin::console_output("[Seen] Creating missing table " . $table);
    plugin::execute_query( $definition, 1 );
    delete $tables{$table};
  }


  # Nothing to update at the moment...
  return 1;
}


# Plugin loaded OK
1;