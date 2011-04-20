<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">


<?php

/* NB: If you use a phpBB forum, you can change the line below to point to config.php
in your forum folder, as the variable names are the same. Otherwise ensure you have the
correct settings in ranks_dbconfig.php */
require_once 'ranks_dbconfig.php';

/* Startup the templates control system */
require_once 'templates.php';
$templates = new templates();

/* Handle newer PHP versions */
if ( !isset ( $HTTP_POST_VARS ) )
{
	$HTTP_POST_VARS = $_POST;
	$HTTP_GET_VARS = $_GET;
}


/* Set some default variables */
$db = false;
$updated = false;
$updateError = false;
$dbError = false;
$criticalError = false;

/* If the database host is not -1 then try to connect to the database */
if ( $dbhost != -1 )
{
	/* Try to connect to the database using the settings provided */
	if ( ( $db = mysql_connect( $dbhost, $dbuser, $dbpasswd ) ) == FALSE )
		$dbError = "Unable to connect to the database server, searching and sorting functions will be disabled."; 
	if ( mysql_select_db ( $dbname ) == false )
	{
		$db = false;
		$dbError = "Unable to connect to the database, searching and sorting functions will be disabled.";
	}
	
	
	if ( $db )
	{
		/* Try to get settings for the plugin */
		$settingsQuery = mysql_query ( "SELECT * FROM ranks_settings" );
		
		if ( mysql_num_rows ( $settingsQuery ) == 0 )
			$dbError = "No settings present in the database, please ensure you have setup the database using ranks_install.php";
		else
		{
			$settings = mysql_fetch_assoc ( $settingsQuery );
			
			/* Throw a couple of variables into the template for showing when the next
			update is due, and how long since the last update. */
			$templates->assignVars ( array (
				'lastUpdate' => number_format ( ( time() - $settings['last_update'] ) /60, 2 ),
				'nextUpdate' => ( ( $settings['update_interval'] /60 ) - ( number_format ( ( time() - $settings['last_update'] ) /60, 2 ) ) ),
				'updateInterval' => ( $settings['update_interval'] /60 ),
				'searchName' => $HTTP_POST_VARS['search_name']
			) );
			
			/* Check if it is time to get new data from the ranks.txt file yet */
			if ( ( time() - $settings['last_update'] ) > $settings['update_interval'] )
			{
				$updated = true;
				
				/* Try to read ranks.txt */
				$oldErrorLevel = error_reporting (0);
				if ( !$ranksTXT = file_get_contents ( "ranks.txt" ) )
					$updateError = true;
				else
				{
					/* We have data from ranks.txt, proceed to clean old ranks out of
					the database, and put new ones in */
					mysql_query ( "TRUNCATE TABLE ranks" );
					
					/* First split the data from ranks.txt into an array of players */
					$playersArray = explode ( "\n", $ranksTXT );
					
					/* Now for each player in the array, split it into the seperate
					details and put it into the database */
					for ( $pos = 0; $pos < sizeof ( $playersArray ); $pos++ )
					{
						$playersArray[$pos] = explode ( "\t", $playersArray[$pos] );
						
						if ( !mysql_query ( "INSERT INTO ranks ( rank, name, kills, deaths, score, mvp, games, gdi, nod ) VALUES ( " . trim ( $playersArray[$pos][0] ) . ", '" . str_replace ( "'", "\'", trim ( $playersArray[$pos][1] ) ) . "', " . trim ( $playersArray[$pos][2] ) . ", " . trim ( $playersArray[$pos][3] ) . ", " . trim ( $playersArray[$pos][4] ) . ", " . trim ( $playersArray[$pos][5] ) . ", " . trim ( $playersArray[$pos][6] ) . ", " . trim ( $playersArray[$pos][7] ) . ", " . trim ( $playersArray[$pos][8] ) . ")" ) )
							$criticalError = "<b>An error occured while updating the database!</b><br><i>" . mysql_error() . "</i>";
					}
					
					mysql_query ( "UPDATE ranks_settings SET last_update = " . time() );
				}
				error_reporting ($oldErrorLevel);
			}
			
			// Sort out the WHERE and ORDER_BY settings
			$ORDER_BY = ( isset ( $HTTP_POST_VARS['orderBy'] ) ) ? $HTTP_POST_VARS['orderBy'] : 'score DESC';
			$NAME = ( isset ( $HTTP_POST_VARS['search_name'] ) && strlen ( $HTTP_POST_VARS['search_name'] ) > 0 ) ? "AND name LIKE '%" . $HTTP_POST_VARS['search_name'] . "%'" : "";
			$GAMES = ( isset ( $HTTP_POST_VARS['gamesPlayed'] ) ) ? $HTTP_POST_VARS['gamesPlayed'] : '0';
			
			/* Get all the playerData from the database and start putting it into
			the template. */
			$ranksQuery = mysql_query ( "SELECT *, (kills/deaths) AS kd, (score/games) AS spg, (kills/games) AS kpg, (deaths/games) AS dpg FROM ranks WHERE games >= $GAMES $NAME ORDER BY  $ORDER_BY" );
			
			if ( mysql_num_rows ( $ranksQuery ) == 0 )
				$player = false;
			else
			{
				while ( $player = mysql_fetch_assoc ( $ranksQuery ) )
				{
					$templates->assignVars ( array (
						'rank' => $player['rank'],
						'player' => $player['name'],
						'kills' => $player['kills'],
						'deaths' => $player['deaths'],
						'score' => $player['score'],
						'mvp' => $player['mvp'],
						'games' => $player['games'],
						'gdi' => $player['gdi'],
						'nod' => $player['nod'],
						'kd' => number_format ( $player['kd'], 2, '.', '' ),
						'spg' => number_format ( $player['spg'], 2, '.', '' ),
						'kpg' => number_format ( $player['kpg'], 2, '.', '' ),
						'dpg' => number_format ( $player['dpg'], 2, '.', '' ),
					), 'players' );
				}
				$player = true;
			}
		}
	
		/* Output various template bits for the sorting and searching form */
		$sortOptions = array (
			'score DESC' => 'Score (default)',
			'name ASC' => 'Alphabetically',
			'(kills/deaths) DESC' => 'Kills / Deaths Ratio',
			'mvp DESC' => 'MVP Awards',
			'kills DESC' => 'Kills',
			'deaths DESC' => 'Deaths',
			'(score/games) DESC' => 'Score per game',
			'(kills/games) DESC' => 'Kills per game',
			'(deaths/games) DESC' => 'Deaths per game'
		);
		
		foreach ( $sortOptions as $ordering => $name )
		{
			$selected = ( $ordering == $ORDER_BY ) ? 'selected' : '';
			
			$templates->assignVars ( array (
				'value' => $ordering,
				'name' => $name,
				'selected' => $selected
			), 'sort_options' );
		}
		
		$gamesPlayedOptions = array ( '0', '1', '2', '3', '4', '5', '10', '20' );
		foreach ( $gamesPlayedOptions as $value )
		{
			$selected = ( $value == $GAMES ) ? 'selected' : '';
			
			$templates->assignVars ( array (
				'value' => $value,
				'selected' => $selected
			), 'games_options' );
		}
	}
}
	
	
if ( $db === false )
{
	$oldErrorLevel = error_reporting (0);
	/* We are not using the database, so process data straight from the file */
	if ( !$ranksTXT = file_get_contents ( "ranks.txt" ) )
		$criticalError = "<b>Unable to open ranks.txt</b>";
	else
	{
		/* First split the data from ranks.txt into an array of players */
		$playersArray = explode ( "\n", $ranksTXT );
		
		$player = false;
		/* Now for each player in the array, split it into the seperate details
		and put it into the database */
		for ( $pos = 0; $pos < sizeof ( $playersArray ); $pos++ )
		{
			$player = explode ( "\t", $playersArray[$pos] );
			
			$templates->assignVars ( array (
				'rank' => $player[0],
				'player' => $player[1],
				'kills' => $player[2],
				'deaths' => $player[3],
				'score' => $player[4],
				'mvp' => $player[5],
				'games' => $player[6],
				'gdi' => $player[7],
				'nod' => $player[8],
				'kd' => number_format( ( $player[2] / $player[3] ), 2, '.', '' ),
				'spg' => number_format( ( $player[4] / $player[6] ), 2, '.', '' ),
				'kpg' => number_format( ( $player[2] / $player[6] ), 2, '.', '' ),
				'dpg' => number_format( ( $player[3] / $player[6] ), 2, '.', '' )
			), 'players' );
		}
		
		mysql_query ( "UPDATE ranks_settings SET last_update = " . time() );
	}
	error_reporting ($oldErrorLevel);
}
	
/* Now we should have all the data we need to output the template. */
if ( $criticalError ) echo $critialError;
else
{
	if ( $dbError ) echo $dbError;
	$templates->parseTemplate ( ranks );
	
	echo "<br>
	<br>
	<center><font size='2'><i>Rankings system created by danpaul88</i></font></center>";
}

?>