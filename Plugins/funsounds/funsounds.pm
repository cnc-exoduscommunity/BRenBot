#
# SNDA Plugin 1.02
# orginal idea by zunnie
#

package funsounds;
use POE;
use plugin;
use strict;

# define additional events in the POE session

our %additional_events =
(
	# !commands
	"1" => "1",
);

# plugin_name and config are automatically given data by BRenBot
our $plugin_name;
our %config;
my $pluginVersion = 1.02;

my %keywords =
(
	"gotya" => "mx0_nodsniper_alt07.wav",
	"chiky" => "m00achk_kill0001i1gbmg_snd.wav",
	"skill" => "mxxdsgn_dsgn014i1gbmg_snd.wav",
	"snipe" => "mx0_nodsniper_alt01.wav",
	"killem" => "mx1dsgn_dsgn0018i1dsgn_snd.wav",
	"guns" => "mxxdsgn_dsgn005i1gbmg_snd.wav",
	"smile" => "mxxdsgn_dsgn004i1gbmg_snd.wav",
	"toy" => "mtudsgn_dsgn0289i1gbmg_snd.wav",
	"hehe" => "mtudsgn_dsgn0377a1gbmg_snd.wav",
	"kills" => "m00avis_kick0030i1moac_snd.wav",
	"jerks" => "m11dsgn_dsgn0104r1gbmg_snd.wav",
#	"^^" => "m00avis_kifi0021i1ccsf_snd.wav",
	"waiting" => "m11dsgn_dsgn0069i1mbpt_snd.wav",
	"tt" => "m00mstm_kill0013i1gbrs_snd.wav",
	"bwahaha" => "m00asqr_kill0019i1mbrs_snd.wav",
	"n00b" => "m00asqr_kill0018i1mbpt_snd.wav",
	"coffee" => "m00gnod_gcon0041i3nbmg_snd.wav",
	"squirrel" => "m00asqr_kill0034i1gbmg_snd.wav",
	"sit" => "m00bnsn_kill0053i1gbmg_snd.wav",
	"ask" => "m00ccck_kitb0029i1gbmg_snd.wav",
	"die" => "m00decx_004in_nsrs_snd.wav",
	"fun" => "m00gbmg_sfcx0001i1gbmg_snd.wav",
	"hunt" => "m00gbmg_sfsx0001i1gbmg_snd.wav",
	"medic" => "m00ffire_003in_gemg_snd.wav",
	"run" => "m00decx_010in_nbft_snd.wav",
	"daddy" => "mtudsgn_dsgn0320a1gbmg_snd.wav",
	"shoot" => "mxxdsgn_dsgn029i1gbmg_snd.wav",
	"haha" => "laugh1.wav",
	"burn" => "m00decx_009in_neft_snd.wav",
	"boink" => "m00bnss_kill0053i1gbmg_snd.wav",
	"more?" => "m00ccck_kitb0029i1gbmg_snd.wav",
	"nonono" => "m00gbrs_stoc0001i1gbrs_snd.wav",
	"noes" => "m00gcc3_sftd0001i1gcc3_snd.wav",
	"udie" => "m00gcf1_decx0001i1gcf1_snd.wav",
	"stfu" => "mxxdsgn_dsgn010i1gbmg_snd.wav",
	"boo" => "m00kimd_001in_neft_snd.wav",
	"i smell" => "m00avis_kifi0020i1nctk_snd.wav",
	"moo" => "amb_cow1.wav",
	"cya" => "m00bnol_kill0054i1gbmg_snd.wav",
	"help" => "m00gbrs_hftd0001i1gbrs_snd.wav",
	"gg" => "m00bncy_kill0054i1gbmg_snd.wav",
	"lucky" => "m00gnod_kill0037r1nbft_snd.wav",
	"urdead" => "l02b_02_hav02.wav",
	"finally" => "m00gsmg_atoc0001i1gsmg_snd.wav",
	"strike" => "m00gsrs_kill0029i1nbft_snd.wav",
	"wasted" => "m00gsrs_kiov0016i1nbft_snd.wav",
	"present" => "bombit1.wav",
	"pray" => "m11dsgn_dsgn0073i1mbpt_snd.wav",
	"amateur" => "m00bntu_kill0040i1gcm1_snd.wav",
	"eye" => "m03dsgn_dsgn0005r1gbmg_snd.wav"
	
);



 




########### Event handlers

# Runs when BRenBot loads the plugin
sub start
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	
	# Set our current version in the globals table
	plugin::set_global ( "version_plugin_funsounds", $pluginVersion );
}

# Runs when BRenBot shuts down
sub stop
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
}

# Runs when any text is typed ingame or in IRC
sub text
{
	my ( $session, $heap, $args ) = @_[ SESSION, HEAP, ARG0 ];
	my $kernel = $_[KERNEL];
	my %args = %{$args};
	
	return if ( $config{'trigger_f2chat'} == 0 && $args{messagetype} eq 'public' );
	return if ( $config{'trigger_f3chat'} == 0 && $args{messagetype} eq 'team' );
	return if ( $config{'trigger_irc'} == 0 && $args{messagetype} eq 'irc_public' );
	
	
	while (my ($keyword, $sound) = each %keywords)
	{
		if ($args{message} =~ m/$keyword/)
		{
			print ("Sending $sound\n");
			plugin::RenRemCMD("snda $sound");
		} 
	}
}




1;
