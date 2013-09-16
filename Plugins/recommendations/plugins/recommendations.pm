#**
# The recommendations plugin for BRenBot 1.54 and newer, this contains all the functionality of the
# recommendations system that existed in BRenBot prior to version 1.53.14
#
# \author Daniel Paul (danpaul88@yahoo.co.uk)
# \version 1.0
#*

package recommendations;

use POE;
use plugin;

my $currentVersion = '1.0';
my $loaded_ok = undef;

# Check bot compatibility
if ( !defined(plugin::getBrVersion) || plugin::getBrVersion() < 1.53
  || (plugin::getBrVersion() == 1.53 && plugin::getBrBuild() < 14 ) )
{
  print " == Recommendations Plugin Error ==\n"
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
  'recommend'   => 'recommend',
  'n00b'        => 'recommend',     # Same code for both functions
  'recignore'   => 'recignore',
  'recallow'    => 'recallow',
);

my $tpLastUsed = 0;   # Global variable used to track last used time for !teamplayers/!shown00bs
my @joinmessages;
my %autorec_cache;    # Tracks per-player data for auto recommendations




# --------------------------------------------------------------------------------------------------
##
#### Bot Events
##
# --------------------------------------------------------------------------------------------------

sub start
{
  return ($loaded_ok = 0) if ( db_update() != 1 );

  # Set our current version in the globals table
  plugin::set_global ( "version_plugin_recommendations", $currentVersion );
  
  read_recs();
  
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
  
  # Show join message after 5 seconds
  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
        $_[HEAP]->{'playername'} = $args{'nick'};
        $_[KERNEL]->delay('show_joinmessage' => 5);
      },
      show_joinmessage => \&show_joinmessage
    }
  );
}

sub command
{
  return if ($loaded_ok == 0);

  my %args = %{$_[ARG0]};
  $_[KERNEL]->yield ( $args{'command'} => \%args );
}

# Gameresult event - Triggers once BRenBot has read the results##.txt file at the end of the map
sub gameresult
{
  return if ($loaded_ok == 0);

  my %args = %{$_[ARG0]};
  my @results = @{$args{'gameresults'}};

  # Data storage...
  my $mvp = undef;
  my $mvp_score = $config{'autorec_min_score'}-1;
  my $mostkills = undef;
  my $mostkills_kills = $config{'autorec_min_kills'}-1;
  my $bestkd = undef;
  my $bestkd_kd = $config{'autorec_min_kd'}-0.01;

  # Process the results array
  foreach ( @results )
  {
    if ( $_->{'score'} > $mvp_score )
    {
      $mvp = $_->{'name'};
      $mvp_score = $_->{'score'};
    }
    
    if ( $_->{'kills'} > $mostkills_kills )
    {
      $mostkills = $_->{'name'};
      $mostkills_kills = $_->{'score'};
    }
    
    if ( $_->{'kdratio'} > $bestkd_kd )
    {
      $bestkd = $_->{'name'};
      $bestkd_kd = $_->{'kdratio'};
    }
  }
  
  # Grant recommendations in 45 seconds time (giving the next map time to load)
  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
        $_[KERNEL]->delay('grant_recommendations' => 45);
      },
      show_joinmessage => sub
      {
        if ( defined($mvp) && $config{'autorec_min_score'} > 0 )
          { recommend_player( $mvp, 'BRenBot', 'MVP on '.$args{'map'}.' with '.$mvp_score.' points' ); }
        if ( defined($mostkills) && $config{'autorec_min_kills'} > 0 )
          { recommend_player( $mostkills, 'BRenBot', 'Most Kills on '.$args{'map'}.' with '.$mostkills_kills.' frags' ); }
        if ( defined($bestkd) && $config{'autorec_min_kd'} > 0 )
          { recommend_player( $bestkd, 'BRenBot', 'Best K/D Ratio on '.$args{'map'}.' with '.$bestkd_kd ); }
      }
    }
  );
}

# Called when a new map has loaded
sub mapload
{
  return if ($loaded_ok == 0);

  while ( my ( $player, $stats ) = each ( %autorec_cache ) )
  {
    while ( my ( $stat_name, $stat_value ) = each ( %{$stats} ) )
      { delete $autorec_cache{$player}{$stat_name}; }
    delete $autorec_cache{$player};
  }
}




# --------------------------------------------------------------------------------------------------
##
#### Gamelog hook events
##
# --------------------------------------------------------------------------------------------------

# Building kill detected
sub gamelog_building_killed
{
  return if ( $loaded_ok == 0 or $config{'autorec_two_buildings_killed'} <= 0 );
  
  my %args = %{$_[ARG0]};
  my $line = $args{'line'};

  #KILLED;BUILDING;1500000045;CnC_GDI_Barracks;72;-87;0;-175;1500001168;CnC_Nod_Minigunner_0;67;-95;0;-145;Weapon_AutoRifle_Player_Nod
  if ( $line =~ m/KILLED;BUILDING;\d+;([^;]+);-?\d+;-?\d+;-?\d+;-?\d+;(\d+);[^;]+;-?\d+;-?\d+;-?\d+;-?\d+;/i )
  {
    my $building = plugin::translatePreset($1);
    my $player = plugin::getPlayerFromObjectID($2);
    if ( defined ( $player ) )
    {
      $autorec_cache{$player} = {} if (!exists($autorec_cache{$player}));
      
      if ( !defined($autorec_cache{$player}{'buildingKillA'}) )
        { $autorec_cache{$player}{'buildingKillA'} = $building; }
      
      else
      {
        my $building_1 = $autorec_cache{$player}{'buildingKillA'};
        my $building_2 = $building;
        
        if ( 1 != $args{'startup'} && !is_rec_ignored($player) )
          { recommend_player($player, 'BRenBot', "Destroyed $building_1 and $building_2" ); }
          
        delete $autorec_cache{$player}{'buildingKillA'};
      }
    }
  }
}

# Building repair detected
sub gamelog_building_repair
{
  return if ( $loaded_ok == 0 or $config{'autorec_min_building_repair'} <= 0 );
  
  my %args = %{$_[ARG0]};
  my $line = $args{'line'};

  #DAMAGED;BUILDING;1500000045;CnC_GDI_Barracks;72;-87;0;-175;1500001168;CnC_Nod_Minigunner_0;65;-104;0;-173;2.399994;150;147;0
  if ( $line =~ m/DAMAGED;BUILDING;\d+;[^;]+;-?\d+;-?\d+;-?\d+;-?\d+;(\d+);[^;]+;-?\d+;-?\d+;-?\d+;-?\d+;(-\d+\.\d+);\d+;\d+;\d+$/i )
  {
    my $repairAmount = $2;
    my $player = plugin::getPlayerFromObjectID($1);
    if ( defined ( $player ) )
    {
      $autorec_cache{$player} = {} if (!exists($autorec_cache{$player}));
      
      if ( !defined($autorec_cache{$player}{'buildingRepairs'}) )
        { $autorec_cache{$player}{'buildingRepairs'} = $2; }
      
      else
        { $autorec_cache{$player}{'buildingRepairs'} += $2; }
        
      if ( $autorec_cache{$player}{'buildingRepairs'} >= $config{'autorec_min_building_repair'} )
      {
        if ( 1 != $args{'startup'} && !is_rec_ignored($player) )
          { recommend_player($player, 'BRenBot', "Repairing the base" ); }
          
        $autorec_cache{$player}{'buildingRepairs'} -= $config{'autorec_min_building_repair'};
      }
    }
  }
}

# Vehicle kill detected
sub gamelog_vehicle_killed
{
  return if ( $loaded_ok == 0 or $config{'autorec_min_vehicle_kills'} <= 0 );
  
  my %args = %{$_[ARG0]};
  my $line = $args{'line'};

  #KILLED;VEHICLE;1500000045;CnC_GDI_Humm-vee;72;-87;0;-175;1500001168;CnC_Nod_Minigunner_0;67;-95;0;-145;Weapon_AutoRifle_Player_Nod
  if ( $line =~ m/KILLED;VEHICLE;\d+;([^;]+);-?\d+;-?\d+;-?\d+;-?\d+;(\d+);[^;]+;-?\d+;-?\d+;-?\d+;-?\d+;/i )
  {
    my $player = plugin::getPlayerFromObjectID ( $2 );
    if ( defined ( $player ) )
    {
      $autorec_cache{$player} = {} if (!exists($autorec_cache{$player}));
      
      if ( !defined($autorec_cache{$player}{'vehicleKills'}) )
        { $autorec_cache{$player}{'vehicleKills'} = 1; }
      
      else
        { $autorec_cache{$player}{'vehicleKills'} += 1; }
        
      if ( $autorec_cache{$player}{'vehicleKills'} >= $config{'autorec_min_vehicle_kills'} )
      {
        if ( 1 != $args{'startup'} && !is_rec_ignored($player) )
          { recommend_player($player, 'BRenBot', 'Destroying '.$autorec_cache{$player}{'vehicleKills'}.' enemy vehicles'); }
          
        $autorec_cache{$player}{'vehicleKills'} -= $config{'autorec_min_vehicle_kills'};
      }
    }
  }
}

# Vehicle repair detected
sub gamelog_vehicle_repair
{
  return if ( $loaded_ok == 0 or $config{'autorec_min_vehicle_repair'} <= 0 );
  
  my %args = %{$_[ARG0]};
  my $line = $args{'line'};

  #DAMAGED;VEHICLE;1500000930;CnC_GDI_Medium_Tank;-132;4;-2;142;1500000189;CnC_GDI_Engineer_0;-127;4;-3;-92;-2.000000;400;390;0
  if ( $line =~ m/DAMAGED;VEHICLE;\d+;[^;]+;-?\d+;-?\d+;-?\d+;-?\d+;(\d+);[^;]+;-?\d+;-?\d+;-?\d+;-?\d+;(-\d+\.\d+);\d+;\d+;\d+$/i )
  {
    my $player = plugin::getPlayerFromObjectID ( $1 );
    if ( defined ( $player ) )
    {
      $autorec_cache{$player} = {} if (!exists($autorec_cache{$player}));
      
      if ( !defined($autorec_cache{$player}{'vehicleRepairs'}) )
        { $autorec_cache{$player}{'vehicleRepairs'} = $2; }
      
      else
        { $autorec_cache{$player}{'vehicleRepairs'} += $2; }
        
      if ( $autorec_cache{$player}{'vehicleRepairs'} >= $config{'autorec_min_vehicle_repair'} )
      {
        if ( 1 != $args{'startup'} && !is_rec_ignored($player) )
          { recommend_player($player, 'BRenBot', "Repairing their teams vehicles" ); }
          
        $autorec_cache{$player}{'vehicleRepairs'} -= $config{'autorec_min_vehicle_repair'};
      }
    }
  }
}




# --------------------------------------------------------------------------------------------------
##
#### Commands
##
# --------------------------------------------------------------------------------------------------

# !recommend command, commonly aliased as !rec, this allows a player to recommend another player for
# good teamwork... or any other reason they like really.
sub recommend
{
  my %args = %{$_[ARG0]};
  my $isNoob = ($args{'command'} eq "n00b") ? 1 : 0;

  # Only available for use ingame
  if ( $args{'nicktype'} == 1 )
  {
    plugin::ircmsg ( "This command can only be used by players in the server", $args{'ircChannelCode'} );
    return;
  }

  # Check for rec_ignore
  if ( is_rec_ignored($args{'nick'}) )
  {
    plugin::pagePlayer( $args{'nick'}, 'BRenBot', "Sorry, the server administrators have disabled recommendations for you" );
    return;
  }
  
  # Syntax check...
  if ( ($args{'arg'} =~ /^\!\S+\s(.+?)\s(.+)/i) )
  {
    my $target = $1;
    my $reason = $2;

    my ( $result, %player ) = plugin::getPlayerData ( $target );
    if ( $result == 1 )
    {
      if ( $player{'name'} eq $args{'nick'} and $isNoob == 0 )
      {
        plugin::pagePlayer( $args{'nick'}, 'BRenBot', "You are not allowed to recommend yourself.");
        return;
      }

      my $can_recommend = can_recommend ( $args{'nick'}, $player{'name'}, $isNoob );
      if ( $can_recommend == 1 )
      {
        recommend_player( $player{'name'}, $args{'nick'}, $reason );
      }
      elsif ( $can_recommend == 2 )
      {
        plugin::pagePlayer( $args{'nick'}, 'BRenBot', "You have reached your daily limit for recommendations" );
      }
      else
      {
        plugin::pagePlayer( $args{'nick'}, 'BRenBot', 'You have already '.(($isNoob==0)?'recommended':'n00bed')." $player{'name'} today." );
      }
    }
    else
    {
      plugin::pagePlayer( $args{'nick'}, 'BRenBot', "Player $target was not found ingame, or is not unique." );
    }
  }
  
  else
    { report_syntax_error(\%args); }
}


# !recommendations command, commonly aliased as !recs, this allows an ingame player to check their
# recommendations score
sub recommendations
{
  my %args = %{$_[ARG0]};

  # Only available for use ingame
  if ( $args{'nicktype'} == 1 )
  {
    plugin::ircmsg ( "This command can only be used by players in the server", $args{'ircChannelCode'} );
    return;
  }

  # Get recommendations and n00bs for $args{nick}
  my $recommendations = get_recommendation ( $args{'nick'} );
  my $n00bs = get_n00b ( $args{'nick'} );

  plugin::pagePlayer ( $args{'nick'}, "BRenBot", "You currently have ".($recommendations-$n00bs)." recommendations. ( $recommendations recs, $n00bs n00bs )" );
}


# !recignore command, used by moderators to ignore players for the recommendations system, which
# prevents them from giving or receiving recommendations
sub recignore
{
  my %args = %{$_[ARG0]};

  if (!$args{'arg1'})
  {
    report_syntax_error(\%args);
    return;
  }

  my ( $result, %player ) = plugin::getPlayerData( $args{'arg1'} );
  if ( $result == 1 )
  {
    plugin::serverMsg( "Recommendations have been disabled for $player{name}.");
    rec_ignore( $player{'name'} );

    # Write the rec-ignore to the logs table
    plugin::write_to_log ( 12, "[Recommendations] $player{name} was rec ignored by $args{nick}." );
  }
  else
  {
    my $message = "$args{arg1} is not ingame, or the name is not unique.";
    if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
    else { plugin::pagePlayer($args{'nick'}, 'BRenBot', $message ); }
  }
}


# !recallow command, used by moderators to un-ignore players for the recommendations system
sub recallow
{
  my %args = %{$_[ARG0]};

  if (!$args{'arg1'})
  {
    report_syntax_error(\%args);
    return;
  }

  my ( $result, %player ) = plugin::getPlayerData( $args{'arg1'} );
  if ( $result == 1 )
  {
    plugin::serverMsg( "Recommendations have been enabled for ".$player{'name'} );
    rec_allow( $player{'name'} );

    # Write the rec-allow to the logs table
    plugin::write_to_log ( 12, "[Recommendations] $player{name} was rec allowed by $args{nick}." );
  }
  else
  {
    my $message = "$args{arg1} is not ingame, or the name is not unique.";
    if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
    else { plugin::pagePlayer($args{'nick'}, 'BRenBot', $message ); }
  }
}


# !teamplayers / !shown00bs commands, these commands list the total recommendations or n00bs for all
# players currently in the server
sub teamplayers
{
  my %args = %{$_[ARG0]};
  my $showNoobs = ($args{'command'} eq "shown00bs") ? 1 : 0;
  
  # Check if there are any players in the server
  my $playerCount = (plugin::getGameStatus())[6];
  if ( $playerCount == 0 )
  {
    plugin::ircmsg ( "There are no players in the server", $args{'ircChannelCode'} );
    return;
  }


  # Too recently used?
  if ( time() - $tpLastUsed < 120 )
  {
    if ( $args{'nicktype'} == 1 ) { plugin::ircmsg ( "The !teamplayers/!shown00bs commands can only be used once every 2 minutes!" ); }
    else { plugin::serverMsg ( "The !teamplayers/!shown00bs command can only be used once every 2 minutes! Use !recs to see your own recommendations." ); }
    return;
  }
  else { $tpLastUsed = time(); }
  
  
  # Print header line
  if ( $nPlayersWithRecs == 0 )
  {
    my $message = ($showNoobs==1)?'n00bs based on in-game complaints;':'Teamplayers based on recommendations;';
    if ( $args{'nicktype'} == 1 )
      { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
    else
      { plugin::serverMsg($message); }
  }

  
  # Output data
  my $nPlayersWithRecs = teamplayers_processTeam(1, $showNoobs,(($args{'nicktype'}==1)?$args{'ircChannelCode'}:undef));
  $nPlayersWithRecs += teamplayers_processTeam(0, $showNoobs,(($args{'nicktype'}==1)?$args{'ircChannelCode'}:undef));
  
  
  # Check if nobody had any recs / noobs
  if ( $nPlayersWithRecs == 0 )
  {
    my $message = 'None of the players in the server have any '.(($showNoobs==1)?'n00bs':'recommendations');
    if ( $args{'nicktype'} == 1 )
      { plugin::ircmsg ( $message, $args{'ircChannelCode'} ); }
    else
      { plugin::serverMsg($message); }
  }
}

# Worker function for the !teamplayers command
sub teamplayers_processTeam
{
  my $teamid      = shift;
  my $showNoobs   = shift;
  my $ircChannel  = shift;
  my $string      = "";
  my $count       = 0;

  my %teamplayers = plugin::getPlayersByTeam($teamid);
  while ( my ( $id, $player ) = each ( %teamplayers ) )
  {
    my $recs = ( $showNoobs == 1 ) ? get_n00b($player->{'name'}) : get_recommendation($player->{'name'});
  
    $string .= "," if ($string ne "");
    $string .= " ".plugin::parseModName($player->{'name'}, $ircChannel);
    $string .= " (" . $recs . ")";

    if ( ++$count >= 5 )
    {
      players_outputTeam($teamid, $string);
      $count = 0;
      $string = "";
    }
  }
  
  players_outputTeam($teamid, $string) if ( $string ne "" );
}

# Worker function for the !teamplayers command
sub teamplayers_outputTeam
{
  my $teamid      = shift;
  my $string      = shift;
  my $showNoobs   = shift;
  my $ircChannel  = shift;
  
  if ( defined($ircChannel) )
  {
    $string = plugin::team_colourise($teamid, plugin::irc_bold(plugin::team_get_name($teamid).":").$string);
    plugin::ircmsg($string, $ircChannel);
  }
  else
  {
    plugin::servermsg(plugin::team_get_name($teamid).":".$string);
  }
}




# --------------------------------------------------------------------------------------------------
##
#### Data lookup & storage functions
##
# --------------------------------------------------------------------------------------------------

# Adds a recommentation record for a player
sub recommend_player
{
  my $name        = shift;        $name =~ s/'/''/g;
  my $recommender = shift;        $recommender =~ s/'/''/g;
  my $reason      = shift;        $reason =~ s/'/''/g;

  # Announce recommendation
  plugin::servermsg ( $name.' has been recommended by '.$recommender.' for: '.$reason );
  plugin::play_sound_for_player ( $name, 'bonus_complete.wav' );

  # Does a record exist for this player?
  my @recData = plugin::execute_query ( "SELECT * FROM recommendations WHERE LOWER(name) = '".lc($name)."'" );
  if ( scalar(@recData) > 0 )
    # Record exists, update it
    { plugin::execute_query ( "UPDATE recommendations SET recommendations = recommendations + 1 WHERE LOWER(name) = '".lc($name)."'", 1 ); }
  else
    # Record does not exist, insert as new record
    { plugin::execute_query ( "INSERT INTO recommendations ( name, recommendations ) VALUES ( '$name', 1 )", 1 ); }

  # Record the recommendation in the recent history
  plugin::execute_query ( "INSERT INTO recommendations_recent_history ( timestamp, recommender, recommendee, isN00b, reason ) VALUES ( ".time().", '$recommender', '$name', 0, '$reason' )" );
}

# Gets the current recommendation count for a player
sub get_recommendation
{
  my $name        = lc(shift);    $name =~ s/'/''/g;

  my @recData = plugin::execute_query ( "SELECT * FROM recommendations WHERE LOWER(name) = '$name'" );
  if ( scalar(@recData) > 0 )
    { return $recData[0]->{'recommendations'}; }
  return 0;
}

# Adds a n00b record for a player
sub n00b_player
{
  my $name        = shift;        $name =~ s/'/''/g;
  my $n00ber      = shift;        $n00ber =~ s/'/''/g;
  my $reason      = shift;        $reason =~ s/'/''/g;

  # Announce recommendation
  plugin::servermsg ( $name.' has been marked a n00b by '.$n00ber.' for: '.$reason );

  # Does a record exist for this player?
  my @recData = plugin::execute_query ( "SELECT * FROM recommendations WHERE LOWER(name) = '".lc($name)."'" );
  if ( scalar(@recData) > 0 )
    # Record exists, update it
    { plugin::execute_query ( "UPDATE recommendations SET n00bs = n00bs + 1 WHERE LOWER(name) = '".lc($name)."'", 1 ); }
  else
    # Record does not exist, insert as new record
    { plugin::execute_query ( "INSERT INTO recommendations ( name, n00bs ) VALUES ( '$name', 1 )", 1 ); }

  # Record the n00bing in the recent history
  plugin::execute_query ( "INSERT INTO recommendations_recent_history ( timestamp, recommender, recommendee, isN00b, reason ) VALUES ( ".time().", '$n00ber', '$name', 1, '$reason' )" );
}

# Gets the current recommendation count for a player
sub get_n00b
{
  my $name        = lc(shift);    $name =~ s/'/''/g;

  my @recData = plugin::execute_query ( "SELECT * FROM recommendations WHERE LOWER(name) = '$name'" );
  if ( scalar(@recData) > 0 )
    { return $recData[0]->{'n00bs'}; }
  return 0;
}

# Marks a player as rec ignored, so they cannot recieve or give recommendations
sub rec_ignore
{
  my $name        = lc(shift);    $name =~ s/'/''/g;
  plugin::execute_query( "INSERT IGNORE INTO recommendations_ignored_users (name) VALUES ( '$name' )", 1 );
}

# Checks if a specific player is marked as rec ignored
sub is_rec_ignored
{
  my $name        = lc(shift);    $name =~ s/'/''/g;

  my @array = plugin::execute_query( "SELECT * FROM recommendations_ignored_users WHERE LOWER(name) = '$name'" );
  return (scalar(@array) >= 1) ? 1 : 0;
}

# Unmarks a player as rec ignored, so they can give and recieve recommendations again
sub rec_allow
{
  my $name        = lc(shift);    $name =~ s/'/''/g;
  plugin::execute_query( "DELETE FROM recommendations_ignored_users WHERE LOWER(name) = '$name'", 1 );
}

# Checks whether recommender can recommend (or n00b if isN00b = 1) recommendee at this time.
#
# \param[in] $recommender
# \param[in] $recommendee
# \param[in] $isNoob
#   Is the recommender trying to mark the recommendee as a n00b?
#
# \return
#   1 if the recommender can recommend (or n00b) the recommendee, 0 if they have already recommended
#   (or n00bed) recomendee today or 2 if they have exceeded their daily recommendations quota
sub can_recommend
{
  my $recommender = lc(shift);    $recommender =~ s/'/''/g;
  my $recommendee = lc(shift);    $recommendee =~ s/'/''/g;
  my $isNoob      = shift;

  # Wipe records older than 1 week
  my $cutoff = time() - 604800;
  plugin::execute_query ( "DELETE FROM recommendations_recent_history WHERE timestamp < $cutoff", 1 );

  # We are only interested in activity in the last 24 hours
  $cutoff = time() - 86400;

  # Check to see if recommender has recommended (or n00bed) recommendee since the cutoff point
  my @result = plugin::execute_query ( "SELECT COUNT(*) AS count FROM recommendations_recent_history WHERE LOWER(recommender) = '$recommender' AND LOWER(recommendee) = '$recommendee' AND isN00b = $isNoob AND timestamp >= $cutoff" );
  if ( $result[0]->{'count'} > 0 ) { return 0; }

  # Check to see if recommender has exceeded their recommendations & n00bs quota
  @result = plugin::execute_query ( "SELECT COUNT(*) AS count FROM recommendations_recent_history WHERE LOWER(recommender) = '$recommender' AND timestamp >= $cutoff" );
  if ( $result[0]->{'count'} >= 5 ) { return 2; }

  # No problems found, OK to recommend / n00b
  return 1;
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

# Reads the recommendation based join message strings from the configuration file
sub read_recs
{
  open ( FILE, "<plugins/recommendations.cfg" ) or return;
  while ( <FILE> )
  {
    chomp $_;
    if ( $_ =~ /^\[(-?\d+);(-?\d+)\](.+)/ )
    {
      my $min = ( $1 < $2 ) ? $1 : $2;
      my $max = ( $1 < $2 ) ? $2 : $1;

      # Remove line breaks here instead of later on, and trim whitespace
      my $message = $3;
      $message =~ s/[\n\r]//g;
      chomp $message;

      my %hash = (
        'min' => $min,
        'max' => $max,
        'message' => $message
      );

      push (@joinmessages, \%hash);
    }
  }
  close ( FILE );
}

# Shows a formatted join message for a player based on their total recommendations
sub show_joinmessage
{
  my ( $result, %player ) = plugin::getPlayerData( $_[HEAP]->{'playername'} );
  if ( $result == 1 )
  {
    my $recommendations = get_recommendation($player->{'name'})-get_n00b($player->{'name'});
    
    if ( 0 == $recommendations )
    {
      plugin::servermsg ( $player->{'name'} .' does not have any recommendations yet' );
      return;
    }

    my $team = plugin::team_get_name($player->{'teamid'});
    my $otherteam = plugin::team_get_name(($player->{'teamid'}==0)?1:0);
    
    my $maxrecs = scalar(@joinmessages);
    my $line = "%nick has %rec recommendations.";

    # If loopCount goes above 25 bail out and use default setting
    srand();
    for ( $i = 0; $i < 25; $i++ )
    {
      my %hash = %{$joinmessages[int(rand($maxrecs))]};
      if ( ($recommendations >= $hash{'min'}) && ($recommendations <= $hash{'max'}) )
      {
        $line = $hash{'message'};
        last;
      }
    }
    
    # Format message
    $line =~ s/\%nick/$player->{'name'}/ig;
    $line =~ s/\%rec/$recommendations/ig;
    $line =~ s/\%team/$team/ig;
    $line =~ s/\%otherteam/$otherteam/ig;
    
    plugin::servermsg ( $line );
  }
}




# --------------------------------------------------------------------------------------------------
##
#### Database configuration
##
# --------------------------------------------------------------------------------------------------

sub db_update
{
  # Note: BRenBot will update the database all the way up to the format that was used up to 1.54.13
  #       automatically for us, so we don't need to worry about it being any older than that

  my $db_version = plugin::get_global ( "version_plugin_recommendations" );
  if ( defined($db_version) and $db_version > $currentVersion )
  {
    plugin::console_output("[Recommendations] The database has been modified by a newer version of"
        ." this plugin. To avoid potential data corruption the plugin will now stop");
    return 0;
  }

  # Current table definitions
  my %tables = (
    recommendations => "CREATE TABLE recommendations ( name TEXT PRIMARY KEY, recommendations INTEGER DEFAULT 0, n00bs INTEGER DEFAULT 0  )",
    recommendations_ignored_users => "CREATE TABLE recommendations_ignored_users ( name TEXT PRIMARY KEY )",
    recommendations_recent_history => "CREATE TABLE recommendations_recent_history ( timestamp INTEGER, recommender TEXT, recommendee TEXT, isN00b INTEGER, reason TEXT )"
  );

  # Check which tables already exist...
  my @db_tables = plugin::execute_query( "SELECT name FROM sqlite_master" );
  foreach ( @db_tables )
    { delete $tables{$_->{'name'}}; }

  # Create any missing tables
  while ( my($table,$definition) = each %tables )
  {
    plugin::console_output("[Recommendations] Creating missing table " . $table);
    plugin::execute_query( $definition, 1 );
    delete $tables{$table};
  }



  # Nothing to update at the moment...
  return 1;
}


# Plugin loaded OK
1;