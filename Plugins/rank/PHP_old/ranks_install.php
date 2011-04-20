<?php

include 'ranks_dbconfig.php';
$db = false;

/* Try to connect to the database using the settings provided */
if ( ( $db = mysql_connect( $dbhost, $dbuser, $dbpasswd ) ) == false )
	echo "Unable to connect to the database server...."; 
if ( mysql_select_db ( $dbname ) == false )
{
	$db = false;
	echo "Unable to connect to the database..";
}

if ( $db )
{
	mysql_query ( "CREATE TABLE IF NOT EXISTS `ranks_settings` (
	`update_interval` INT( 11 ) NOT NULL ,
	`last_update` INT( 11 ) NOT NULL
	)" );
	
	
	mysql_query ( "INSERT INTO `ranks_settings` ( `update_interval` , `last_update` )
	VALUES (
	'1200', '0'
	)" );
	
	
	mysql_query ( "CREATE TABLE IF NOT EXISTS `ranks` (
	`rank` INT NOT NULL ,
	`name` VARCHAR( 255 ) NOT NULL ,
	`kills` INT NOT NULL ,
	`deaths` INT NOT NULL ,
	`score` INT NOT NULL ,
	`mvp` INT NOT NULL ,
	`games` INT NOT NULL ,
	`gdi` INT NOT NULL ,
	`nod` INT NOT NULL
	)" );
	
	echo "Ranks tables created succesfully, please now delete ranks_install.php from your web server.";
}

?>