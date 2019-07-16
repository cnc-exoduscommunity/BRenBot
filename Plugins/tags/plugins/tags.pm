#**
# This plugin allows moderators to assign tags to a player to appear below their name in the
# server. Requires SSGM 4.0 or above. Originally written by Catalyst and updated by danpaul88
#
# \author Catalyst
# \author Daniel Paul (danpaul88@yahoo.co.uk)
# \version 1.1
#*

package tags;

use POE;
use plugin;

my $currentVersion = '1.1';
my $loaded_ok = undef;

# Check bot compatibility
if ( !defined(plugin::getBrVersion) || plugin::getBrVersion() < 1.53
  || (plugin::getBrVersion() == 1.53 && plugin::getBrBuild() < 15 ) )
{
  print ' == Tags Plugin Error ==\n'
      . 'This version of the plugin is not compatible with BRenBot versions older than 1.53.15\n';
  return 0;
}

# --------------------------------------------------------------------------------------------------

# BRenBot supplies these on plugin startup
our $plugin_name;
our %config;

# Define additional events in the POE session
our %additional_events =
(
  'tag'         => 'tag'
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
  plugin::set_global ( 'version_plugin_tags', $currentVersion );

  return ($loaded_ok = 1);
}

sub stop
{
}

sub playerjoin
{
  return if ($loaded_ok == 0);

  # Player joined the server, get their tag from the database and apply it
  my %args = %{$_[ARG0]};
  my $tag = get_tag($args{'nick'});
  RenRem::RenRemCMD('tag '.$args{'id'}.' '.$tag) if defined $tag;
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
  $_[KERNEL]->yield ( $args{'command'} => \%args );
}




# --------------------------------------------------------------------------------------------------
##
#### Commands
##
# --------------------------------------------------------------------------------------------------

# !tag command - Sets a new tag for the specified player
sub tag
{
  my %args = %{$_[ARG0]};
  
  # Syntax check...
  if ( ($args{'arg'} =~ /^\!\S+\s(.+?)\s(.+)/i) )
  {
    my $target = $1;
    my $tag = $2;
    
    my ( $result, %player ) = plugin::getPlayerData($target);
    if ( $result == 1 )
    {
      if ( length($tag) > 32 )
      {
        my $message = "The specified tag is too long, please use 32 characters or less";
        
        if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
        else { plugin::pagePlayer( $args{'nick'}, 'BRenBot', $message ); }
      }
      else
      {
        save_tag($player{'name'}, $args{'nick'}, $tag);
        RenRem::RenRemCMD('tag '.$player{'id'}.' '.$tag);
      }
    }
    else
    {
      my $message = "Player $target was not found ingame, or is not unique.";
      
      if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
      else { plugin::pagePlayer( $args{'nick'}, 'BRenBot', $message ); }
    }
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
sub get_tag
{
  my $name    = lc(shift);            $name =~ s/'/''/g;

  my @tagData = plugin::execute_query ( "SELECT tag FROM tags WHERE LOWER(name) = '$name'" );
  return $tagData[0]->{'tag'} if (scalar(@tagData) > 0);
  return undef;
}

# Save a new or updated tag to the database
sub save_tag
{
  my $name    = lc(shift);            $name =~ s/'/''/g;
  my $tagger  = lc(shift);            $tagger =~ s/'/''/g;
  my $tag     = shift;                $tag =~ s/'/''/g;
  
  if ( defined get_tag($name) )
  {
    plugin::execute_query ( "UPDATE tags SET tagger = '$tagger', tag = '$tag' WHERE LOWER(name) = '$name'", 1 );
  }
  else
  {
    plugin::execute_query ( "INSERT INTO tags (name, tagger, tag) VALUES ( '$name', '$tagger', '$tag')", 1 );
  }
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

  if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( "Usage: $syntaxvalue", $args{'ircChannelCode'} ); }
  else { plugin::pagePlayer( $args{'nick'}, 'BRenBot', "Usage: $syntaxvalue" ); }
}




# --------------------------------------------------------------------------------------------------
##
#### Database configuration
##
# --------------------------------------------------------------------------------------------------

sub db_update
{
  my $db_version = plugin::get_global ( "version_plugin_tags" );
  if ( defined($db_version) and $db_version > $currentVersion )
  {
    plugin::console_output("[Tags] The database has been modified by a newer version of"
        ." this plugin. To avoid potential data corruption the plugin will now stop");
    return 0;
  }

  # Current table definitions
  my %tables = (
    tags => "CREATE TABLE tags ( name TEXT PRIMARY KEY, tagger TEXT, tag TEXT )"
  );

  # Check which tables already exist...
  my @db_tables = plugin::execute_query( "SELECT name FROM sqlite_master" );
  foreach ( @db_tables )
    { delete $tables{$_->{'name'}}; }

  # Create any missing tables
  while ( my($table,$definition) = each %tables )
  {
    plugin::console_output("[Tags] Creating missing table " . $table);
    plugin::execute_query( $definition, 1 );
    delete $tables{$table};
  }



  # Nothing to update at the moment...
  return 1;
}


# Plugin loaded OK
1;