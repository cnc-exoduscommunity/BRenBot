# brTeams.pm
#
# This module is dedicated to storing the settings for team names and colours and providing quick
# methods for formatting text with this information

package brTeams;
use brIRC;

# --------------------------------------------------------------------------------------------------

# Create the data array with default values for use in Renegade
our %teams = (
  0 => {
    'name'          => "Nod",
    'abbreviation'  => "Nod",
    'colour'        => "04"
  },
  1 => {
    'name'          => "GDI",
    'abbreviation'  => "GDI",
    'colour'        => "08,15"
  },
  2 => {
    'name'          => "Neutral",
    'abbreviation'  => "Neutral",
    'colour'        => "09"
  }
);

# --------------------------------------------------------------------------------------------------

# Reads the team configuration file if it exists
sub read_config
{
  my $teamid = undef;

  eval
  {
    open ( TEAMCONFIG, "teams.cfg" );
    while ( <TEAMCONFIG> )
    {
      chomp;  # Kill any \n's

      if ( $_ !~ m/^\#/ && $_ !~ m/^\s+$/ )   # If the line starts with a hash or is blank ignore it
      {
        if ( $_ =~ m/\[TEAM(\-?\d+)\]/i )
        {
          $teamid = int($1);
        }
        elsif ( defined $teamid )
        {
          if ( $_ =~ m/^name\s*=\s*(\S.*)$/i )
          {
            $teams{$teamid}->{'name'} = $1;
          }
          elsif ( $_ =~ m/^abbreviation\s*=\s*(\S.*)$/i )
          {
            $teams{$teamid}->{'abbreviation'} = $1;
          }
          elsif ( $_ =~ m/^colour\s*=\s*(\d{1,2}(?:,\d{1,2})?)$/i )
          {
            $teams{$teamid}->{'colour'} = $1;
          }
        }
      }
    }
    close ( TEAMCONFIG );
  }
}

# --------------------------------------------------------------------------------------------------

# Get the ID for a team given it's name or abbreviation
sub get_id_from_name
{
  my $team = shift;
  
  # Can't do anything useful with an undefined value...
  return undef if !defined $team;

  # If $team is numeric then it is already an ID so return it
  return int($team) if ( $team =~ m/^\d+$/ and $team >= 0 and $team <= 2 );

  # Otherwise search for a matching team by name or abbreviation
  $team = lc($team);
  for my $id (keys %teams)
  {
    return int($id) if ( lc($teams{$id}->{'name'}) eq $team || lc($teams{$id}->{'abbreviation'}) eq $team );
  }

  return undef;
}

# --------------------------------------------------------------------------------------------------

# Get the full name for a team
sub get_name
{
  my $team = get_id_from_name(shift);

  if ( defined $team )
    { return $teams{$team}->{'name'}; }
  else
    { return "Unknown"; }
}

# Get the abbreviated name for a team
sub get_abbreviation
{
  my $team = get_id_from_name(shift);

  if ( defined $team )
    { return $teams{$team}->{'abbreviation'}; }
  else
    { return "Unk"; }
}

# Get the IRC colour for this team
sub get_colour
{
  my $team = get_id_from_name(shift);

  if ( defined $team )
    { return $teams{$team}->{'colour'}; }
  else
    { return "01"; }
}

# --------------------------------------------------------------------------------------------------

# Colourise a string with the specified team colour
sub colourise
{
  my $colour  = get_colour(shift);
  my $message = shift;

  return brIRC::colourise($colour, $message);
}

# Get the name of the specified team in a colourised string
sub get_colourised_name
{
  my $team = shift;
  return colourise($team, get_name($team));
}

# Format a string with the specified team colour
sub get_colourised_abbreviation
{
  my $team = shift;
  return colourise($team, get_abbreviation($team));
}