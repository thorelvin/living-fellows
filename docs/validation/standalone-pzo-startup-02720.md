# Windows standalone startup with PZO — 0.27.20 hotfix

The reported symptom was no game window and no new game logs after installing
0.27.20 standalone. The reporter uses an optimizer, but its exact identity and
version have not been confirmed. This investigation reproduces and fixes a
matching failure with **prop11's PZO launcher**; it does not establish which
optimizer the reporter has. The separate `pzopt.ActionEval` gameplay adapter
for PZ_Optimization is unchanged.

## Reproduction and cause

The LF standalone PZO path kept `com/pzoptimizer/PZOEntrypoint` as main but
added `-javaagent:LivingFellowsBridge.jar` to the launcher JSON. The real
`ProjectZomboid64.exe` embeds the JVM without making the bundled `jli.dll`
available to the instrumentation library. With the LF agent option, it exits
1 during VM initialization, before the game creates `console.txt`:

```text
Could not find agent library instrument on the library path
Module java.instrument may be missing from runtime image.
```

The same executable and bridge start successfully without that option. Both
absolute and relative `-agentpath` variants also fail. Starting through
`java.exe` does not reproduce the native executable's DLL-loading behavior.
The test compiler resolver can also hide the failure by adding a JDK bin
directory to PATH; the regression test removes directories containing
`jli.dll` from its test-process PATH before running the native executable.

This bootstrap option was already present in 0.27.19. The 0.27.19-to-0.27.20
source diff does not change the installer or launcher. PZO V2.1, released on
2026-11-14, removed its Windows native DLL and uses a different startup path.
Its own source documents the same native-executable/JLI limitation.

Primary sources:

- [PZO V2.1 release](https://github.com/prop11/PZO-Launcher/releases/tag/V2.1)
- [PZO AgentSelfLoader](https://github.com/prop11/PZO-Launcher/blob/V2.1/src/com/pzoptimizer/AgentSelfLoader.java)
- [PZO JavaModLoader](https://github.com/prop11/PZO-Launcher/blob/V2.1/src/com/pzoptimizer/JavaModLoader.java)

## Fix

PZO installs now use the `pzo-loader` ownership mode. The installer retains
PZO's main class and uses its existing Java mod loader to invoke the bridge's
`Premain-Class`. It checks that both PZO's entrypoint and JavaModLoader exist.
Updating a verified legacy `agent` installation removes only the owned LF
agent option. Other settings, classpath order, duplicates and foreign JARs
are retained. Legacy agent manifests remain supported for rollback/uninstall.

Standalone and private-test payloads also drop `javaPkgName`. That marker made
PZO classify the standalone bridge as a ZombieBuddy mod and skip its entry.
The canonical Workshop metadata retains the marker and dependency. A PZO
approval prompt for the standalone Java bridge remains PZO's normal user flow.

No Java bridge code, bridge JAR, game files, companion movement or zombie
navigation changes are required. The hotfix stays on the 0.27.20 line; the
unfinished 0.27.21 dialogue work is separate and remains paused.

## Validation

`scripts/Test-PzoStandaloneStartup.ps1` uses the real Windows executable and
bundled game JRE in an owned fixture. It checks the unmodified official PZO
V2.1 artifact, SHA-256
`417af446d2889bb80c0e92d07f5e70cae074f097bf1061c88981c6666ece2e26`.
Its native probe invokes PZO's real metadata reader and entrypoint dispatcher
with the installed standalone payload and real LF bootstrap. A test
Instrumentation proxy is passed because LF does not use instrumentation; it
rejects unexpected instrumentation calls. The legacy Workshop metadata is a
negative control for PZO's framework classification. A second control restores
the old agent option and must fail before the probe main runs.

This proves native VM startup, metadata acceptance and bootstrap dispatch.
It does not run PZO's full optimization/transformer pipeline or load a world.
The user's current save and installed game configuration are untouched.

- Clean standalone install, native failure control, loader bootstrap and
  original-launcher restoration pass:
  `build/pzo-startup-20261115-135029-09c809`.
- Actual 0.27.19 source installer followed by the fixed 0.27.20 installer passes
  the same controls and restores the original PZO configuration on uninstall:
  `build/pzo-startup-20261115-134757-ccd75a`.
- All 18 essential installer transaction cases pass, including legacy-agent
  upgrade fault rollback, clean PZO reinstall recovery, exact and selective
  uninstall, and refusal of ambiguous ownership.
- All five release checks pass in
  `build/test-results/20261115-135019-2a2d9a`: 299.4 seconds, 23 direct JVMs.

The owned native fixture directories contain a JRE junction and are retained
for audit. Do not recursively delete them as ordinary temporary folders.

To repeat the native check, supply the pinned official PZO JAR; the script
does not download or install third-party software automatically:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Test-PzoStandaloneStartup.ps1 -PzoJar C:\path\to\PZOptimEngine.jar
```

After obtaining the hotfix, re-run its `Install.bat`. Existing owned standalone
installations migrate in place. The reported machine still needs confirmation
by its owner because its optimizer identity and startup error are unknown.
