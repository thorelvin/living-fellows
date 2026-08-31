# SPDX-License-Identifier: MIT

from pathlib import Path
import re
import zipfile


ROOT = Path(__file__).resolve().parents[2]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def capture(pattern: str, text: str, label: str) -> str:
    match = re.search(pattern, text, re.MULTILINE)
    require(match is not None, f"missing {label}")
    return match.group(1)


namespace = (ROOT / "SurvivorCompanion/42/media/lua/shared/SCNamespace.lua").read_text(
    encoding="utf-8"
)
actor = (ROOT / "SurvivorCompanion/42/media/lua/client/SCActor.lua").read_text(
    encoding="utf-8"
)
bridge = (ROOT / "bridge/src/main/java/survivorcompanion/bridge/SCBridge.java").read_text(
    encoding="utf-8"
)
manifest = (ROOT / "bridge/native/MANIFEST.MF").read_text(encoding="utf-8")
architecture = (ROOT / "ARCHITECTURE.md").read_text(encoding="utf-8")
version = (ROOT / "VERSION.txt").read_text(encoding="utf-8").strip()
source_workflow = (ROOT / ".github/workflows/source-ci.yml").read_text(encoding="utf-8")
real_jar_workflow = (ROOT / ".github/workflows/real-jar-compatibility.yml").read_text(
    encoding="utf-8"
)

lua_release = capture(r'release\s*=\s*"([^"]+)"', namespace, "Lua release")
lua_game = capture(r'gameVersion\s*=\s*"([^"]+)"', namespace, "Lua game version")
lua_protocol = capture(r'bridgeProtocol\s*=\s*"([^"]+)"', namespace, "Lua protocol")
save_key = capture(r'saveKey\s*=\s*"([^"]+)"', namespace, "save key")
save_schema = capture(r'saveSchema\s*=\s*(\d+)', namespace, "save schema")
java_protocol = capture(r'PROTOCOL\s*=\s*"([^"]+)"', bridge, "Java protocol")
java_game = capture(r'COMPILED_GAME_VERSION\s*=\s*"([^"]+)"', bridge, "Java game version")
jar_protocol = capture(r'^SC-Bridge-Protocol:\s*(\S+)', manifest, "JAR protocol")
jar_game = capture(r'^SC-Compiled-Game-Version:\s*(\S+)', manifest, "JAR game version")

require(version == lua_release, "VERSION.txt and SC.Identity.release disagree")
for info_path in (ROOT / "SurvivorCompanion/mod.info", ROOT / "SurvivorCompanion/42/mod.info"):
    info = info_path.read_text(encoding="utf-8")
    require(capture(r'^modversion=(\S+)', info, str(info_path)) == version,
            f"{info_path} version disagrees")
require(lua_protocol == java_protocol == jar_protocol,
        "Lua, Java, and source JAR manifest protocols disagree")
require(lua_game == java_game == jar_game,
        "Lua, Java, and source JAR manifest game versions disagree")
require("local expectedNativeProtocol = SC.Identity.bridgeProtocol" in actor,
        "SCActor must read the shared protocol identity")
require(lua_protocol in architecture and "42.20-isocompanion-4" not in architecture,
        "architecture protocol documentation drifted")
require(save_key == "SC_SaveV1" and save_schema == "2"
        and "stable save key `SC_SaveV1` with document schema 2" in architecture,
        "stable save key/schema documentation drifted")
require("pull_request:" in source_workflow
        and "./scripts/Test-Source.ps1" in source_workflow,
        "pull requests must execute the source-only reliability gate")
require("self-hosted" in real_jar_workflow
        and "./scripts/Test-Project.ps1" in real_jar_workflow,
        "trusted real-JAR compatibility workflow is missing")

payload_jar = ROOT / "SurvivorCompanion/42/media/java/SurvivorCompanionBridge.jar"
with zipfile.ZipFile(payload_jar) as archive:
    packaged_manifest = archive.read("META-INF/MANIFEST.MF").decode("utf-8")
require(f"SC-Bridge-Protocol: {lua_protocol}" in packaged_manifest
        and f"SC-Compiled-Game-Version: {lua_game}" in packaged_manifest,
        "packaged bridge metadata disagrees with source constants")

print(
    "RELEASE_SYNC_PASS "
    f"release={version} protocol={lua_protocol} game={lua_game} "
    f"save={save_key}/schema-{save_schema}"
)
