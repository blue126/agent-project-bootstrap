#!/usr/bin/env python3
"""Read-only BMAD installation planning and file verification (Python 3.11+)."""

import argparse
import csv
import io
import json
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
if sys.version_info < (3, 11):
    print("Python 3.11+ is required for this helper.", file=sys.stderr)
    raise SystemExit(2)

try:
    import yaml
except ImportError:
    print("PyYAML is required; provision this skill's requirements.txt in an isolated environment.", file=sys.stderr)
    raise SystemExit(2) from None


BMM_SKILLS = {"bmad-prd", "bmad-architecture", "bmad-build"}
VERIFIED_VERSIONS = {"6.12.0"}
IDENTIFIER = re.compile(r"[a-zA-Z0-9][a-zA-Z0-9_.-]*\Z")
VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9.-]+)?\Z")


class InvalidInput(ValueError):
    pass


class UniqueLoader(yaml.SafeLoader):
    def construct_mapping(self, node, deep=False):
        self.flatten_mapping(node)
        mapping = {}
        for key_node, value_node in node.value:
            key = self.construct_object(key_node, deep=deep)
            if not isinstance(key, str) or key in mapping:
                raise InvalidInput("YAML mapping keys must be unique strings")
            mapping[key] = self.construct_object(value_node, deep=deep)
        return mapping


def identifiers(values, label, allow_empty=False):
    if not isinstance(values, list) or (not values and not allow_empty):
        raise InvalidInput(f"{label} must be {'a' if allow_empty else 'a nonempty'} list")
    if any(not isinstance(value, str) or not IDENTIFIER.fullmatch(value) for value in values):
        raise InvalidInput(f"{label} contains an invalid identifier")
    return sorted(set(values))


def target_directory(value):
    path = Path(value)
    if not path.is_absolute():
        raise InvalidInput("--target must be an explicit absolute path")
    target = path.resolve(strict=True)
    if not target.is_dir():
        raise InvalidInput("--target must be an existing directory")
    return target


def within(target, relative):
    path = target / relative
    resolved = path.resolve()
    if not resolved.is_relative_to(target):
        raise InvalidInput(f"Path escapes the target through a symlink: {relative}")
    return path


def read_text(target, relative):
    path = within(target, relative)
    if not path.is_file():
        raise InvalidInput(f"Missing readable file: {relative}")
    return path.read_text(encoding="utf-8")


def installed(target):
    content = read_text(target, "_bmad/_config/manifest.yaml")
    manifest = yaml.load(content, Loader=UniqueLoader)
    if not isinstance(manifest, dict):
        raise InvalidInput("manifest must be a YAML mapping")
    installation = manifest.get("installation")
    if not isinstance(installation, dict) or not isinstance(installation.get("version"), str):
        raise InvalidInput("manifest installation.version must be a string")
    if not VERSION.fullmatch(installation["version"]):
        raise InvalidInput("manifest installation.version must be an exact version")
    modules = manifest.get("modules")
    if not isinstance(modules, list):
        raise InvalidInput("manifest modules must be a list")
    modules = identifiers([item.get("name") if isinstance(item, dict) else item for item in modules], "modules")
    if "core" not in modules:
        raise InvalidInput("Existing manifest lacks core; inspect the incomplete installation")
    tools = identifiers(manifest.get("ides"), "ides", allow_empty=True)
    return {"version": installation["version"], "modules": modules, "tools": tools}


def record(target, version, previous, requested):
    if version not in VERIFIED_VERSIONS:
        raise InvalidInput(f"Unsupported installer contract: {version}; verified versions: {', '.join(sorted(VERIFIED_VERSIONS))}")
    modules = sorted(set(previous["modules"] + requested["modules"] + ["core"]))
    tools = sorted(set(previous["tools"] + requested["tools"]))
    action = "update" if previous["modules"] else None
    argv = ["npx", "--yes", f"bmad-method@{version}", "install", "--yes", "--directory", str(target)]
    if action:
        argv.extend(["--action", action])
    # The installer injects core; retain it explicitly for a core-only request.
    argv.extend(["--modules", ",".join([m for m in modules if m != "core"] or ["core"]), "--tools", ",".join(tools)])
    return {
        "schema_version": 1,
        "status": "planned",
        "target": str(target),
        "installer_version": version,
        "action": action,
        "existing": previous,
        "requested": requested,
        "expected": {"modules": modules, "tools": tools},
        "argv": argv,
    }


def preflight(target, version, modules, tools):
    for relative in ("_bmad", ".claude/skills"):
        within(target, relative)
    bmad = within(target, "_bmad")
    if bmad.exists() or bmad.is_symlink():
        previous = installed(target)
        current = tuple(map(int, previous["version"].split("-")[0].split(".")))
        selected = tuple(map(int, version.split("-")[0].split("."))) if VERSION.fullmatch(version) else ()
        if selected and current > selected:
            raise InvalidInput("Refusing to plan a downgrade of the existing installer version")
    else:
        legacy = target / "bmad"
        skills = within(target, ".claude/skills")
        if legacy.exists() or legacy.is_symlink() or any(skills.glob("bmad-*")):
            raise InvalidInput("BMAD evidence exists without _bmad; inspect the legacy or incomplete installation")
        previous = {"version": None, "modules": [], "tools": []}
    requested = {"modules": identifiers(modules, "requested modules"), "tools": identifiers(tools, "requested tools")}
    return record(target, version, previous, requested)


def load_record(target, path):
    before = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(before, dict) or before.get("target") != str(target):
        raise InvalidInput("Before-record target does not match --target")
    previous = before.get("existing")
    requested = before.get("requested")
    if not isinstance(previous, dict) or not isinstance(requested, dict):
        raise InvalidInput("Invalid before-record sets")
    for key in ("modules", "tools"):
        identifiers(previous.get(key), f"existing {key}", allow_empty=True)
        identifiers(requested.get(key), f"requested {key}")
    if previous["modules"]:
        if "core" not in previous["modules"] or not isinstance(previous.get("version"), str):
            raise InvalidInput("Invalid before-record installation")
        if not VERSION.fullmatch(previous["version"]):
            raise InvalidInput("Invalid before-record installation version")
    elif previous.get("version") is not None or previous["tools"]:
        raise InvalidInput("Invalid fresh-install before-record")
    version = before.get("installer_version")
    if not isinstance(version, str) or before != record(target, version, previous, requested):
        raise InvalidInput("Before-record is inconsistent; use unmodified preflight JSON")
    return before


def verify(target, before):
    after = installed(target)
    expected = before["expected"]
    errors = []
    for key in ("modules", "tools"):
        missing = sorted(set(expected[key]) - set(after[key]))
        if missing:
            errors.append(f"Missing {key}: {', '.join(missing)}")
    if after["version"] != before["installer_version"]:
        errors.append("Installed version does not match the selected installer version")
    for module in expected["modules"]:
        if not within(target, f"_bmad/{module}").is_dir():
            errors.append(f"Missing module directory: {module}")

    required_skills = {"bmad-help"}
    if "bmm" in expected["modules"]:
        required_skills |= BMM_SKILLS
    try:
        catalog = csv.DictReader(io.StringIO(read_text(target, "_bmad/_config/bmad-help.csv")), strict=True)
        headers = catalog.fieldnames or []
        if not {"module", "skill"}.issubset(headers) or len(headers) != len(set(headers)):
            raise InvalidInput("Help CSV requires unique module and skill columns")
        rows = list(catalog)
        if not rows or any(None in row or any(value is None for value in row.values()) for row in rows):
            raise InvalidInput("Help CSV has empty or malformed rows")
        found = {row["skill"] for row in rows}
        missing = sorted(required_skills - found)
        if missing:
            errors.append(f"Missing help entries: {', '.join(missing)}")
    except (OSError, ValueError, csv.Error) as error:
        errors.append(str(error))

    count = None
    if "claude-code" in expected["tools"]:
        skills = within(target, ".claude/skills")
        count = 0
        for entry in sorted(skills.glob("*/SKILL.md")):
            try:
                if read_text(target, entry.relative_to(target)).strip():
                    count += 1
            except (OSError, ValueError):
                # Unrelated external/broken skills do not prove or disprove BMAD.
                continue
        for name in sorted(required_skills):
            try:
                if not read_text(target, f".claude/skills/{name}/SKILL.md").strip():
                    raise InvalidInput(f"Empty skill entry: {name}")
            except (OSError, ValueError) as error:
                errors.append(str(error))
    return {
        "status": "failed" if errors else "files_verified",
        "target": str(target),
        "installed": after,
        "claude_skill_count": count,
        "tool_integrations_not_verified": [tool for tool in expected["tools"] if tool != "claude-code"],
        "errors": errors,
        "session_loading": "not_verified",
        "python_runtime": "not_verified",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    plan = commands.add_parser("preflight", help="Print a read-only installation plan; never execute it")
    plan.add_argument("--target", required=True)
    plan.add_argument("--installer-version", required=True)
    plan.add_argument("--modules", required=True, help="Requested comma-separated module IDs")
    plan.add_argument("--tools", required=True, help="Requested comma-separated tool IDs")
    check = commands.add_parser("verify", help="Verify installed files against preflight JSON")
    check.add_argument("--target", required=True)
    check.add_argument("--before", required=True, help="Saved, unmodified preflight JSON")
    args = parser.parse_args()
    try:
        target = target_directory(args.target)
        if args.command == "preflight":
            result = preflight(target, args.installer_version, args.modules.split(","), args.tools.split(","))
        else:
            result = verify(target, load_record(target, args.before))
    except (OSError, ValueError, yaml.YAMLError, RuntimeError) as error:
        print(json.dumps({"status": "blocked", "error": str(error)}, ensure_ascii=False))
        return 2
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 1 if result["status"] == "failed" else 0


if __name__ == "__main__":
    raise SystemExit(main())
