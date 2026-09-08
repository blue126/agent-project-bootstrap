#!/usr/bin/env python3
"""Local onboarding facts and optimistic, metadata-preserving selection updates.

This deliberately reads bootstrap's small block-mapping format, not general YAML.
Client selections use JSON flow arrays. Unknown mapping subtrees stay verbatim.
No installers, project commands, Git mutations, or network requests run here.
"""
import argparse
import csv
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
SOURCE = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("bootstrap_merge", SOURCE / "scripts/lib/merge-bootstrap-config.py")
merger = importlib.util.module_from_spec(spec)
spec.loader.exec_module(merger)
WORKFLOWS = {"github-workflow": "github-workflow", "superpowers": "using-superpowers", "bmad": "bmad-help"}
IDENTIFIER = re.compile(r"[a-zA-Z0-9][a-zA-Z0-9_.-]*\Z")
HEADER = re.compile(r"^( *)([a-zA-Z_][a-zA-Z0-9_-]*):(?:[ \t]+(.*))?\r?\n?$")
LIMIT = 2 * 1024 * 1024


def mapping(lines, indent=0):
    """Validate keys at this level without interpreting opaque child subtrees."""
    for line in lines:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        leading = line[:len(line) - len(line.lstrip())]
        if "\t" in leading:
            raise ValueError("Unsupported bootstrap indentation")
        if len(leading) < indent or (len(leading) == indent and not HEADER.fullmatch(line)):
            raise ValueError("Unsupported bootstrap mapping syntax")
    return merger.entries(lines, indent)[1]


def scalar(block):
    value = HEADER.fullmatch(block[0])[3] or ""
    if any(line.strip() and not line.lstrip().startswith("#") for line in block[1:]):
        raise ValueError("Expected a single-line bootstrap value")
    value = value.strip()
    if value.startswith('"'):
        try:
            result, end = json.JSONDecoder().raw_decode(value)
        except ValueError:
            raise ValueError("Unsupported bootstrap scalar") from None
        if not isinstance(result, str) or (value[end:].strip() and not value[end:].lstrip().startswith("#")):
            raise ValueError("Unsupported bootstrap scalar")
        return result
    if value.startswith("'"):
        match = re.fullmatch(r"'((?:[^']|'')*)'\s*(?:#.*)?", value)
        if not match:
            raise ValueError("Unsupported bootstrap scalar")
        return match[1].replace("''", "'")
    value = re.split(r"\s+#", value, maxsplit=1)[0]
    if not value or re.search(r"[\[\]{}&*!>|]", value):
        raise ValueError("Unsupported bootstrap scalar")
    return value


def child(block, indent):
    header = HEADER.fullmatch(block[0])
    if header[3] and not header[3].lstrip().startswith("#"):
        raise ValueError("Unsupported inline bootstrap mapping")
    return mapping(block[1:], indent)


def path_in(project, relative, links=False):
    """Policy/config paths reject links; skill entries allow relative local links."""
    relative = Path(relative)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError("Unsafe project path")
    current = project
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            if not links or Path(os.readlink(current)).is_absolute():
                raise ValueError(f"Refusing symlink: {relative}")
        if not current.resolve().is_relative_to(project):
            raise ValueError(f"Path escapes project: {relative}")
    return current


def read_bytes(path):
    with path.open("rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError("Expected a regular project file")
        data = stream.read(LIMIT + 1)
    if len(data) > LIMIT:
        raise ValueError("Project metadata exceeds size limit")
    return data


def text(project, relative, links=False):
    path = path_in(project, relative, links)
    return read_bytes(path).decode("utf-8") if path.is_file() else ""


def clients_manifest():
    lines = (SOURCE / "bootstrap-manifest.yml").read_text().splitlines(keepends=True)
    skills = child(mapping(lines)["skills"], 2)
    block = skills["supported_agents"]
    if (HEADER.fullmatch(block[0])[3] or "").strip():
        raise ValueError("Unsupported supported_agents manifest format")
    clients, record = {}, None
    for line in block[1:]:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = re.fullmatch(r"    - name: ([a-z0-9-]+)\s*", line)
        if match:
            record = {}
            if match[1] in clients:
                raise ValueError("Duplicate manifest agent")
            clients[match[1]] = record
            continue
        match = re.fullmatch(r"      ([a-z_]+): (\S+)\s*", line)
        if not match or record is None or match[1] in record:
            raise ValueError("Unsupported supported_agents manifest format")
        record[match[1]] = match[2]
    for record in clients.values():
        value = record.get("project_path", "")
        if not value or Path(value).is_absolute() or ".." in Path(value).parts:
            raise ValueError("Invalid manifest project_path")
    if not clients:
        raise ValueError("Manifest has no supported agents")
    return clients


def validate_agents(agents, clients):
    if not isinstance(agents, list) or any(not isinstance(a, str) or a not in clients for a in agents):
        raise ValueError("Unknown or malformed project agent IDs")
    if len(agents) != len(set(agents)):
        raise ValueError("Duplicate project agent IDs")
    return agents


def snapshot(project, clients):
    path = path_in(project, ".agent/bootstrap.yml")
    if not path.exists():
        return [], {}, {"selected": [], "workflow": "none", "config_sha256": None}
    if not path.is_file():
        raise ValueError("Bootstrap configuration must be a regular file")
    data = read_bytes(path)
    lines = data.decode("utf-8").splitlines(keepends=True)
    entries = mapping(lines)
    selected = []
    if "project_agents" in entries:
        block = entries["project_agents"]
        value = (HEADER.fullmatch(block[0])[3] or "").strip()
        if any(line.strip() and not line.lstrip().startswith("#") for line in block[1:]):
            raise ValueError("project_agents requires a JSON-compatible YAML flow list")
        try:
            selected, end = json.JSONDecoder().raw_decode(value)
        except ValueError:
            raise ValueError("project_agents requires a JSON-compatible YAML flow list") from None
        if value[end:].strip() and not value[end:].lstrip().startswith("#"):
            raise ValueError("Malformed project_agents list")
        validate_agents(selected, clients)
    workflow = scalar(entries["workflow_id"]) if "workflow_id" in entries else "none"
    if workflow not in {"none", *WORKFLOWS}:
        raise ValueError("Unknown recorded workflow_id")
    return lines, entries, {"selected": selected, "workflow": workflow, "config_sha256": hashlib.sha256(data).hexdigest()}


def metadata(project, clients):
    """Read restoration selections only; never inspect Skill files or runtimes."""
    _, entries, result = snapshot(project, clients)
    for name, keys in {
        "curated_skills": ("components", "curated_skills"),
        "workflow_pack": ("components", "workflow_pack"),
        "understand_anything": ("integrations", "understand_anything", "installation"),
        "superpowers": ("superpowers", "installation"),
    }.items():
        level = entries
        for depth, key in enumerate(keys[:-1], 1):
            level = child(level[key], depth * 2) if key in level else {}
        result[name] = scalar(level[keys[-1]]) if keys[-1] in level else ""
    return result


def git(project, *args, input=None):
    # Inherited Git routing variables must not redirect inspection to another repo.
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(GIT_OPTIONAL_LOCKS="0", GIT_TERMINAL_PROMPT="0")
    try:
        result = subprocess.run(["git", "-c", "core.fsmonitor=false", "-C", str(project), *args],
                                env=env, input=input, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=10)
        output = result.stdout.decode("utf-8", errors="replace")
        return result.returncode, output if input is not None else output.strip()
    except (OSError, subprocess.TimeoutExpired):
        return 2, ""


def git_facts(project):
    code, root = git(project, "rev-parse", "--show-toplevel")
    initialized = code == 0 and Path(root).resolve() == project
    if not initialized:
        return {"initialized": False, "branch": None, "head": None, "identity_ready": False, "origin_present": False}
    return {"initialized": True,
            "branch": git(project, "symbolic-ref", "--quiet", "--short", "HEAD")[1] or None,
            "head": git(project, "rev-parse", "--verify", "HEAD")[1] or None,
            "identity_ready": all(git(project, "config", "--get", key)[1] for key in ("user.name", "user.email")),
            "origin_present": git(project, "remote", "get-url", "origin")[0] == 0}


def skill_names(project, root, only=None):
    directory = path_in(project, root)
    names, errors, runtime = [], [], []
    if not directory.is_dir():
        return names, errors, runtime
    entries = (directory / name for name in only) if only is not None else directory.iterdir()
    for entry in sorted(entries):
        if entry.name.startswith(".") or not IDENTIFIER.fullmatch(entry.name):
            continue
        relative = f"{root}/{entry.name}/SKILL.md"
        try:
            resolved = path_in(project, relative, links=True).resolve()
            if resolved.is_relative_to(project / ".agent/runtime"):
                ua = project / ".agent/runtime/understand-anything/repo/understand-anything-plugin/skills"
                if not resolved.is_relative_to(ua):
                    raise ValueError(f"Unsupported runtime-backed skill: {root}/{entry.name}")
                runtime.append(entry.name)
            if text(project, relative, links=True).strip():
                names.append(entry.name)
        except (OSError, ValueError, RuntimeError):
            errors.append(f"Unsafe or unreadable skill entry: {root}/{entry.name}")
    return names, errors, runtime


def bmad_installed(project):
    """Check bounded manifest/help markers, not runtime execution or every module."""
    try:
        raw = text(project, "_bmad/_config/manifest.yaml")
        entries = mapping(raw.splitlines(keepends=True))
        installation = child(entries["installation"], 2)
        version = scalar(installation["version"])
        if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[\w.-]+)?", version):
            return False
        # Upstream emits either scalar module entries or records with name fields.
        modules = entries["modules"][1:]
        if not any(re.fullmatch(r"\s+- (?:name: )?['\"]?core['\"]?\s*", line) for line in modules):
            return False
        if not path_in(project, "_bmad/core").is_dir():
            return False
        reader = csv.DictReader(io.StringIO(text(project, "_bmad/_config/bmad-help.csv")), strict=True)
        fields = reader.fieldnames or []
        rows = list(reader)
        return (len(fields) == len(set(fields)) and {"module", "skill"}.issubset(fields)
                and bool(rows) and all(None not in row and all(v is not None for v in row.values()) for row in rows)
                and any(row["skill"] == "bmad-help" for row in rows))
    except (OSError, ValueError, KeyError, csv.Error, RuntimeError):
        return False


def installed_workflows(project, scans):
    names = {name for scan in scans.values() for name in scan[0]}
    return [workflow for workflow, entry in WORKFLOWS.items()
            if entry in names and (workflow != "bmad" or bmad_installed(project))]


def ua_verified(project):
    """Require the pinned HEAD, installer compatibility patch, and all project links."""
    try:
        integration = SOURCE / "integrations/understand-anything"
        entries = mapping((integration / "integration.yml").read_text().splitlines(keepends=True))
        pin = child(entries["known_good"], 2)
        expected = scalar(pin["ref"])
        installation = child(entries["installation"], 2)
        runtime = path_in(project, scalar(installation["runtime_path"]))
        skills_root = scalar(installation["skills_path"])
        path_in(project, skills_root)
        if not re.fullmatch(r"[0-9a-f]{40}", expected) or not runtime.is_dir():
            return None
        if not path_in(project, runtime.relative_to(project) / ".git").is_dir():
            return None
        facts = git_facts(runtime)
        if not facts["initialized"] or facts["head"] != expected:
            return None
        patches = installation["local_patches"]
        if (HEADER.fullmatch(patches[0])[3] or "").strip():
            return None
        required = [line for line in patches[1:] if line.strip() and not line.lstrip().startswith("#")]
        if not required:
            return None
        for line in required:
            match = re.fullmatch(r"    - (\S+)\s*", line)
            if not match:
                return None
            patch = path_in(integration, match[1])
            if not patch.is_file() or git(runtime, "apply", "--unidiff-zero", "--reverse", "--check", str(patch))[0] != 0:
                return None
        upstream = path_in(project, runtime.relative_to(project) / "understand-anything-plugin/skills")
        names = [p.name for p in upstream.iterdir() if p.is_dir() and (p / "SKILL.md").is_file()]
        if not names or "understand" not in names:
            return None
        for name in names:
            source = upstream / name
            link = project / skills_root / name
            expected_link = os.path.relpath(source, link.parent)
            if not link.is_symlink() or os.readlink(link) != expected_link:
                return None
            if not text(project, link.relative_to(project) / "SKILL.md", links=True).strip():
                return None
        return {"installation": "install", "scope": "project", "upstream": scalar(entries["upstream"]),
                "tag": scalar(pin["tag"]), "ref": expected}
    except (OSError, ValueError, KeyError, RuntimeError):
        return None


def save(project, clients, agents, workflow, expect):
    lines, entries, current = snapshot(project, clients)
    if not lines:
        raise ValueError("Bootstrap configuration must exist before saving selections")
    if (current["config_sha256"] or "missing") != expect:
        raise ValueError("Bootstrap configuration changed; inspect again before saving")
    roots = {record["project_path"] for record in clients.values()}
    scans = {root: skill_names(project, root) for root in roots}
    installed = installed_workflows(project, scans)
    desired = [f"project_agents: {json.dumps(agents)}\n", f"workflow_id: {workflow}\n"]
    components = []
    ordinary = {p.name for p in (SOURCE / "skills").iterdir() if (p / "SKILL.md").is_file()}
    if any(ordinary.intersection(scan[0]) for scan in scans.values()):
        components.append("  curated_skills: install\n")
    pack = workflow if workflow in installed else (installed[0] if len(installed) == 1 else None)
    if pack:
        components.append(f"  workflow_pack: {pack}\n")
    if components:
        if "components" in entries:
            child(entries["components"], 2)
        desired.extend(["components:\n", *components])
    verified = ua_verified(project)
    if verified:
        if "integrations" in entries:
            integrations = child(entries["integrations"], 2)
            if "understand_anything" in integrations:
                child(integrations["understand_anything"], 4)
        desired.extend(["integrations:\n", "  understand_anything:\n"])
        desired.extend(f"    {key}: {value}\n" for key, value in verified.items())
    # A Superpowers entry proves availability, not its source/ref. Preserve it.
    output = "".join(merger.merge(lines, desired)).encode("utf-8")
    path = path_in(project, ".agent/bootstrap.yml")
    mode = stat.S_IMODE(path.stat().st_mode)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix=".bootstrap-", dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            os.fchmod(stream.fileno(), mode)
            stream.write(output)
            stream.flush()
            os.fsync(stream.fileno())
        # Recheck immediately before atomic replacement; never overwrite a stale snapshot.
        if snapshot(project, clients)[2]["config_sha256"] != expect:
            raise ValueError("Bootstrap configuration changed; inspect again before saving")
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return {"saved": True, "config_sha256": hashlib.sha256(output).hexdigest()}


def git_dependencies(project, relative):
    """Git cannot inspect symlink descendants: check each link and its local source."""
    path = path_in(project, relative, links=True)
    current = project
    parts = Path(relative).parts
    for index, part in enumerate(parts):
        current /= part
        if current.is_symlink():
            target = Path(os.path.normpath(current.parent / os.readlink(current) / Path(*parts[index + 1:])))
            return {current.relative_to(project).as_posix()} | git_dependencies(project, target.relative_to(project))
    dependencies = {path.relative_to(project).as_posix()}
    if path.name == "SKILL.md":
        dependencies.add(path.parent.relative_to(project).as_posix())
    return dependencies


def readiness(project, clients, agents, workflow):
    issues, notes, results = [], [], []
    policies = {"AGENTS.md", ".agent/policies/git.md", ".agent/bootstrap.yml", ".gitignore"}
    critical = {relative: set() for relative in policies}
    recorded = snapshot(project, clients)[2]
    config_present = recorded["config_sha256"] is not None
    if not config_present:
        issues.append("Project .agent/bootstrap.yml is missing")
    policy_ready = True
    for relative, reference in [("AGENTS.md", ".agent/policies/git.md"), (".agent/policies/git.md", None)]:
        try:
            content = text(project, relative)
            if not content.strip() or (reference and reference not in content):
                raise ValueError("Missing policy or reference")
        except (OSError, ValueError, RuntimeError):
            issues.append(f"Missing, unsafe, or incomplete policy: {relative}")
            policy_ready = False
    if "claude-code" in agents:
        policies.add("CLAUDE.md")
        critical["CLAUDE.md"] = {"claude-code"}
        try:
            if "AGENTS.md" not in text(project, "CLAUDE.md"):
                raise ValueError("Missing shared-policy reference")
        except (OSError, ValueError, RuntimeError):
            issues.append("CLAUDE.md must safely reference AGENTS.md")
            policy_ready = False
    scans = {}
    ua_runtime = project / ".agent/runtime/understand-anything/repo"
    ua_present = ua_runtime.exists() or ua_runtime.is_symlink()
    ua_valid = ua_verified(project) if ua_present else None
    if ua_present and not ua_valid:
        issues.append("Present Understand Anything runtime is invalid: pinned HEAD, compatibility patch, or project links failed verification")
    for agent in agents:
        root = clients[agent]["project_path"]
        if root not in scans:
            try:
                scans[root] = skill_names(project, root)
            except (OSError, ValueError, RuntimeError):
                scans[root] = ([], [f"Unsafe skill directory: {root}"], [])
        names, errors, runtime = scans[root]
        for name in names:
            # Verified managed runtimes/links are intentionally restored, not tracked.
            if name not in runtime:
                for relative in (f"{root}/{name}", f"{root}/{name}/SKILL.md"):
                    critical.setdefault(relative, set()).add(agent)
        client_issues = [f"{agent}: {error}" for error in errors]
        adapter_issues = []
        if workflow != "none":
            required = WORKFLOWS[workflow]
            if required not in names:
                adapter_issues.append(f"{agent}: missing {root}/{required}/SKILL.md")
            if workflow == "bmad" and not bmad_installed(project):
                client_issues.append(f"{agent}: BMAD manifest/help markers are incomplete")
            if workflow == "bmad" and agent == "universal":
                adapter_issues.append("Universal + BMAD is unsupported")
            if workflow == "bmad" and clients[agent].get("bmad_commands"):
                pointer = f"{clients[agent]['bmad_commands']}/bmad-help.md"
                try:
                    if "@skills/bmad-help" not in text(project, pointer, links=True).splitlines():
                        adapter_issues.append(f"{agent}: missing BMAD command pointer {pointer}")
                    critical.setdefault(pointer, set()).add(agent)
                except (OSError, ValueError, RuntimeError):
                    adapter_issues.append(f"{agent}: unsafe BMAD command pointer {pointer}")
        if runtime:
            notes.append(f"{agent}: runtime-backed skills found; session loading is unverified")
            if not ua_valid:
                client_issues.append(f"{agent}: Understand Anything runtime-backed skills are not verified")
        client_issues.extend(adapter_issues)
        issues.extend(client_issues)
        results.append({"id": agent, "path": root, "skills": names, "ready": not client_issues,
                        "adapters_ready": not adapter_issues})
    installed = workflow == "none" or workflow in installed_workflows(project, scans)
    if workflow == "bmad":
        for relative in ("_bmad/_config/manifest.yaml", "_bmad/_config/bmad-help.csv"):
            critical[relative] = set(agents)
    if not installed:
        issues.append(f"Workflow artifacts are incomplete: {workflow}")
    facts = git_facts(project)
    if not facts["initialized"]:
        issues.append("Git must be initialized at the project root, not only a parent directory")
    if not facts["identity_ready"]:
        notes.append("Git user.name/user.email must be configured before committing; no global identity was changed")
    try:
        if not path_in(project, ".gitignore").is_file():
            issues.append("Project .gitignore is missing")
    except (OSError, ValueError, RuntimeError):
        issues.append("Project .gitignore is unsafe")
    if facts["initialized"]:
        dependencies, blocked = {}, set()
        for relative, owners in critical.items():
            try:
                path = path_in(project, relative, links=relative not in policies)
                if path.exists():
                    for dependency in git_dependencies(project, relative):
                        dependencies.setdefault(dependency, set()).update(owners)
            except (OSError, ValueError, RuntimeError):
                issues.append(f"Unsafe critical project entry: {relative}")
                blocked.update(owners)
        if dependencies:
            code, output = git(project, "check-ignore", "--no-index", "--stdin", "-z",
                               input="".join(relative + "\0" for relative in sorted(dependencies)).encode("utf-8"))
            if code not in (0, 1):
                issues.append("Git ignore inspection failed; critical entries could not be verified")
                blocked.update(agents)
            else:
                for relative in filter(None, output.split("\0")):
                    owners = dependencies[relative]
                    suffix = f" (clients: {', '.join(sorted(owners))})" if owners else ""
                    issues.append(f"Critical project entry is ignored by Git: {relative}{suffix}")
                    blocked.update(owners)
        for result in results:
            if result["id"] in blocked:
                result["ready"] = False
    if workflow == "superpowers":
        notes.append("Superpowers entry availability does not verify its source or pinned version")
    notes.append("Local files do not verify agent session loading, remote CI, or review protection")
    return {"ready": not issues, "issues": list(dict.fromkeys(issues)), "clients": results, "git": facts,
            "workflow": {"id": workflow, "installed": installed}, "policy_ready": policy_ready,
            "config_present": config_present, "persisted_workflow": recorded["workflow"], "notes": list(dict.fromkeys(notes))}


def links_plan(project, clients, agents):
    """Offer only missing client entries, preserving all existing Skill content."""
    sources = {}
    for root in sorted({record["project_path"] for record in clients.values()}):
        names, errors, _ = skill_names(project, root)
        if errors:
            raise ValueError("Resolve unsafe existing Skills before adding client entries")
        for name in names:
            # BMAD tool adapters include manifest/command-pointer semantics;
            # do not substitute generic links for its official installer.
            if name.startswith("bmad-"):
                continue
            source = path_in(project, f"{root}/{name}", links=True).resolve()
            sources.setdefault(name, set()).add(source)
    links, conflicts = [], []
    for root in sorted({clients[agent]["project_path"] for agent in agents}):
        path_in(project, root)
        for name, candidates in sorted(sources.items()):
            destination = path_in(project, f"{root}/{name}", links=True)
            if destination.exists() or destination.is_symlink():
                continue
            if len(candidates) != 1:
                conflicts.append(f"Multiple different project sources for {name}; no link chosen")
                continue
            source = next(iter(candidates))
            links.append({"path": destination.relative_to(project).as_posix(),
                          "target": os.path.relpath(source, destination.parent)})
    report = {"project": str(project), "links": links, "conflicts": conflicts}
    report["token"] = hashlib.sha256(json.dumps(report, sort_keys=True).encode()).hexdigest()
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("clients")
    commands.add_parser("metadata")
    link_command = commands.add_parser("links")
    link_command.add_argument("--agents", nargs="+", required=True)
    link_command.add_argument("--apply", action="store_true")
    link_command.add_argument("--expect")
    for name in ("save", "readiness"):
        command = commands.add_parser(name)
        command.add_argument("--agents", nargs="+", required=True)
        command.add_argument("--workflow", choices=["none", *WORKFLOWS], required=True)
        if name == "save":
            command.add_argument("--expect", required=True)
    args = parser.parse_args()
    try:
        project = Path(args.project).resolve()
        if project.exists() and not project.is_dir():
            raise ValueError("Project must be a directory")
        if args.command == "save" and not project.is_dir():
            raise ValueError("Project must exist before saving configuration")
        clients = clients_manifest()
        if args.command == "clients":
            result = snapshot(project, clients)[2]
            scans = {}
            for record in clients.values():
                root = record["project_path"]
                if root not in scans:
                    scans[root] = skill_names(project, root, only=WORKFLOWS.values())
            result["detected"] = [agent for agent, record in clients.items() if path_in(project, record["project_path"]).is_dir()]
            result["installed_workflows"] = installed_workflows(project, scans)
        elif args.command == "metadata":
            result = metadata(project, clients)
        elif args.command == "links":
            validate_agents(args.agents, clients)
            result = links_plan(project, clients, args.agents)
            if args.apply:
                if args.expect != result["token"]:
                    raise ValueError("Client entry preview changed; inspect a fresh preview")
                for item in result["links"]:
                    path_in(project, item["path"])
                for item in result["links"]:
                    destination = path_in(project, item["path"])
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.symlink_to(item["target"])
        else:
            validate_agents(args.agents, clients)
            # Both commands validate the snapshot before inspecting artifacts.
            result = (save(project, clients, args.agents, args.workflow, args.expect) if args.command == "save"
                      else readiness(project, clients, args.agents, args.workflow))
        print(json.dumps(result))
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        # Deliberately avoid file contents, Git stderr, or config values in diagnostics.
        print(f"onboarding-project: {error}" if isinstance(error, ValueError) else "onboarding-project: unable to inspect local project metadata", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
