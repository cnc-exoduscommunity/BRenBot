# FDS code package for BRenBot
#
# This contains functionality for sending various different commands to the FDS via RenRem and
# handles fallback actions when a command isn't supported

package fds;
use strict;

use POE;

use brconfig;
use brTeams;
use playerData;
use RenRem;

# --------------------------------------------------------------------------------------------------

# Transmits commands to the FDS via an appropriate method
sub send_command($;$)
{
  my $command = shift;
  my $delay = shift // 0;

  if ( $delay > 0 )
  {
    POE::Session->create(inline_states =>
    {
      _start => sub { $_[KERNEL]->alarm( 'tick' => (time()+$delay) ); },
      tick => sub { send_command($command); },
    });
    return;
  }

  # Currently only RenRem is supported
  RenRem::RenRemCMD($command);

  # Should probably add support for transmitting the commands via the SSGM 4+ TCP connection...
}



# --------------------------------------------------------------------------------------------------
##
#### Sound Commands
##
# --------------------------------------------------------------------------------------------------

# Play a sound file for all players in the server
sub play_sound($)
{
  my $filename = shift;

  return 0 if ( $brconfig::serverScriptsVersion < 1.9 );

  send_command("snda $filename");
  return 1;
}

# Play a sound file for a specific player
sub play_sound_player($$)
{
  my $filename  = shift;
  my $player    = shift;

  my ($result, %playerdata) = playerData::getPlayerData($player);
  return 0 if ( $result != 1 || $playerdata{'scriptsVersion'} < 1.9 || $brconfig::serverScriptsVersion < 1.9 );

  send_command("sndp $playerdata{id} $filename");
  return 1;
}

# Play a sound file for each player on a team
sub play_sound_team($$)
{
  my $filename  = shift;
  my $team      = shift;

  return 0 if ( $brconfig::serverScriptsVersion < 1.9 );

  my $teamid = brTeams::get_id_from_name($team);

  send_command("sndt $teamid $filename");
  return 1;
}




# --------------------------------------------------------------------------------------------------
##
#### Messaging Commands
##
# --------------------------------------------------------------------------------------------------

# Displays a message to all players in the server
sub send_message($;$)
{
  my ($message,$sender) = (@_);

  $message = '('.$sender."): $message" if ( defined($sender) );
  send_command("msg $message");
  return 1;
}

# Displays a popup admin message to all players in the server
sub send_admin_message($;$)
{
  my ($message,$sender) = (@_);

  $message = '('.$sender."): $message" if ( defined($sender) );
  send_command("admin_message $message");
  return 1;
}

# Displays a message to a specific player
sub send_message_player($$;$)
{
  my ($message,$player,$sender) = (@_);

  my ($result, %playerdata) = playerData::getPlayerData($player);
  return 0 if ( $result != 1 );

  # If cmsg paging is enabled then try using that first
  return 1 if ($brconfig::enableCmsgPaging && send_coloured_message_player(0,255,0,$message,$playerdata{'id'},$sender));

  # CMSG paging not enabled or not supported so fall back on older methods
  $message = '('.$sender."): $message" if (defined($sender));

  if ($brconfig::serverScriptsVersion >= 1.3)
    { send_command("ppage $playerdata{id} $message"); }
  else
    { send_command("page $playerdata{name} $message"); }

  return 1;
}

# Displays a coloured message to all players in the server
sub send_coloured_message($$$$;$)
{
  my ($r,$g,$b,$message,$sender) = (@_);

  return 0 if ($brconfig::serverScriptsVersion < 2.6);

  $message = '('.$sender."): $message" if ( defined($sender) );
  send_command("cmsg $r,$g,$b $message");
  return 1;
}

# Displays a coloured message to a specific player
sub send_coloured_message_player($$$$$;$)
{
  my ($r,$g,$b,$message,$player,$sender) = (@_);

  my ($result, %playerdata) = playerData::getPlayerData($player);
  return 0 if ( $result != 1 || $playerdata{'scriptsVersion'} < 2.6 || $brconfig::serverScriptsVersion < 2.6 );

  $message = '('.$sender."): $message" if ( defined($sender) );
  send_command("cmsgp $playerdata{id} $r,$g,$b $message");
  play_sound_player('yo1.wav', $playerdata{'id'});
  return 1;
}

# Displays a coloured message to each player on a team
sub send_coloured_message_team($$$$$;$)
{
  my ($r,$g,$b,$message,$team,$sender) = (@_);

  return 0 if ( $brconfig::serverScriptsVersion < 2.6 );

  my $teamid = brTeams::get_id_from_name($team);
  $message = '('.$sender."): $message" if ( defined($sender) );

  send_command("cmsgt $teamid $r,$g,$b $message");
  play_sound_team('yo1.wav', $teamid);
}

1;