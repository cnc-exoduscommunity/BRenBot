#!/usr/bin/perl

use strict;
use warnings;

use LWP::Simple;
use LWP::UserAgent;
use Term::ReadKey;
use DBI;
use Digest::MD5;
use XML::Simple;
use XML::Parser;
use XML::Sax::PurePerl;
use Archive::Zip;
use File::Copy;
use File::Path;

my $brLoaderVersion = '1.42';
my $updateBRLoader = 0;
my $dbh;
$| = 1;		# Disable buffering on STDIN / STDOUT


print "BRenBot Loader $brLoaderVersion\n";


# Read config file
my $autoUpdate = 0;
my $autoUpdatePlugins = 0;
my $betaCode = 0;
my $autoLoadBrenbot = 0;
my $OSCode = ( $^O eq "MSWin32" ) ? "W" : "L";

if ( -e "brLoader.cfg" )
{
	open ( SETTINGS, "brLoader.cfg" );
	while ( <SETTINGS> )
	{
		if ( $_ !~ m/^\#/ && $_ !~ m/^\s+$/ )		# If the line starts with a hash or is blank ignore it
		{
			if ( $_ =~ m/^\s*autoUpdate\s*=\s*(\d+)/i )				{ $autoUpdate 			= $1; }
			if ( $_ =~ m/^\s*autoUpdatePlugins\s*=\s*(\d+)/i )		{ $autoUpdatePlugins	= $1; }
			if ( $_ =~ m/^\s*betaTesterCode\s*=\s*(.+)/i )			{ $betaCode				= $1; }
			if ( $_ =~ m/^\s*loadBrenbotOnFinish\s*=\s*(\d+)/i )	{ $autoLoadBrenbot		= $1; }
		}
	}
}


# Check for no database condition, run BRenBot if none found
if (!(-e "brenbot.dat" ))
{
	print "No database exists, BRenBot *must* run at least once before brLoader can be used.\n";
	if ( $autoLoadBrenbot == 1 )
	{
		print "\nLaunching BRenBot now.\n";
		exec ( "brenbot" );				# Launch BRenBot
	}
	else
	{
		exit();
	}
}


# Attempt to open BR database, trying sqlite3 first and falling back to SQLite2
# if necessary
$dbh = DBI->connect("dbi:SQLite:dbname=brenbot.dat","","",{RaiseError => 1});

# Check if this file reads OK as SQLite3
eval { $dbh->selectrow_array ( 'SELECT * FROM globals' ); };
if ( ($@ || !$dbh) && $^O eq "MSWin32" )
{
	print "Could not open database as SQLite3, attempting SQLite2...";
	eval
	{
		$dbh = DBI->connect("dbi:SQLite2:dbname=brenbot.dat","","",{RaiseError => 1});

		# Test database handle
		if ( $dbh ) { $dbh->selectrow_array ( 'SELECT * FROM globals' ); }
	};

	if ( $@ || !$dbh ) { print " Failed!"; undef $dbh; }
	else { print " Database opened OK"; }
	print "\n";
}

# Still no database? Guess it's got screwed up then, bail out!
if ( !$dbh )
{
	print "Unable to open BRenBot database, cannot check versions...\n";
	exit;
}
else
{
	# Check if brLoader has been updated, if it has remove temporary files
	my $brLoaderVersionDB = $dbh->selectrow_array ( "SELECT value FROM globals WHERE name='brLoader_version'" );
	if ( $brLoaderVersion != $brLoaderVersionDB )
	{
		my $query;
		if ( defined ( $brLoaderVersionDB ) )
			{ $query = $dbh->prepare ( "UPDATE globals SET value='$brLoaderVersion' WHERE name='brLoader_version'" ); }
		else
			{ $query = $dbh->prepare ( "INSERT INTO globals (name, value) VALUES ( 'brLoader_version', '$brLoaderVersion' )" ); };
		$query -> execute;

		updateConfig ( "download/brLoader/brLoader.cfg", "brLoader.cfg" );
		rmtree ( "download/brLoader/" );	# Delete temporary folder
	}
}


# Delete updateBRLoader if it exists - no longer needed
if ( $^O eq "MSWin32" && (-e "updateBRLoader.exe") ) { unlink ( "updateBRLoader.exe" ); }
elsif ( -e "updateBRLoader" ) { unlink ( "updateBRLoader" ); }

# Download versions data file
my $versionsData = get( "http://new.brenbot.com/brLoader/brLoaderQuery.php?OS=$OSCode&betaCode=$betaCode" );
if ( defined($versionsData) && $dbh )
{
	print "Downloaded latest version information OK\n";

	# Split versionsData into lines and process each line
	my @lines = split( /\n/, $versionsData );

	foreach my $line ( @lines )
	{
		$line =~ s/(\r|\n)//gi;		# Get rid of any line end characters

		if ( $line =~ m/BETA\sCODE\sOK/ ) { print "\nYour beta testers code has been accepted.\n\n"; next; }
		if ( $line =~ m/BETA\sCODE\sFAIL/ ) { print "\nYour beta testers code has been rejected, it is either invalid or has been revoked. You will only recieve public updates.\n\n"; next; }


		my ( $projectVersionID, $projectCode, $projectVersion, $filename, $filesize, $timestamp, $checksum ) = split( /\;/, $line );
		#print "Found download ($projectVersionID) $projectCode version $projectVersion, size $filesize, timestamp $timestamp, filename $filename, m5d: $checksum\n";

		if ( $projectCode eq "brLoader" && $projectVersion > $brLoaderVersion )
		{
			print "\n\nAn updated version of brLoader is available!\nVersion: $projectVersion\nSize: $filesize bytes\nWould you like to update now? Y/N: ";

			if ( $autoUpdate == 1 || confirmUpdate() == 1 )
			{
				if ( downloadFile ( $filename, $projectVersionID, $checksum ) )
				{
					# Extract zip contents and then delete zip file
					extractZipContents ( "download/".$filename, "download/brLoader/" );
					unlink ( "download/".$filename );

					# Set update flag - runs updateBRLoader.exe instead of brenbot.exe when done
					$updateBRLoader = 1;

					if ( $^O eq "MSWin32" )
						{ copy ( "download/brLoader/updateBRLoader.exe", "updateBRLoader.exe" ); }
					else
						{ copy ( "download/brLoader/updateBRLoader", "updateBRLoader" ); }
				}
			}
			else
			{
				print "\n\nUpdate process aborted. brLoader cannot download further updates until it is updated to the latest version.\n\n";
			}

			last;		# Do not process any more lines, brLoader must be updated
						# and restarted before allowing any other updates.
		}
		if ( $projectCode eq "brenbot" )
		{
			# Check BRenBot version
			my $dbVersion = $dbh->selectrow_array ( "SELECT value FROM globals WHERE name='version'" );
			if ( !$dbVersion ) { $dbVersion = '1.50'; }
			my $dbBuild = $dbh->selectrow_array ( "SELECT value FROM globals WHERE name='build'" );
			if ( !$dbBuild ) { $dbBuild = '1'; }

			# BRenBot versions may also have a build number, if so trim it out
			my $build = 0;
			if ( $projectVersion =~ m/(\d+\.\d+)\.(\d+)/i )
			{
				$projectVersion = $1;
				$build = $2;
			}

			if ( $dbVersion < $projectVersion || ( $dbVersion == $projectVersion && $dbBuild < $build ) )
			{
				print "\n\nAn updated version of BRenBot is available!\nVersion: $projectVersion (Build $build)\nSize: $filesize bytes\nWould you like to update now? Y/N: ";

				if ( $autoUpdate == 1 || confirmUpdate() == 1 )
				{
					if ( downloadFile ( $filename, $projectVersionID, $checksum ) )
					{
						if ( extractZipContents ( "download/".$filename, "download/brenbot/" ) )
						{
							# If there are BRLoader instructions follow them, otherwise use default actions
							if ( -e ( "download/brenbot/brloaderInstructions.cfg" ) )
								{ processBRLoaderInstructions ( "brenbot" ); }
							else
							{
								if ( $^O eq "MSWin32" )
									{ copy ( "download/brenbot/brenbot.exe", "brenbot.exe" ); }
								else
									{ copy ( "download/brenbot/brenbot", "brenbot" ); }
								updateXML ( "download/brenbot/commands.xml", "commands.xml", "commands" );
								if ( -e "download/brenbot/brenbot.cfg" ) { updateConfig( "download/brenbot/brenbot.cfg", "brenbot.cfg" ); }

								if ( !(-e "mapsettings.xml") ) { copy( "download/brenbot/mapsettings.xml", "mapsettings.xml" ); }
							}

							# Have we crossed the SQLite2 -> SQLite3 threshold? (1.53.4)
							if ( ( $projectVersion > 1.53 || ($projectVersion == 1.53 && $build >= 4 ) ) && ( $dbVersion < 1.53 || ( $dbVersion == 1.53 && $dbBuild < 4 ) ) )
							{
								print "This version of BRenBot requires an SQLite3 database, please wait while your database is converted from SQLite2...";

								# We must close our connection to the database so the converter can overwrite it
								$dbh->disconnect();

								system ( "tools/br_database_converter.exe" ) == 0 or die "Failed to load database conversion tool: $?\n\n\nWARNING;\n\nBRenBot will not be able to read your database, please manually update your database using the br_database_converter.exe tool";

								# Reconnect to database
								$dbh = DBI->connect("dbi:SQLite:dbname=brenbot.dat","","") or die "Cannot reconnect to database...";
							}

							print "Successfully updated BRenBot to version $projectVersion build $build\n";

							# Delete temporary files
							rmtree ( "download/brenbot/" );
							unlink ( "download/".$filename );
						}
						else { print "Failed to extract files from zip archive!\n"; }
					}
				}
			}
		}
		else
		{
			# Check plugin version, and that it is installed
			my $dbVersion = $dbh->selectrow_array ( "SELECT value FROM globals WHERE name='version_plugin_$projectCode'" );
			if ( !$dbVersion ) { $dbVersion = 0; }

			# Check it is STILL installed
			if ( $dbVersion && !( -e "plugins/$projectCode.pm" ) ) { $dbVersion = 0; }

			# Check if this is an update we need
			if ( $dbVersion != 0 && $dbVersion < $projectVersion )
			{
				print "\n\nAn updated version of the plugin $projectCode is available!\nVersion: $projectVersion\nSize: $filesize bytes\nWould you like to update now? Y/N: ";

				if ( $autoUpdatePlugins == 1 || confirmUpdate() == 1 )
				{
					if ( downloadFile ( $filename, $projectVersionID, $checksum ) )
					{
						if ( extractZipContents ( "download/".$filename, "download/$projectCode/" ) )
						{
							# If there are BRLoader Instructions follow them, otherwise use default actions
							if ( -e ( "download/$projectCode/brloaderInstructions.cfg" ) )
								{ processBRLoaderInstructions ( $projectCode ); }
							else
							{
								copy ( "download/$projectCode/$projectCode.pm", "plugins/$projectCode.pm" );
								updateXML ( "download/$projectCode/$projectCode.xml", "plugins/$projectCode.xml", "plugin" );
							}

							print "Successfully updated plugin $projectCode to version $projectVersion\n";

							# Delete temporary files
							rmtree ( "download/$projectCode/" );
							unlink ( "download/".$filename );
						}
						else { print "Failed to extract files from zip archive!\n"; }
					}
				}
			}
		}
	}
}
else
{
	print "Unable to download latest version information!\n";
}


# End of program execution
if ( $updateBRLoader == 1 )
{
	print "\nUpdating...\n";
	exec ( "updateBRLoader" );		# Launch updateBRLoader to update this updater
}
elsif ( $autoLoadBrenbot == 1 )
{
	print "\nLaunching BRenBot now.\n";
	exec ( "brenbot" );				# Launch BRenBot (update check complete)
}
exit 1;







# Waits for a Y / N response from the user when asked to confirm update
sub confirmUpdate
{
	while ( my $response = ReadKey(5) )
	{
		if ( defined ( $response ) )
		{
			print "$response";

			if ( $response =~ m/^Y/i ) { print "\n"; return 1; }
			elsif ( $response =~ m/^N/i ) { print "\n"; return 0; }
		}
	}

	print "\nResponse timed out, skipping update...\n";
	return 0;
}


# Downloads a file and checks its MD5 checksum
sub downloadFile
{
	my $filename			= shift;
	my $projectVersionID	= shift;
	my $checksum			= shift;

	# Print progress
	print "Downloading ".$filename.": 0b / ?b (0.00%)\r", ;

	# Always download to the download folder, create if it does not exist
	if ( !(-e "download" ) ) { mkdir ( "download" ); }

	# Delete the file if it already exists
	if ( -e "download/$filename" ) { unlink "download/$filename"; }

	open my $outfile, ">download/$filename" or die "Cannot create output file because: $!\n";
	binmode $outfile;
	$outfile->autoflush(1);

	# Generate URL string
	my $url = "http://new.brenbot.com/brLoader/brLoaderDownload.php?pv_id=$projectVersionID&betaCode=$betaCode";

	# Create LWP UserAgent
	my $ua = LWP::UserAgent->new( );

	# Request headers
	my $headerResponse = $ua->head($url);
	if ( !$headerResponse->is_success )
	{
		print "\nUnable to download update! Response;\n".$headerResponse->as_string."\nUpdate aborted!\n";
		return 0;
	}

	# Read filesize
	my $filesize = $headerResponse->headers->content_length;

	# Print progress
	print "Downloading ".$filename.": 0b / ".$filesize."b (0.00%)\r", ;

	# Download file
	my $downloaded = 0;
	$ua->get ( $url,
	":content_cb" => sub {		# Callback function
		my ($chunk, $response, $protocol) = @_;

		# Write data to file
		print {$outfile} $chunk;
		$downloaded += length $chunk;

		# Print progress
		printf "Downloading $filename: %sb / %sb (%.1f%%)\r", $downloaded, $filesize, ($downloaded/$filesize)*100;
	} );

	close $outfile;
	print "\n";

	open my $downloadedFile, "download/$filename" or die "Cannot open file to validate md5 checksum: $!";
	binmode $downloadedFile;
	my $file_checksum = Digest::MD5->new->addfile($downloadedFile)->hexdigest;
	close $downloadedFile;

	print "Verifying MD5 checksum.... ";
	if ( $checksum ne $file_checksum )
	{
		print "Failed, update aborted!\n";
		return 0;
	}
	else
	{
		print "OK\n";
		return 1;
	}

	return 0;
}


# Extracts the contents of a zip file to the specified folder
sub extractZipContents
{
	my $filename = shift;
	my $destination = shift;

	my $zip = Archive::Zip->new( $filename );
	if ( $zip->extractTree( '', $destination ) == 0 )
		{ return 1; }
	return 0;
}


# Updates an XML file based on a default XML file
sub updateXML
{
	my $xmlDefaultFile = shift;
	my $xmlFile = shift;
	my $rootname = shift;


	# Check both files exist
	if ( !(-e $xmlDefaultFile ) )
		{ print "Default XML data not found, skipping update of $xmlFile\n"; return; }

	if ( !(-e $xmlFile) )
		{ print "$xmlFile not found, using default settings.\n"; copy ( $xmlDefaultFile, $xmlFile ); return; }


	# Make backup
	copy ( $xmlFile, "backup/".$xmlFile );
	print "Updating $xmlFile...\n";

	my $xmlDefaultData;
	my $xmlData;

	# Fix xml entities in each file before trying to process them
	fixXMLEntities ( $xmlDefaultFile );
	fixXMLEntities ( $xmlFile );

	eval { $xmlDefaultData = XMLin( $xmlDefaultFile, ForceArray => [ qw(event group command hook) ] ); };
	if ($@) { print "  Error reading $xmlDefaultFile: $@"; return; }

	eval { $xmlData = XMLin( $xmlFile, ForceArray => [ qw(event group command hook) ] ); };
	if ($@) { print "  Error reading $xmlFile: $@"; return; }

	# For each command in the source file check it exists in the default file
	# If not remove it (redundant or removed command). Otherwise update it
	while ( my ( $command, $data ) = each %{$xmlData->{command}} )
	{
		if ( exists ( $xmlDefaultData->{command}->{$command} ) )
		{
			while ( my ( $k, $v ) = each %{$xmlDefaultData->{command}->{$command}} )
			{
				if ( !exists ( $xmlData->{command}->{$command}->{$k} ) )
				{
					print "  Adding missing data for command $command, key $k\n";
					$xmlData->{command}->{$command}->{$k} = $v;
				}
			}
		}
		else
		{
			print "  Deleting redundant command $command\n";
			delete $xmlData->{command}->{$command};
		}
	}


	# Now check each command in the default file and check it is in the source
	# file. If not copy it's data over
	while ( my ( $command, $data ) = each %{$xmlDefaultData->{command}} )
	{
		if ( !exists ( $xmlData->{command}->{$command} ) )
		{
			print "  Adding missing command $command\n";
			$xmlData->{command}->{$command} = $data;
		}
	}


	##################################
	# Plugin Specific Section
	##################################

	# Events - not user settable, simply copy over updated values
	if ( exists ( $xmlDefaultData->{'events'} ) )
	{
		print "  Updating events...\n";
		$xmlData->{'events'} = $xmlDefaultData->{'events'};
	}


	# Config settings
	if ( exists ( $xmlDefaultData->{'config'}->{'cvar'} ) )
	{			# Add missing config settings
		while ( my ( $setting, $value ) = each %{$xmlDefaultData->{'config'}->{'cvar'}} )
		{
			if ( !exists ( $xmlData->{'config'}->{'cvar'}->{$setting} ) )
				{ $xmlData->{'config'}->{'cvar'}->{$setting} = $value; }
		}

		# Remove redundant config settings
		while ( my ( $setting, $value ) = each %{$xmlData->{'config'}->{'cvar'}} )
		{
			if ( !exists ( $xmlDefaultData->{'config'}->{'cvar'}->{$setting} ) )
				{ delete $xmlData->{'config'}->{'cvar'}->{$setting}; }
		}

		# For each config setting reformat it so it comes out properly, otherwise
		# config options get royally fucked up
		my @cvarArray;
		my $arrayIndex = 0;
		while ( my ( $setting, $value ) = each %{$xmlData->{'config'}->{'cvar'}} )
		{
			$cvarArray[$arrayIndex] = {
				'name' => $setting,
				'value' => $value->{'value'}
			};
			$arrayIndex++;
		}

		$xmlData->{'config'}->{'cvar'} = \@cvarArray;
	}


	# Renlog regex hooks - not user settable, simply copy over updated values
	if ( exists ( $xmlDefaultData->{'renlog_regex_hooks'}->{'hook'} ) )
	{
		print "  Updating renlog hooks...\n";
		$xmlData->{'renlog_regex_hooks'}->{'hook'} = $xmlDefaultData->{'renlog_regex_hooks'}->{'hook'};
	}


	# Gamelog regex hooks - not user settable, simply copy over updated values
	if ( exists ( $xmlDefaultData->{'gamelog_regex_hooks'}->{'hook'} ) )
	{
		print "  Updating gamelog hooks...\n";
		$xmlData->{'gamelog_regex_hooks'}->{'hook'} = $xmlDefaultData->{'gamelog_regex_hooks'}->{'hook'};
	}


	# Now XML out the xmlData file
	XMLout( $xmlData, NoSort => 1, OutputFile => $xmlFile, RootName => $rootname, XMLDecl => 1 );
}


# Updates a brenbot.cfg style config file
sub updateConfig
{
	my $defaultConfigFile = shift;
	my $configFile = shift;

	# Check both files actually exist
	if ( !(-e $defaultConfigFile ) )
		{ print "Default config not found, skipping update of $configFile.\n"; return; }

	if ( !(-e $configFile ) )
		{ print "$configFile not found, using default settings.\n"; copy ( $defaultConfigFile, $configFile ); return; }


	# Make backup
	copy ( $configFile, "backup/".$configFile );
	print "Updating $configFile...\n";

	my %configSettings;
	my $newFile;

	# Read the existing settings from the current config
	open ( CONFIGFILE, $configFile );
	while ( <CONFIGFILE> )
	{
		if ( $_ =~ m/^(\S+)\s*=\s*(.*)$/i )
		{
			#print "$1 = $2\n";
			$configSettings{$1} = $2;

			# Settings that have been renamed need to be updated
			if ( $1 eq "IrcChannel" )
				{ $configSettings{"ircAdminChannel"} = $2; }

			elsif ( $1 eq "IrcChannelKey" )
				{ $configSettings{"ircAdminChannelKey"} = $2; }
		}
	}
	close CONFIGFILE;


	# Now read default config file, and substitute in our existing settings
	open ( DEFAULTCONFIG, $defaultConfigFile );
	while ( <DEFAULTCONFIG> )
	{
		if ( $_ =~ m/^(\S+)\s*=\s*(.*)$/i )
		{
			# If we have an existing value for this setting use that
			if ( exists ( $configSettings{$1} ) )
			{
				#print "changing value of $1 to $configSettings{$1}\n";
				$_ = "$1 = $configSettings{$1}\n";
			}
		}

		$newFile .= $_;
	}
	close DEFAULTCONFIG;


	# Print out the new config to the config file
	open ( CONFIGFILE, ">$configFile" );
	print CONFIGFILE $newFile;
	close CONFIGFILE;

}




# Function to scan an XML file for <, > and & in text tags and substitute it properly.
sub fixXMLEntities
{
	my $xmlFile = shift;
	my $newFile = "";

	open XMLFILE, $xmlFile;
	while ( <XMLFILE> )
	{
		if ( $_ =~ m/^(\s*\<\S+\s+\S+=\")(.+)(\"\/\>)$/i )
		{
			my $prefix = $1;
			my $value = $2;
			my $suffix = $3;

			$value =~ s/&(?!(gt;|lt;|apos;|quot;|amp;))/&amp;/g;
			$value =~ s/>/&gt;/g;
			$value =~ s/</&lt;/g;

			$newFile .= $prefix.$value.$suffix."\n";
		}
		else
		{
			$newFile .= $_;
		}
	}
	close XMLFILE;

	open XMLFILE,, '>'.$xmlFile;
	print XMLFILE $newFile;
	close XMLFILE;
}




# Reads a brloaderInstructions.cfg file and executes the instructions inside it
sub processBRLoaderInstructions
{
	my $download = shift;

	open ( BRLOADERINSTRUCTIONS, "download/$download/brloaderInstructions.cfg" );
	while ( <BRLOADERINSTRUCTIONS> )
	{
		if ( $_ !~ m/^\#/ && $_ !~ m/^\s+$/ )		# If the line starts with a hash or is blank ignore it
		{
			if ( $_ =~ m/^COPY\s+([^:]+)\s+\:(.+)$/ )
			{
				# If the destination contains a file path make sure the folder(s) exist
				createPathIfNotExists ( $2 );
				copy ( "download/$download/$1", $2 );
			}

			if ( $_ =~ m/^COPYIFNOTEXISTS\s+([^:]+)\s+\:(.+)$/ )
			{
				if ( !(-e $2 ) )
				{
					createPathIfNotExists ( $2 );
					copy ( "download/$download/$1", $2 );
				}
			}

			elsif ( $_ =~ m/^MOVE\s+([^:]+)\s+\:(.+)$/ )
			{
				if ( -e $1 )
				{
					createPathIfNotExists ( $2 );
					copy ( $1, $2 );
					unlink ( $1 );
				}
			}

			elsif ( $_ =~ m/^DELETE\s+(.+)$/ )
				{ unlink ( $1 ); }

			elsif ( $_ =~ m/^UPDATECFG\s+([^:]+)\s+\:(.+)$/ )
				{ updateConfig( "download/$download/$1", $2 ); }

			elsif ( $_ =~ m/^UPDATEXML\s+([^:]+)\s+\:([^:]+)\s+:(.+)$/ )
				{ updateXML ( "download/$download/$1", $2, $3 ); }
		}
	}
	close BRLOADERINSTRUCTIONS;
}


# Creates the path to a filename if it does not exist
sub createPathIfNotExists
{
	my $path = shift;
	my $tempPath = "";

	while ( $path =~ m/([^\/\\]+)(\\|\/)(.+)/ )
	{
		# Check tempPath/$1 exists
		if ( !(-e "$tempPath$1" ) )
			{ mkdir ( "$tempPath$1" ); }

		# Update tempPath
		$tempPath = ($tempPath) ? "$tempPath/$2/" : "$1/";

		# Trim path to the remaining path
		$path = $3;
	}
}