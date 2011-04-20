#
# CUSTOM COMMANDS PLUGIN for BRenBot 1.43 by Daniel Paul
# Version 1.11
#
package custom_commands;

use POE;
use plugin;
use strict;

sub CHANNEL () { plugin::get_irc_channel() };

# define additional events in the POE session

our %additional_events =
(
	# !commands
	"show_commands" => "show_commands",
);

# plugin_name and config are automatically given data by BRenBot
our $plugin_name;
our %config;
our %type1Commands;				# Holds a list of type 1 commands, and the ID for their text
our %type2Commands;				# Holds a list of type 2 commands, and the ID for their text
our %type3Commands;				# Holds a list of type 3 commands, and the ID for their text
our %commandsText;				# Holds the actual text for the commands
my $pluginVersion = 1.11;



########### Functions for !commands

# Function for !show_commands command - Shows available custom commands
sub show_commands
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};
	
	my $key;
	my $commandsList = "Available Commands: ";
	
	foreach $key ( keys ( %type1Commands ) )
	{
		$commandsList .= $key . ", ";
	}
	foreach $key ( keys ( %type2Commands ) )
	{
		$commandsList .= $key . ", ";
	}
	foreach $key ( keys ( %type3Commands ) )
	{
		$commandsList .= $key . ", ";
	}
	
	if ( $commandsList ne "Available Commands: " )
	{
		# Trim trailing ", "
		$commandsList = substr ( $commandsList, 0, -2 );
	}
	else
	{ $commandsList = "There are no custom commands setup at this time."; }
	
	if ( $args{nicktype} == 1 )
	{ $kernel->post ( IRC => privmsg => CHANNEL, "[BR] " . $commandsList ); }
	else
	{ plugin::RenRemCMD ( "msg [BR] " . $commandsList ); }
}



########### Event handlers

# Runs when BRenBot loads the plugin
sub start
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	
	# Set our current version in the globals table
	plugin::set_global ( "version_plugin_custom_commands", $pluginVersion );
	
	# Load commands list
	loadCommands();
}

# Runs when BRenBot shuts down
sub stop
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
}

# Runs when a !command specified in the .xml file is typed
sub command
{
	# trigger on !commands
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};
	
	if ( $args{command} eq "show_commands" )
	{ $kernel->yield("show_commands" => \%args); }
}

# Runs when any text is typed ingame or in IRC
sub text
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};
	
	if ( $args{message} =~ m/^\!(\S+)(\s(.+))?/i )
	{
		my $command = lc ($1);
		my $argsparam = $3;
		
		# Check type 1 commands
		if ( $type1Commands{$command} )
		{
			#print $commandsText{$type1Commands{$command}};
			my $message = $commandsText{$type1Commands{$command}};
			$message =~ s/\%(name|nick)/$args{nick}/gi;
			$message =~ s/\%args/$argsparam/gi;
			
			plugin::RenRemCMD( "msg [BR] " . $message );
		}
		
		# Check type 2 commands
		if ( $type2Commands{$command} )
		{
			if ( $args{nicktype} == 0 )
			{
				#print $commandsText{$type2Commands{$command}};
				my $message = $commandsText{$type2Commands{$command}};
				$message =~ s/\%(name|nick)/$args{nick}/gi;
				$message =~ s/\%team/$args{team}/gi;
				my $otherteam = ( $args{team} eq "GDI" ) ? "Nod" : "GDI";
				$message =~ s/\%enemyteam/$otherteam/gi;
				$message =~ s/\%args/$argsparam/gi;
				
				plugin::RenRemCMD( "msg [BR] " . $message );
			}
			else
			{ $kernel->post ( IRC => privmsg => CHANNEL, "[BR] The command $command cannot be used from IRC." ); }
		}
		
		# Check type 3 commands
		if ( $type3Commands{$command} )
		{
			if ( $args{nicktype} == 0 )
			{
				#print $commandsText{$type3Commands{$command}};
				my $message = $commandsText{$type3Commands{$command}};
				$message =~ s/\%(name|nick)/$args{nick}/gi;
				$message =~ s/\%team/$args{team}/gi;
				my $otherteam = ( $args{team} eq "GDI" ) ? "Nod" : "GDI";
				$message =~ s/\%enemyteam/$otherteam/gi;
				$message =~ s/\%args/$argsparam/gi;
				
				plugin::RenRemCMD( "page $args{nick} [BR] " . $message );
			}
			else
			{ $kernel->post ( IRC => privmsg => CHANNEL, "[BR] The command $command cannot be used from IRC." ); }
		}
	}
}



########### Other Functions

# Reads the commands from the commands.xml file
sub loadCommands
{
	my $currentSection = 0;
	my $currentTextID = 0;
	
	eval
	{
		open ( COMMANDSFILE, 'plugins/custom_commands.brf' );
		while ( <COMMANDSFILE> )
		{
			if ( $_ !~ m/^\#/ && $_ !~ m/^\s+$/ )		# If the line starts with a hash or is blank ignore it
			{
				if ( $_ =~ m/\[(|TYPE1|TYPE2|TYPE3)\]/i )
				{
					$currentSection = uc($1);
				}
				elsif ( $currentSection )
				{
					if ( $_ =~ m/([^=]+)\s?=\s?(.+)/i )
					{
						# Put the command text into the commandsTest hash
						$currentTextID++;
						$commandsText{$currentTextID} = $2;
						
						# Now put all of the commands into the right hash
						foreach ( split(/,/, $1) )
						{
							my $command = lc($_);
							$command =~ s/\s//g;	# Trim spaces from the command
							
							if ( $currentSection eq "TYPE1" ) { $type1Commands{$command} = $currentTextID; }
							elsif ( $currentSection eq "TYPE2" ) { $type2Commands{$command} = $currentTextID; }
							elsif ( $currentSection eq "TYPE3" ) { $type3Commands{$command} = $currentTextID; }
						}
					}
				}
			}
		}
		close ( COMMANDSFILE );
	}
	or modules::display_error($@);
}

1;
