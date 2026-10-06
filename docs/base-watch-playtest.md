# Base Watch playtest

Base Watch keeps camp loaded through a real second local view while the player
travels. The chosen leader remains a base-duty companion; other residents keep
their usual jobs. It uses the same view slot as expeditions, so the two modes
cannot run together.

## In a cloned save

1. Stand inside the marked camp area with an indoor base-duty companion. Open
   **More > Base** and choose that companion under **Base Watch**. Start it and
   wait for the second view to appear.
2. Leave camp. Confirm the leader remains indoors in the second view and
   another resident continues a loaded camp job. A worker beyond the leader's
   loaded area may wait for the area to stream again.
3. Try a direct companion order and a camp policy edit from the remote UI;
   both should be refused. Equip powered two-way radios on the player and the
   leader, set the same channel, then request status and change defense policy.
   Turn one radio off or change its channel and confirm the policy stays put.
4. Save and reload while away. The cold loader should restore the camp view,
   then hand it to the exact saved leader. Check the leader's clothes, inventory,
   work order, and the one reused local-player save slot.
5. Return to camp near the leader. The second view should close once the
   primary player's map owns that area. Starting a later expedition should
   reuse the released slot.
6. In a separate clone, move the watched leader outdoors for several seconds
   while another indoor resident is nearby. The indoor resident should take
   the view. If the leader dies, the next eligible resident should take it;
   with none available the mode should end after native corpse handling.

The automated `base-watch` core harness checks the asynchronous join, radio
acknowledgement, policy refusal, living/dead handoff, return release, and cold
restore. The native control test checks that a living handoff keeps one SQL
row and rejects a successor with a different saved local-player identity.
