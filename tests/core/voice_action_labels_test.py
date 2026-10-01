"""Guard status speech against raw supervisor action keys."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "SurvivorCompanion/42/media/lua/client"


def mapping_block(source: str, name: str) -> str:
    return source.split(f"local {name} = {{", 1)[1].split("\n}", 1)[0]


def missing_labels(actions: set[str], labels: set[str], prefixes: set[str]) -> set[str]:
    return {action for action in actions
            if action not in labels
            and not any(action.startswith(prefix) for prefix in prefixes)}


def main() -> None:
    relationship = (CLIENT / "SCRelationship.lua").read_text(encoding="utf-8")
    labels = set(re.findall(r"\b([a-z_]+)\s*=\s*\"",
                            mapping_block(relationship, "doingLabels")))
    prefixes = set(re.findall(r"\b([a-z_]+)\s*=\s*\"",
                              mapping_block(relationship, "doingPrefixes")))
    actions: set[str] = set()
    for path in CLIENT.glob("*.lua"):
        actions.update(re.findall(r"\baction\s*=\s*\"([a-z_]+)\"",
                                  path.read_text(encoding="utf-8")))
    assert actions and labels, "action or label inventory is empty"
    missing = missing_labels(actions, labels, prefixes)
    assert not missing, f"unlabelled supervisor actions: {', '.join(sorted(missing))}"
    assert missing_labels({"unlisted_task"}, labels, prefixes) == {"unlisted_task"}, \
        "negative control: unknown actions must fail the label inventory"
    print(f"VOICE_ACTION_LABELS_PASS actions={len(actions)} labels={len(labels)}")


if __name__ == "__main__":
    main()
