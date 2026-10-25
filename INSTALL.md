<!-- SPDX-License-Identifier: MIT -->

# Install Living Fellows 0.26.68

For **Project Zomboid Build 42.21.0, single-player**. Choose Workshop or standalone; use one copy at a time.

[Field Guide](https://thorelvin.github.io/living-fellows/) · [Quick reference](https://thorelvin.github.io/living-fellows/quick-reference.html)

## Steam Workshop

1. Close Project Zomboid.
2. Subscribe to [ZombieBuddy](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853) **2.3.3 or newer** and follow its one-time loader setup. A subscription alone does not install the loader.
3. Subscribe to [Living Fellows](https://steamcommunity.com/sharedfiles/filedetails/?id=3805760339).
4. Start the game and enable both mods. For an existing save, enable both under **More… → Choose Mods** as well.

ZombieBuddy loads Living Fellows' Java bridge. Check its installation preview before approving the mod.

## Standalone Windows

1. Download a complete [standalone release](https://github.com/thorelvin/living-fellows/releases), or choose **Code → Download ZIP** on the repository.
2. Extract the whole folder. Run the installer from that folder, not from inside a ZIP viewer.
3. Close Project Zomboid and run **Install.bat**.
4. Launch the game normally and enable **Living Fellows** in **Mods** and in the save's **More… → Choose Mods** menu.

No ZombieBuddy installation or Workshop subscription is needed for this edition. If Windows denies access to the game folder, run the installer as Administrator.

For a different Steam library, open a terminal in the extracted folder and run:

```powershell
.\Install.bat -GameRoot "D:\SteamLibrary\steamapps\common\ProjectZomboid"
```

The installer puts the mod in `%USERPROFILE%\Zomboid\mods\SurvivorCompanion` and its managed bridge data in `%LOCALAPPDATA%\LivingFellows`. It adds `LivingFellowsBridge.jar` beside the game executable and updates the launcher configuration. It keeps the original launcher configuration for uninstall and does not modify `projectzomboid.jar`.

**Optional Debug menu:** `Install-Debug.bat` installs the same version with the in-game Debug tab and manual spawn controls enabled. Ordinary installation leaves those controls off. Both use the same `Uninstall.bat`.

## Updating or removing the standalone edition

Close the game and run **Install.bat** from the new complete download. The installer updates its managed files together, including the matching native bridge, and enables Living Fellows in the default mod profile.

To remove it, close the game and run **Uninstall.bat** from the extracted release folder. Keep `%LOCALAPPDATA%\LivingFellows` intact until uninstall finishes: it contains the ownership records and original launcher configuration. Verified launcher changes from other mods are preserved.

## If something isn't working

- **No companion panel:** press **Home**, look for the **LF** launcher, and check that Living Fellows is enabled for the current save.
- **Runtime inactive or companions appear as shadows:** Workshop users should check ZombieBuddy's loader setup and enable both mods for the save. Standalone users should close the game and rerun the latest installer.
- **After repairing or reinstalling the game:** rerun the latest `Install.bat`. It can restore the managed bridge entry when the retained installation records still verify. If it refuses, keep those records and report the exact error; do not edit the launcher by hand.
- **Two Living Fellows entries:** remove the duplicate installation. A Workshop upload staged under `%USERPROFILE%\Zomboid\Workshop` can also be discovered by the game; keep upload staging outside that directory when using the standalone edition.
- **Uninstall refuses:** use `Uninstall.bat` from the latest complete download and include the exact error in a report. The installer checks file ownership before changing an unfamiliar installation.

Open **More → Support** for a copyable report. Include it, your game version and the installation error in a [bug report](https://github.com/thorelvin/living-fellows/issues/new/choose).
