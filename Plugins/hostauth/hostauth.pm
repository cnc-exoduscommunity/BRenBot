#
# Host Authentication plugin for BRenBot 1.53 by Daniel Paul
#
# Automatically authenticates users if they have joined from a predefined hostname or IP address in
# the plugin XML configuration file
#
# Version 1.00
#
package hostauth;

use POE;
use plugin;
use Net::DNS::Resolver;

# define additional events in the POE session
our %additional_events = (
 "tryauth" => "tryauth"
);

# BRenBot automatically sets the plugin name
our $plugin_name;

# BRenBot automatically imports the plugin's config (from the xml file) into %config
our %config;

our $currentVersion = 1.00;
my $dnsresolver;


########### Event handlers

sub start
{
  # Set our current version in the globals table
  plugin::set_global ( "version_plugin_hostauth", $currentVersion );
  
  $dnsresolver = Net::DNS::Resolver->new(nameservers => [qw(8.8.8.8)]);
}


sub stop
{
  undef $dnsresolver;
}


sub playerjoin
{
  my %args = %{$_[ ARG0 ]};

  if ( defined($config{$args{'nick'}}) )
    { $poe_kernel->alarm( tryauth => (int(time()) +3) => $args{'nick'} ); }
}

# Triggered by the timer on playerjoin event
sub tryauth
{
  my $playername = $_[ ARG0 ];

  if ( defined($config{$playername}) )
  {

    my ( $result, %player ) = plugin::getPlayerData( $playername );
    return if ( $result != 1 || !$player{'ip'} );

    my $ip = $config{$playername};
    if ( $ip !~ '/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/' )
    {
      # IP to hostname
      my $hostname = $ip;
      undef $ip;
      my $query = $dnsresolver->search($hostname);
      if ($query) {
        foreach my $rr ($query->answer) {
          next unless $rr->type eq "A";
          $ip = $rr->address;
        }
      }
      
      return if ( !defined($ip) );
    }
    
    # Auth
    if ( $ip eq $player{'ip'} )
    {
      plugin::call_command("BRenBot", "!auth ".$playername);
      plugin::ircmsg ( "Automatically authenticated $playername based on hostname", "A" );
    }
  }
  
  return;
}


# Return true or the bot will not work properly...
1;