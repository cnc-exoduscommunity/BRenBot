Swap Plugin
Version 1.00
Daniel Paul (danpaul88)
danpaul88@yahoo.co.uk


The swap plugin for BRenBot allows players to swap teams upon mutual agreement between
two players on opposite teams. This plugin replicates the functionality of the !swap
command created by Oxi on the APB official server.

If you want to ask any questions, request new features or report bugs please post on
the Renegade Public forums (www.renegadeforums.com) in the Technical Support -> Other
area, or email me.


###############
Installation
###############

Extract the plugins folder to your BRenBot folder.


###############
Additional Credits
###############
Oxi - Original !swap implementation idea


###############
Changelog
###############

1.01
 - Fixed bug where any player leaving the game would cause other players swaps to
     be cancelled

1.0
 - First Release

###############
Commands
###############

!swap
  Issue a request to swap teams. If a player on the opposite team has already issued a
  swap request the player using the command will swap places with the first player. Only
  one swap request may be active at any time.


!swapcancel
  Cancels a swap request, may be used by the requestee or moderators, dependant on settings.


###############
Config Settings
###############

tempModCanCancelSwaps
  Set this to 1 to allow temporary moderators to cancel other players swap requests

halfModCanCancelSwaps
  Set this to 1 to allow half moderators to cancel other players swap requests

fullModCanCancelSwaps
  Set this to 1 to allow full moderators to cancel other players swap requests

ircHalfOpCanCancelSwaps
  Set this to 1 to allow IRC half operators to cancel swap requests

ircOpCanCancelSwaps
  Set this to 1 to allow IRC operators to cancel swap requests