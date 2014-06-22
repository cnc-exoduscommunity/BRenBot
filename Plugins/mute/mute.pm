#**
# A plugin that allows a moderator to mute or unmute a plugin
#
# \author Daniel Paul (danpaul88@yahoo.co.uk)
# \version 1.00
#*

package mute;

use POE;
use plugin;

my $currentVersion = '1.00';
my $loaded_ok = undef;

# Check bot compatibility
if ( !defined(plugin::getBrVersion) || plugin::getBrVersion() < 1.54
  || (plugin::getBrVersion() == 1.54 && plugin::getBrBuild() < 1 ) )
{
  print ' == Mute Plugin Error ==\n'
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
  'mute'        => 'mute',
  'unmute'      => 'unmute'
);

# Forward declarations
sub is_muted($);
sub save_mute($$$$);
sub delete_mute($);




# --------------------------------------------------------------------------------------------------
##
#### Bot Events
##
# --------------------------------------------------------------------------------------------------

sub start
{
  return ($loaded_ok = 0) if (1 != db_update());

  plugin::set_global("version_plugin_mute", $currentVersion);

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

  # Player joined the server, check if they are still muted
  my %args = %{$_[ARG0]};

  my ($mute_id, $muter, $datetime, $reason, $duration) = is_muted($args{'nick'});
  if (0 != $mute_id)
  {
    plugin::RenRemCMD('mute '.$args{'id'});
    plugin::send_message($args{'name'}." was muted on $datetime by $muter for $reason");
    plugin::send_message_player("You were muted on $datetime by $muter for $reason", $args{'id'}, 'BRenBot');
  }
}




# --------------------------------------------------------------------------------------------------
##
#### Commands
##
# --------------------------------------------------------------------------------------------------

# !mute command
sub mute
{
  my %args = %{$_[ARG0]};

  # Check they supplied a name to search for
  if ($args{'arg'} =~ /^\!\S+\s(.+?)\s(\d+)\s(\S+)\s(.+)/i)
  {
    my $target = $1;
    my $duration_num = $2;
    my $duration_type = lc($3);
    my $reason = $4;

    my ($result, %player) = plugin::getPlayerData($target);
    if (1 != $result)
    {
      my $message = "Player $target was not found ingame, or is not unique.";
      
      if (1 == $args{'nicktype'}) { plugin::ircmsg($message, $args{'ircChannelCode'}); }
      else { plugin::pagePlayer($args{'nick'}, 'BRenBot', $message); }
      return;
    }

    # Check they are not already muted
    my ($mute_id, undef, undef, undef, undef) = is_muted($target);
    if (0 != $mute_id)
    {
      $message = "Player $player is already muted";
      
      if (1 == $args{'nicktype'}) { plugin::ircmsg($message, $args{'ircChannelCode'}); }
      else { plugin::pagePlayer($args{'nick'}, 'BRenBot', $message); }
      return;
    }


    # Figure out the mute duration in seconds
    my $duration = $duration_num;
    if ($duration_type == 'minute' or $duration_type == 'minutes')    { $duration *= 60; }
    elsif ($duration_type == 'hour' or $duration_type == 'hours')     { $duration *= 3600; }
    elsif ($duration_type == 'day' or $duration_type == 'days')       { $duration *= 86400; }
    elsif ($duration_type == 'week' or $duration_type == 'weeks')     { $duration *= 604800; }
    elsif ($duration_type == 'month' or $duration_type == 'months')   { $duration *= 2592000; }
    elsif ($duration_type == 'year' or $duration_type == 'years')     { $duration *= 31449600; }
    elsif ($duration_type != 'second' and $duration_type != 'seconds')
    {
      report_syntax_error(\%args);
      return;
    }

    save_mute($player{'name'}, $args{'nick'}, $reason, $duration);

    plugin::RenRemCMD('mute '.$player{'id'});
    plugin::send_message($player{'name'}." has been muted for $duration_num $duration_type by ".$args{'nick'}." for $reason");
    plugin::send_message_player("You have been muted for $duration_num $duration_type by ".$args{'nick'}." for $reason", $player{'id'}, 'BRenBot');
    plugin::write_to_log(13, "[Mute] $player{'name'} was muted for $duration_num $duration_type by ".$args{'nick'}." for $reason");
  }

  else
    { report_syntax_error(\%args); }
}

# !unmute command
sub unmute
{
  my %args = %{$_[ARG0]};

  # Check they supplied a name to search for
  if ($args{'arg'} =~ /^\!\S+\s(.+?)/i)
  {
    my $target = $1;

    my ($result, %player) = plugin::getPlayerData($target);
    if (1 != $result)
    {
      my $message = "Player $target was not found ingame, or is not unique.";
      
      if (1 == $args{'nicktype'}) { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
      else { plugin::pagePlayer( $args{'nick'}, 'BRenBot', $message ); }
      return;
    }

    # Check they are muted
    my ($mute_id, undef, undef, undef, undef) = is_muted($target);
    if (0 == $mute_id)
    {
      $message = "Player $player is not muted";
      
      if (1 == $args{'nicktype'}) { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
      else { plugin::pagePlayer( $args{'nick'}, 'BRenBot', $message ); }
      return;
    }

    delete_mute($mute_id);

    plugin::RenRemCMD('unmute '.$player{'id'});
    plugin::send_message($player{'name'}." has been unmuted by ".$args{'nick'});
    plugin::send_message_player("You have been unmuted by ".$args{'nick'}, 'BRenBot');
    plugin::write_to_log(13, "[Mute] $player{'name'} was unmuted by ".$args{'nick'});
  }

  else
    { report_syntax_error(\%args); }
}




# --------------------------------------------------------------------------------------------------
##
#### Data lookup & storage functions
##
# --------------------------------------------------------------------------------------------------

# Gets the tag for the specified player
sub is_muted($)
{
  my $name      = lc(shift);            $name =~ s/'/''/g;

  my @muteData = plugin::execute_query("SELECT * FROM plugin_mute WHERE LOWER(name) = '$name'");
  if (scalar(@muteData) > 0)
  {
    my $remaining_duration = $muteData[0]->{'duration'} - (time() - $muteData[0]->{'timestamp'});
    if ($remaining_duration > 0)
    {
      return ($muteData[0]->{'id'},
      $muteData[0]->{'muter'},
      plugin::strftimestamp('%d/%m/%Y at %H:%M:%S', $muteData[0]->{'timestamp'}),
      $muteData[0]->{'reason'},
      $remaining_duration);
    }

    delete_mute($muteData[0]->{'id'});
  }

  return (0,undef,undef,undef,undef);
}

# Record a mute to the database
sub save_mute($$$$)
{
  my $name      = lc(shift);            $name =~ s/'/''/g;
  my $muter     = shift;                $muter =~ s/'/''/g;
  my $reason    = shift;                $reason =~ s/'/''/g;
  my $duration  = int(shift);

  plugin::execute_query(
    "INSERT INTO plugin_mute ("
      ."name, muter, reason, timestamp, duration"
    .") VALUES ("
      ."'$name', '$muter', '$reason', ".time().",$duration)", 1);
}

# Remove a mute from the database
sub delete_mute($)
{
  my $id        = int(shift);

  plugin::execute_query("DELETE FROM plugin_mute WHERE id = $id", 1) if ($id > 0);
}




# --------------------------------------------------------------------------------------------------
##
#### Utility functions
##
# --------------------------------------------------------------------------------------------------

# Reports a syntax error to the user when using a !command with the wrong parameters
sub report_syntax_error
{
  my(%args) = @_;
  
  my $syntaxvalue = $args{'settings'}->{'syntax'}->{'value'};

  if (1 == $args{'nicktype'}) { plugin::ircmsg("Usage: $syntaxvalue", $args{'ircChannelCode'}); }
  else { plugin::pagePlayer($args{'nick'}, 'BRenBot', "Usage: $syntaxvalue"); }
}




# --------------------------------------------------------------------------------------------------
##
#### Database configuration
##
# --------------------------------------------------------------------------------------------------

sub db_update
{
  my $db_version = plugin::get_global("version_plugin_mute");
  if (defined($db_version) and $db_version > $currentVersion)
  {
    plugin::console_output("[Mute] The database has been modified by a newer version of"
        ." this plugin. To avoid potential data corruption the plugin will now stop");
    return 0;
  }

  # Current table definitions
  my %tables = (
    plugin_mute => "CREATE TABLE plugin_mute(ID INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, muter TEXT, reason TEXT, timestamp INTEGER, duration INTEGER)"
  );

  # Check which tables already exist...
  my @db_tables = plugin::execute_query("SELECT name FROM sqlite_master");
  foreach (@db_tables)
    { delete $tables{$_->{'name'}}; }

  # Create any missing tables
  while ( my($table,$definition) = each %tables )
  {
    plugin::console_output("[Mute] Creating missing table " . $table);
    plugin::execute_query($definition, 1);
    delete $tables{$table};
  }


  # Nothing to update at the moment...
  return 1;
}


# Plugin loaded OK
1;