#**
# This plugin contains the join messages functionality that used to exist in BRenBot prior to
# version 1.53.15. It allows players to set a message to be shown in the server every time they
# join.
#
# \author Daniel Paul (danpaul88@yahoo.co.uk)
# \version 1.0
#*

package joinmessages;

use POE;
use plugin;

my $currentVersion = '1.0';
my $loaded_ok = undef;

# Check bot compatibility
if ( !defined(plugin::getBrVersion) || plugin::getBrVersion() < 1.53
  || (plugin::getBrVersion() == 1.53 && plugin::getBrBuild() < 14 ) )
{
  print " == Join Messages Plugin Error ==\n"
      . "This version of the plugin is not compatible with BRenBot versions older than 1.53.14\n";
  return 0;
}

# --------------------------------------------------------------------------------------------------

# BRenBot supplies these on plugin startup
our $plugin_name;
our %config;

# Define additional events in the POE session
our %additional_events =
(
  'setjoin'     => 'setjoin',
  'viewjoin'    => 'viewjoin'
);




# --------------------------------------------------------------------------------------------------
##
#### Bot Events
##
# --------------------------------------------------------------------------------------------------

sub start
{
  return ($loaded_ok = 0) if ( db_update() != 1 );

  # Set our current version in the globals table
  plugin::set_global ( "version_plugin_joinmessages", $currentVersion );

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

sub playerjoin
{
  return if ($loaded_ok == 0);

  my %args = %{$_[ARG0]};
  my $joinmessage = get_joinmessage($args{'nick'});
  if ( defined($joinmessage) )
    { plugin::serverMsg ( '['.$args{'nick'}.'] '.$joinmessage ); }
}

sub command
{
  return if ($loaded_ok == 0);

  my %args = %{$_[ARG0]};
  $_[KERNEL]->yield ( $args{'command'} => \%args );
}




# --------------------------------------------------------------------------------------------------
##
#### Commands
##
# --------------------------------------------------------------------------------------------------

# !setjoin command - Sets a users join message
sub setjoin
{
  my %args = %{$_[ ARG0 ]};
  return if ( $args{'nicktype'} == 1 );

  if ($args{arg} =~ /^\!\w+\s*(\S(.+))/i)  #set joinmessage
  {
    my $setjoin_msg = substr( $1, 0, 249 ); # Limit length to prevent FDS crash
    set_joinmessage( $args{'nick'}, $setjoin_msg );
    plugin::pagePlayer( $args{'nick'}, 'BRenBot', "Your join message has been set." );
  }
  else
    { show_syntax_error(@_); }
}

# !viewjoin command - Shows a user their current join message
sub viewjoin
{
  my %args = %{$_[ ARG0 ]};
  return if ( $args{'nicktype'} == 1 );

  my $jointext = get_joinmessage( $args{'nick'} );
  if ( $jointext )
  {
    $jointext=substr($jointext,0,249); # Limit length to prevent FDS crash
    plugin::pagePlayer( $args{'nick'}, 'BRenBot', "Your joinmessage is '$jointext'" );
  }
  else
  {
    plugin::pagePlayer( $args{'nick'}, 'BRenBot', "You do not have a join message set. Set one with !setjoin <jointext>." );
  }
}




# --------------------------------------------------------------------------------------------------
##
#### Data lookup & storage functions
##
# --------------------------------------------------------------------------------------------------

sub set_joinmessage
{
  my $name = lc(shift);               $name =~ s/'/''/g;
  my $message = shift;                $message =~ s/'/''/g;

  if ( !defined(get_joinmessage($name)) )
    { plugin::execute_query( "INSERT INTO join_messages ( name, message ) VALUES ( '$name','$message' )", 1 ); }
  else
    { plugin::execute_query( "UPDATE join_messages SET message = '$message' WHERE LOWER(name) = '$name'", 1 ); }
}

sub get_joinmessage
{
  my $name = lc(shift);               $name =~ s/'/''/g;

  my @array = plugin::execute_query( "SELECT * FROM join_messages WHERE LOWER(name) = '$name'" );
  return $array[0]->{'message'} if ( scalar(@array) > 0 );
  return undef;
}




# --------------------------------------------------------------------------------------------------
##
#### Utility Functions
##
# --------------------------------------------------------------------------------------------------

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
  # Note: BRenBot will update the database all the way up to the format that was used up to 1.54.14
  #       automatically for us, so we don't need to worry about it being any older than that

  my $db_version = plugin::get_global ( "version_plugin_joinmessages" );
  if ( defined($db_version) and $db_version > $currentVersion )
  {
    plugin::console_output("[Join Messages] The database has been modified by a newer version of"
        ." this plugin. To avoid potential data corruption the plugin will now stop");
    return 0;
  }

  # Current table definitions
  my %tables = (
    join_messages => "CREATE TABLE join_messages ( name TEXT PRIMARY KEY, message TEXT )"
  );

  # Check which tables already exist...
  my @db_tables = plugin::execute_query( "SELECT name FROM sqlite_master" );
  foreach ( @db_tables )
    { delete $tables{$_->{'name'}}; }

  # Create any missing tables
  while ( my($table,$definition) = each %tables )
  {
    plugin::console_output("[Join Messages] Creating missing table " . $table);
    plugin::execute_query( $definition, 1 );
    delete $tables{$table};
  }



  # Nothing to update at the moment...
  return 1;
}


# Plugin loaded OK
1;