<!-- SPDX-License-Identifier: MIT -->

# Install Living Fellows

For **Project Zomboid Build 42.22.2, single-player**. The Windows standalone edition is recommended for this game version and includes its own native bridge. Choose Workshop or standalone; use one copy at a time.

[Field Guide](https://thorelvin.github.io/living-fellows/) · [Quick reference](https://thorelvin.github.io/living-fellows/quick-reference.html)

## Steam Workshop

1. Close Project Zomboid.
2. Subscribe to [ZombieBuddy](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853) **2.3.3 or newer** and follow its one-time loader setup. A subscription alone does not install the loader.
3. Subscribe to [Living Fellows](https://steamcommunity.com/sharedfiles/filedetails/?id=3805760339).
4. Start the game and enable both mods. For an existing save, enable both under **More… → Choose Mods** as well.

ZombieBuddy loads Living Fellows' Java bridge. Check its installation preview before approving the mod.

## Standalone Windows

1. Download the standalone Windows ZIP from the [latest GitHub release](https://github.com/thorelvin/living-fellows/releases/latest).
2. Extract the whole folder. Run the installer from that folder, not from inside a ZIP viewer.
3. Close Project Zomboid and run **Install.bat**.
4. Launch the game normally and enable **Living Fellows** in **Mods** and in the save's **More… → Choose Mods** menu.

No ZombieBuddy installation or Workshop subscription is needed for this edition. If Windows denies access to the game folder, run the installer as Administrator.

If you are subscribed to Living Fellows on the Steam Workshop, the installer stops without changing anything: the game always loads the Workshop copy instead of a standalone one. It opens the Workshop page in Steam; unsubscribe there, wait until Steam has removed it, and run **Install.bat** again. To keep the Workshop edition instead, use it with ZombieBuddy and don't install this one.

If PZO is already installed, Living Fellows keeps PZO's launcher and uses PZO's Java mod loader to start its bridge. Keep third-party Java mods enabled in **F10 → JAVA**. On the next full game launch, allow the Living Fellows bridge if PZO asks. PZO approves each bridge file separately, so an update can require approval again. Skipping the prompt leaves companions unavailable for that launch. PZO and LF retain their own settings, and uninstall removes only LF's entries. Use the complete current download so the installer and bridge match.

For a different Steam library, open a terminal in the extracted folder and run:

```powershell
.\Install.bat -GameRoot "D:\SteamLibrary\steamapps\common\ProjectZomboid"
```

The installer puts the mod in `%USERPROFILE%\Zomboid\mods\SurvivorCompanion` and its managed bridge data in `%LOCALAPPDATA%\LivingFellows`. It adds `LivingFellowsBridge.jar` beside the game executable and updates the launcher configuration. It keeps the original launcher configuration for uninstall and does not modify `projectzomboid.jar`.

**Optional Debug menu:** `Install-Debug.bat` installs the same version with the in-game Debug tab and manual spawn controls enabled. Ordinary installation leaves those controls off. Both use the same `Uninstall.bat`.

## Updating or removing the standalone edition

Close the game and run **Install.bat** from the new complete download. The installer updates its managed files together, including the matching native bridge, and enables Living Fellows in the default mod profile.

To remove it, close the game and run **Uninstall.bat** from the extracted release folder. It should end with `UNINSTALL COMPLETE`. Keep `%LOCALAPPDATA%\LivingFellows` intact until uninstall finishes: it contains the ownership records and original launcher configuration. Verified launcher changes from other mods are preserved.

Uninstall also works after Steam's **Verify integrity of game files**, a game update or a PZO install has rewritten the launcher. It removes only what Living Fellows still owns and takes Living Fellows out of the default mod list. Saves keep their own mod lists. It does not remove the Steam Workshop edition: if you are subscribed, the uninstaller names that copy, and you unsubscribe on Steam.

## If something isn't working

- **No companion panel:** press **Home**, look for the **LF** launcher, and check that Living Fellows is enabled for the current save.
- **Runtime inactive or companions appear as shadows:** Workshop users should check ZombieBuddy's loader setup and enable both mods for the save. Standalone users should close the game and rerun the latest installer.
- **Companions missing after a standalone update with PZO:** check **F10 → JAVA**, then fully restart the game and allow the updated Living Fellows bridge if PZO asks. Installing the files does not approve them in PZO. Saved companions wait for their bridge; their records are retained. If the problem continues, include `Zomboid\Lua\pzo_engine.log`, `pzo_engine.prev.log` and `pzo_config.json` in the report.
- **After repairing or reinstalling the game:** rerun the latest `Install.bat`. It can restore the managed bridge entry when the retained installation records still verify. If it refuses, keep those records and report the exact error; do not edit the launcher by hand.
- **"Two copies installed" in game:** a Workshop copy is loading with the standalone bridge. Keep one edition: unsubscribe from the Workshop copy, or run `Uninstall.bat` from the standalone download, then restart. **Review** opens Support with both versions.
- **Two Living Fellows entries:** remove the duplicate installation. The installer warns about an upload staging copy, and the uninstaller names any Workshop subscription or staging copy that keeps loading. A Workshop upload staged under `%USERPROFILE%\Zomboid\Workshop` can also be discovered by the game; keep upload staging outside that directory when using the standalone edition.
- **Very low frame rate or missing models after installing:** close the game, run `Uninstall.bat` and check that it ends with `UNINSTALL COMPLETE` and names no other copy. If the game is still slow after that, Living Fellows is no longer loading. Report it with `%USERPROFILE%\Zomboid\console.txt` from the slow session, your mod list and whether PZO, ZombieBuddy or the Workshop edition is installed.
- **Uninstall refuses:** close the game completely first; saving can take a minute, so check that `ProjectZomboid64.exe` has gone from Task Manager. Then use `Uninstall.bat` from the latest complete download and include the exact error in a report. The uninstaller checks file ownership before changing an unfamiliar installation.

Open **More → Support** for a copyable report. Include it, your game version and the installation error in a [bug report](https://github.com/thorelvin/living-fellows/issues/new/choose).
