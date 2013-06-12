# brTeams.pm
#
# This module is dedicated to storing the settings for team names and colours and providing quick
# methods for formatting text with this information

# --------------------------------------------------------------------------------------------------

# Create the data array with default values for use in Renegade
our %teams = {
  0 => {
    'name'          => "Nod",
    'abbreviation'  => "Nod",
    'colour'        => "04,00"
  }
  1 => {
    'name'          => "GDI",
    'abbreviation'  => "GDI",
    'colour'        => "08,15"
  }
  2 => {
    'name'          => "Neutral",
    'abbreviation'  => "Neutral",
    'colour'        => "09,00"
  }
};

# --------------------------------------------------------------------------------------------------

# Get the ID for a team given it's name or abbreviation
sub get_id_from_name
{
  my $team = lc(shift);
  
  if ( $team !~ m/^\d+$/ )
  {
    while ( my ( $id, $data ) = each %teams )
    {
      return $id if ( lc($data{'name'}) eq $team || lc($data{'abbreviation'}) eq $team );
    }
  }
  
  return -1;
}

# --------------------------------------------------------------------------------------------------

# Get the full name for a team
sub get_name
{
  my $team = get_id_from_name(shift);
  
  if ( $team != -1 )
    { return $teams{$team}{'name'}; }
  else
    { return "Unknown"; }
}

# Get the abbreviated name for a team
sub get_abbreviation
{
  my $team = get_id_from_name(shift);
  
  if ( $team != -1 )
    { return $teams{$team}{'abbreviation'}; }
  else
    { return "Unk"; }
}

# Get the IRC colour for this team
sub get_colour
{
  my $team = get_id_from_name(shift);
  
  if ( $team > 0 and $team <= 2 )
    { return $teams{$team}{'colour'}; }
  else
    { return "01"; }
}

# --------------------------------------------------------------------------------------------------

# Colourise a string with the specified team colour
sub colourise
{
  my $colour  = get_colour(shift);
  my $message = shift;
  
  return "$colour$message";
}

# Get the name of the specified team in a colourised string
sub get_colourised_name
{
  return colourise(get_name(shift));
}

# Format a string with the specified team colour
sub get_colourised_abbreviation
{
  return colourise(get_name(shift));
}