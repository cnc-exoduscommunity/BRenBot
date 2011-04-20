#!/usr/bin/perl

package results;
use strict;

use POE;

use modules;

our $mostkills;
our $mostdeaths;
our $mostkd;

sub DisplayGameResults
{
	my ( $session, $heap ) = @_[ SESSION, HEAP ];
  	my $kernel = $_[KERNEL];

	my $map = serverStatus::getLastMap();
	$map =~ s/\.mix//g;

	# Instead of messing around sorting arrays, just store the
	# results in these variables
	my $bestScore	= 0;		my $bestScoreName	= "";
	my $bestKills	= 0;		my $bestKillsName	= "";
	my $worstDeaths	= 0;		my $worstDeathsName	= "";
	my $bestKD		= 0.0;		my $bestKDName		= "";

	#use Sort::Array qw(Sort_Table);
	my $result = find_result_file();

	# First we grab the filename (thanks xmath!)
	if ( defined ($result) )
	{
		my $file = "$brconfig::config_fdslogpath" . "$result";

		#print "DEBUG: Looking for $file\n";
		my @results;


		if ( open ( LOGFILE, $file ) )
		{
			while ( <LOGFILE> )
			{							#take one input line at a time
			  chomp;
				#### WOL RESULTS FORMAT
				#	 Player	 Kills   Deaths  K/D	 Credits Score   Rank
				#  1. crimsson   1	   1	   1.0	 2245	2133	2188	  Nod
				#  2. genlkozar  6	   1	   6.0	 1509	1349	1969	  Nod
				#-----------------------------------------------------------------------------
				#### LFDS RESULTS FORMAT (has no Rank column...neither does Win32+GSA mode)
				#	 Player							  Kills   Deaths  K/D	 Credits Score
				#  1. [AoA]Night_Hawk					 6	   4	   1.5	 6568	4287	  GDI
				#  2. =|GWoD|=Cell						11	  8	   1.4	 4427	2358	  GDI
				#------------------------------------------------------------------------------
				#### RENALERT RESULT FORMAT
				# Player	Kills	Deaths	K/D	Credits	Score	Ladder	Rank
				# 1. DaLinkZ	14	2	7.0	2197	2888	36	-	Allies
				# 2. bman1992	9	1	9.0	2325	357	26	7005	Allies
				# 3. hog654321	1	1	1.0	1825	326	21	4090	Allies
				# 4. migwolf	3	3	1.0	1432	70	15	-	Allies
				# 5. DC50	4	2	2.0	2134	48	10	11979	Allies
				# 6. huntermcc	7	2	3.5	1703	35	6	-	Allies
				# 7. bartokk77	3	3	1.0	111	35	3	-	Allies
				# 8. TruYuri	5	1	5.0	1599	25	1	11991	Allies
				# 9. endepende	3	6	0.5	88	140	0	4721	Soviet
				#------------------------------------------------------------------------------
				# The new regex below should work for all results.txt formats
				# I also added proper detection and correction of "-" for K/D and Credits.
				# -Blazer
				# Update 06/07/2004
				# Redid Regex AGAIN...now it definitely works for any and all kinds of fucked up nicks.
				# -Blazer

				if (/\s+\d+\.\s([^\#]+)[\s\#]+(\d+)\s+(\d+)\s+(\S+)\s+(\d+)\s+(\d+).+(Nod|GDI|Allies|Soviet)/)	# new improved regex
				{
			#	if (/\s+\d+\.\s(.+?)[\s\#]+(\d+)\s+(\d+)\s+([\d\-\.]+)\s+([\d\-]+)\s+(\d+).+(Nod|GDI)/i)			#old buggy regex
			#	{

					my %hash;
					$hash{name} = $1;
					$hash{kills} = $2;
					$hash{death} = $3;
					$hash{kdratio} = ( $3 == 0 ) ? $2 : sprintf ( "%.1f", ( $2 / $3) );		# If player had 0 deaths kd = kills
					$hash{creds} = $5;
					$hash{score} = $6;
					$hash{side} = $7;

					$hash{name} =~ s/^( +)//; ## remove all spaces at start
					$hash{name} =~ s/( +)$//; ## remove spaces at end

					# Push the data hash onto the results array
					push ( @results, \%hash );


					# Check for best score / most kills / best KD
					if ( $hash{score} > $bestScore )
					{
						$bestScore = $hash{'score'};	$bestScoreName = $hash{'name'};
					}
					if ( $hash{kills} > $bestKills )
					{
						$bestKills = $hash{'kills'};	$bestKillsName = $hash{'name'};
					}
					if ( $hash{kdratio} > $bestKD )
					{
						$bestKD = $hash{'kdratio'};		$bestKDName = $hash{'name'};
					}
					if ( $hash{kdratio} < $worstDeaths )
					{
						$worstDeaths = $hash{'death'};	$worstDeathsName = $hash{'name'};
					}
				}
			}	# End file read while loop

			close LOGFILE;


			# Trigger plugin gameresult event
			my @plugins = plugin::get_plugin_event( "gameresult" );
			my %args;
			$args{gameresults} = \@results;
			foreach ( @plugins )
			{
				my $plugin = $_;
				my $alias = "plugin_" . $plugin;

				$kernel->post( $alias => "gameresult" => \%args );
			}


			# Create session to show results in a 45 seconds time
			POE::Session->create
			( inline_states =>
				{
					_start => sub
					{
						$_[HEAP]->{next_alarm_time} = int( time() ) + 45;
						$_[KERNEL]->alarm( tick => $_[HEAP]->{next_alarm_time} );
					},
					tick => sub
					{
						modules::console_output ( "Processing game results" );

						# MVP recommendation
						if ( $bestScore >= $brconfig::config_autorec_minscore )
						{
							modules::recommend_player( $bestScoreName, "BRenBot", "MVP on $map with $bestScore points" );
							bhs::playsndp( "bonus_complete.wav", $bestScoreName );
						}

						# Most Kills recommendation
						if ( $bestKills >= $brconfig::config_autorec_minkills )
						{
							modules::recommend_player( $bestKillsName, "BRenBot", "Most Kills on $map with $bestKills frags" );
							bhs::playsndp( "bonus_complete.wav", $bestKillsName );
						}

						# Best K/D ratio recommendation
						if ( $bestKD >= $brconfig::config_autorec_minkd )
						{
							modules::recommend_player( $bestKDName, "BRenBot", "Best K/D Ratio on $map with $bestKD" );
							bhs::playsndp( "bonus_complete.wav", $bestKDName );
						}

						# Most kills lastgame autoannounce cookie
						$mostkills= "";
						if ( $bestKills > 0 )
						{
							$mostkills = "Most KILLS last game was $bestKillsName with $bestKills frags";
						}

						# Most deaths lastgame autoannounce cookie
						$mostdeaths= "";
						if ( $worstDeaths > 0 )
						{
							$mostdeaths = "Most DEATHS last game was $worstDeathsName with $worstDeaths deaths";
						}

						# Best KD lastgame autoannounce cookie
						$mostkd= "";
						if ( $bestKD > 0 )
						{
							$mostkd = "The highest Kill/Death ratio last game was $bestKDName with $bestKD";
						}
					} # end of tick
				} # end of inline states
			);
		}
	}
}	# End sub DisplayGameResults


sub find_result_file
{
	my $dir = "$brconfig::config_fdslogpath";

	opendir(DIR,$dir);
	my @dirContents = readdir(DIR);
	closedir(DIR);

	my @result_files;
	foreach (@dirContents)
	{
		my $filename = $_;
		if(!(($_ eq ".") || ($_ eq "..")))
		{
			if ($filename =~ m/result(.+?).txt/g)
			{
				my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
				  $atime,$mtime,$ctime,$blksize,$blocks)
					  = stat($brconfig::config_fdslogpath . $filename);

				my %hash;
				$hash{'name'} = $filename;
				$hash{'time'} = $mtime;
				push ( @result_files, \%hash );
			}

		}
	} # end of foreach

	my $old_time=0;
	my $result;
	foreach ( @result_files )
	{
		if ( $_->{time} > $old_time )
		{
			$old_time = $_->{'time'};
			$result = $_->{'name'};

		}

	}
	return $result;
}

1;
