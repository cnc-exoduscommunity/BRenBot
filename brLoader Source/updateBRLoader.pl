#!/usr/bin/perl -w

# This simple utility application is downloaded along with updates to brLoader, to allow brLoader
# to update itself. Once it has served its purpose it should get deleted again.


use File::Copy;

# Copy brLoader.exe from the downloads folder to our folder
if ( $^O eq "MSWin32" )
{
	copy ( "download/brLoader/brLoader.exe", "brLoader.exe" );
}
else
{
	copy( "download/brLoader/brLoader", "brLoader" )
}

print "\n\nUpdated brLoader OK\n\n";

# Return to brLoader
exec ("brloader");