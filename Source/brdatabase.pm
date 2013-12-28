#!/usr/bin/perl

package brdatabase;
use strict;
use warnings;

use POE;
use modules;
use DBI;

our $dbh;		# Database handle

# Connects to the database
sub db_connect
{
	my $newDb = 1;
	if (-e "brenbot.dat" ) { $newDb = 0; }

	# Open database file
	$dbh = DBI->connect("dbi:SQLite:dbname=brenbot.dat","","");
	if (!$dbh)
	{
    modules::console_output ( "FATAL ERROR: Unable to establish database connection!\nShutting down..." );
    sleep(5);
    exit;
	}

	# Check all tables are present in the database
	check_tables();

	# If we created a new database set the version number.
	if ( $newDb )
	{
		modules::console_output ( "Database does not exist, creating new database..." );
		set_global ( 'version', main::BR_VERSION );
	 	set_global ( 'build', main::BR_BUILD );
	}

	# Otherwise check for any updates to process
	else
	{
		check_database();
	}

	return 0;
}


# Runs a database query
sub execute_query
{
	$| = 1;
	my $sth;
	my $query = shift;
	my $flag = shift;
	my @result = ();

	eval
	{
		#print "DEBUG: $query\n";
		$sth = $dbh->prepare ( "$query" );
		$sth -> execute;

		# If the flag is undef or 0 return the result of the query
		if (!$flag)
		{
			my $attrib_nr = 0;
			my @array_of_hash_refs;
			my @new_array;
			my $db_line;

		    while ($db_line = $sth->fetchrow_hashref())
		    {
		    	$array_of_hash_refs[$attrib_nr] = $db_line;
				$attrib_nr++;
			}

			foreach (@array_of_hash_refs)
			{
				my %hash = %$_;
				my %hash_lc;
				while ((my $k, my $v) = each %hash)
				{
					 $k = lc($k);
					 $hash_lc{$k} = $v;
				}
				push (@new_array,\%hash_lc);
			}

			# Clear the hash refs array by setting its length to -1
			$#array_of_hash_refs = -1;

			@result = @new_array;
		}
	};
	if ($@)
	{
		modules::display_error ( "Failed to execute query: $query\nError: $@", 'c' );
		modules::display_error ( "An error occured whilst executing a database query, see the console for more information.", 'i' );
		return();
	}
	return @result;
}


# Sets a global variable, useful for storing information which does
# not fit in any other tables but must not be lost at shutdown
#
# PARAM		String		Global Name
# PARAM		String		Global Value
sub set_global
{
	my $name = shift;						$name =~ s/'/''/g;
	my $value = shift;						$value =~ s/'/''/g;

	if ( defined ( get_global ( $name ) ) )
	{
		execute_query ( "UPDATE globals SET value='$value' WHERE name='$name'", 1 );
	}
	else
	{
		execute_query ( "INSERT INTO globals ( name, value ) VALUES ( '$name', '$value' )", 1 );
	}
	return undef;
}



# Retrieves a stored global variable from the database
#
# PARAM		String		Global Name
#
# RETURN ( $value )
# undef - Not found
# db value - Found
sub get_global
{
	my $name = shift;						$name =~ s/'/''/g;

	my @result = execute_query ( "SELECT value FROM globals WHERE name = '$name'" );

	if ( @result )
	{
		return ( $result[0]->{value} );
	}
	return undef;
}



# Write a record to the log's table. Mainly used for kicklog and banlog, but
# can be used for other things if nessicary
#
# PARAM		Int			Log Code ( 1 = banlog, 2 = kicklog )
# PARAM		String		Log Content
#
sub writeLog
{
	my $logCode = shift;
	my $logContent = shift;
	my $time = time;

	$logContent =~ s/'/''/g;
	execute_query ( "INSERT INTO logs ( logCode, log, timestamp ) VALUES ( $logCode, '$logContent', $time )", 1 );
}



# Searches for logs of any type matching a specified keyword.
#
# PARAM		String		Search String
#
sub findLogs
{
	my $searchString = shift;
	my $limit = shift;
	if ( !defined ( $limit ) ) { $limit = 8; }

	$searchString =~ s/"/""/g;
	return execute_query ( "SELECT * FROM logs WHERE log LIKE \"%$searchString%\" ORDER BY timestamp DESC LIMIT 0,$limit", 0 );
}



# Searches for logs of any type matching a specified keyword, of the specified type
#
# PARAM		String		Search String
# PARAM		Int			Search logCode
#
sub findLogs_Type
{
	my $searchString = shift;
	my $searchCode = shift;

	$searchString =~ s/"/""/g;
	return execute_query ( "SELECT * FROM logs WHERE log LIKE \"%$searchString%\" AND logCode = $searchCode ORDER BY timestamp DESC LIMIT 0,10", 0 );
}



# Dumps all logs of a specified type to a file
#
# PARAM		Int			Log Type ( 1 = banlog 2 = kicklog, )
# PARAM		String		Filename
#
sub dumpLogs
{
	my $logCode = shift;
	my $filename = shift;

	my @logs = execute_query ( "SELECT * FROM logs WHERE logCode = $logCode ORDER BY timestamp DESC", 0 );

	open ( LOGFILE, ">$filename" );

	foreach ( @logs )
	{
		my $timestamp = modules::get_past_date_time ( "[DD/MM/YY - hh:mm]", $_->{'timestamp'} );
		print LOGFILE "$timestamp $_->{log} \n";
	}

	close ( LOGFILE );
}



# Checks that all required tables are present in the database
sub check_tables
{
  my %required_tables =
  (
    globals    => "CREATE TABLE globals ( name TEXT PRIMARY KEY, value TEXT )",
    kicks      => "CREATE TABLE kicks ( id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, ip TEXT, serial TEXT, kicker TEXT, reason TEXT, timestamp INTEGER )",
    bans       => "CREATE TABLE bans ( id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, ip TEXT, serial TEXT, banner TEXT, reason TEXT, timestamp INTEGER )",
    logs       => "CREATE TABLE logs ( id INTEGER PRIMARY KEY AUTOINCREMENT, logCode INTEGER, log TEXT, timestamp INTEGER )",
    modules    => "CREATE TABLE modules ( name TEXT PRIMARY KEY, description TEXT, status INTEGER, locked INTEGER DEFAULT 0 )",
    auth_users => "CREATE TABLE auth_users ( id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, password TEXT )",
    plugins    => "CREATE TABLE plugins ( name TEXT PRIMARY KEY, bIsEnabled INTEGER )"
  );

	my @array = execute_query( "SELECT name FROM sqlite_master" );
	while ( ( my $k, my $v ) = each %required_tables )
	{
		my $found = 0;
		foreach ( @array )
		{
			if ( $_->{'name'} eq $k )
			{
				$found = 1;
			}
		}
		if ( $found == 0 )
		{
			execute_query( "$v", 1 );
		}

		delete $required_tables{$k};
	} # end of while
}





# Gets the current database version, checks it against the program version
# and runs any necessary updates.
sub check_database
{
	my $dbVersion = get_global( "version" );
	my $dbBuild = get_global( "build" );

	if ( !$dbVersion || !$dbBuild )
 	{
	 	# This should never happen on the new SQLite3 databases....
	 	modules::console_output ( "Database version data missing, your database could be corrupt...." );
 	}
  
  elsif ( $dbVersion > main::BR_VERSION || ($dbVersion == main::BR_VERSION && $dbBuild > main::BR_BUILD) )
  {
    modules::console_output("Database has been used with a newer version of BRenBot ($dbVersion build $dbBuild)\nAborting startup to prevent data corruption...");
    sleep(5);
    exit();
  }

 	elsif ( $dbVersion != main::BR_VERSION || $dbBuild != main::BR_BUILD )
 	{
	 	# Database is out of date, see if any updates need doing...
	 	modules::console_output ( "Database is out of date, updating to latest version..." );

    if ( $dbVersion < 1.53 || ($dbVersion == 1.53 && $dbBuild <= 11) )
    {
      print "      Deleting redundant module pingresponse...\n";
      execute_query ( "DELETE FROM modules WHERE name = 'pingresponse'", 1 );
    }

    if ( $dbVersion < 1.53 || ($dbVersion == 1.53 && $dbBuild <= 17) )
    {
      print "      Deleting redundant modules...\n";
      execute_query ( "DELETE FROM modules WHERE name = 'autorecs'", 1 );
      execute_query ( "DELETE FROM modules WHERE name = 'donate'", 1 );
      execute_query ( "DELETE FROM modules WHERE name = 'gameresults'", 1 );
      execute_query ( "DELETE FROM modules WHERE name = 'join_messages'", 1 );
      execute_query ( "DELETE FROM modules WHERE name = 'recommend'", 1 );
    }

    if ( $dbVersion < 1.53 || ($dbVersion == 1.53 && $dbBuild <= 18) )
    {
      print "      Deleting redundant modules...\n";
      execute_query ( "DELETE FROM modules WHERE name = 'bhs'", 1 );
    }

	 	# Finally set all the globals to the current version
	 	set_global ( 'version', main::BR_VERSION );
	 	set_global ( 'build', main::BR_BUILD );

	 	modules::console_output ( "Database update to ".main::BR_VERSION." (build ".main::BR_BUILD.") complete." );
 	}
}


return 1;