#**
# FDS Status Reporter plugin
# Reports the status of the FDS to an FTP location automatically by uploading a .txt file.
# Processing the raw data is up to the website
#
# \author Daniel Paul (danpaul88@yahoo.co.uk)
# \version 1.06
#*

package fds_status_reporter;

use POE;
use plugin;
use Net::FTP;

my $currentVersion = '1.06';
my $loaded_ok = undef;

# Check bot compatibility
if ( !defined(plugin::getBrVersion) || plugin::getBrVersion() < 1.54
  || (plugin::getBrVersion() == 1.54 && plugin::getBrBuild() < 1 ) )
{
  print ' == FDS Status Reporter Plugin Error ==\n'
      . 'This version of the plugin is not compatible with BRenBot versions older than 1.54.1\n';
  return 0;
}

# --------------------------------------------------------------------------------------------------

# BRenBot supplies these on plugin startup
our $plugin_name;
our %config;

# Define additional events in the POE session
our %additional_events =
(
  'updateStatus' => 'updateStatus'
);




# --------------------------------------------------------------------------------------------------
##
#### Bot Events
##
# --------------------------------------------------------------------------------------------------

sub start
{
  my $kernel = $_[KERNEL];
  plugin::set_global("version_plugin_fds_status_reporter", $currentVersion);

  # Schedule the first upload for 15 seconds time (giving BRenBot time to get the server status)
  $kernel->alarm(updateStatus => int(time()) + 15);

  return ($loaded_ok = 1);
}


sub stop
{
}




# --------------------------------------------------------------------------------------------------
##
#### FTP upload code
##
# --------------------------------------------------------------------------------------------------

# Creates the file to be uploaded
sub updateStatus
{
  my $kernel = $_[KERNEL];

  ## Update the data in the text file
  my $statusFile;
  if (!open($statusFile, ">./$config{'filename'}") )
  {
    plugin::console_output("[FDS Status Reporter] Failed to open $config{'filename'}");
    return;
  }

  # Report basic server info
  my ($serverMode, $map, $gdiPlayers, $gdiPoints, $nodPlayers, $nodPoints, $currentPlayers, $maxPlayers, $timeRemaining, $sfps) = plugin::getGameStatus();
  print $statusFile "$serverMode\n$map\n$gdiPlayers\n$gdiPoints\n$nodPlayers\n$nodPoints\n$maxPlayers\n$timeRemaining\n$sfps\n";

  # Report player info
  my %playerlist = plugin::get_playerlist();
  while ( my($id,$player) = each (%playerlist) )
  {
    print $statusFile "$player->{name}\t$player->{side}\t$player->{score}\t$player->{stats_kills}\t$player->{stats_deaths}\t$player->{ping}\t$player->{time}\n";
  }

  close $statusFile;

  uploadFile();

  # Schedule the next update
  $kernel->alarm(updateStatus => int(time()) + $config{'updateInterval'}*60);
}

# Uploads the status file
sub uploadFile
{
  ## Login to the FTP and upload our file
  my $ftp = Net::FTP->new("$config{'ftpServer'}", Debug => 0);
  if (!$ftp)
  {
    plugin::console_output("[FDS Status Reporter] Failed to connect to FTP server $config{'ftpServer'}");
    return;
  }

  if (!$ftp->login($config{'ftpUsername'}, $config{'ftpPassword'}))
  {
    plugin::console_output('[FDS Status Reporter] FTP Login Failed');
    $ftp->quit;
    return;
  }

  #plugin::console_output('[FDS Status Reporter] FTP Login Successful');

  if (!$ftp->cwd($config{'ftpPath'}))
  {
    plugin::console_output("[FDS Status Reporter] FTP Directory Path '$config{ftpPath}' does not exist!");
    $ftp->quit;
    return;
  }

  if ($ftp->put("./$config{'filename'}"))
  {
    plugin::console_output("[FDS Status Reporter] File $config{'filename'} uploaded successful\n");
  }
  else
  {
    plugin::console_output("[FDS Status Reporter] File $config{'filename'} upload failed!\n");
  }

  $ftp->quit;
}


# Plugin loaded OK
1;