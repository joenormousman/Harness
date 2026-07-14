#!/usr/bin/env python3
"""
Salesforce metadata dependency resolver.

Given a seed set of metadata items, walk both directions of the reference graph
in a Salesforce DX source tree and emit an expanded package.xml plus a JSON
rationale trail explaining why each item was included.

Supported metadata types (initial slice):
  - CustomObject
  - CustomField
  - ValidationRule
  - PermissionSet
  - Profile

The value here isn't a full walk of Salesforce's ~250 metadata types. It's
demonstrating the *asymmetric* nature of Salesforce metadata references
(a ValidationRule knows which fields it uses; a CustomField does not know
which ValidationRules or PermissionSets touch it) and showing what the
missing intelligence layer would look like in a real deployment pipeline.

Usage:
  python resolve-dependencies.py \\
    --source-dir force-app \\
    --input resolve-input.json \\
    --output package-expanded.xml \\
    --rationale rationale.json \\
    --api-version 61.0
"""

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Set, Tuple

MD_NS = "http://soap.sforce.com/2006/04/metadata"
NS = {"sf": MD_NS}


@dataclass(frozen=True)
class MetadataRef:
    type: str
    name: str

    def key(self) -> str:
        return f"{self.type}:{self.name}"


@dataclass
class RepoIndex:
    """Maps every discoverable metadata item to its source file."""

    files: Dict[str, Path] = field(default_factory=dict)

    def add(self, ref: MetadataRef, path: Path) -> None:
        self.files[ref.key()] = path

    def path_for(self, ref: MetadataRef) -> Optional[Path]:
        return self.files.get(ref.key())

    def all_of_type(self, type_name: str) -> List[MetadataRef]:
        prefix = f"{type_name}:"
        return [
            MetadataRef(type=type_name, name=key[len(prefix):])
            for key in self.files
            if key.startswith(prefix)
        ]


def build_index(source_dir: Path) -> RepoIndex:
    """Scan the source tree once and index every metadata file we recognize."""
    index = RepoIndex()

    objects_root = source_dir / "main" / "default" / "objects"
    if objects_root.is_dir():
        for obj_dir in sorted(objects_root.iterdir()):
            if not obj_dir.is_dir():
                continue
            obj_name = obj_dir.name

            obj_file = obj_dir / f"{obj_name}.object-meta.xml"
            if obj_file.is_file():
                index.add(MetadataRef("CustomObject", obj_name), obj_file)

            fields_dir = obj_dir / "fields"
            if fields_dir.is_dir():
                for field_file in sorted(fields_dir.glob("*.field-meta.xml")):
                    field_name = field_file.name.replace(".field-meta.xml", "")
                    full = f"{obj_name}.{field_name}"
                    index.add(MetadataRef("CustomField", full), field_file)

            vr_dir = obj_dir / "validationRules"
            if vr_dir.is_dir():
                for vr_file in sorted(vr_dir.glob("*.validationRule-meta.xml")):
                    vr_name = vr_file.name.replace(".validationRule-meta.xml", "")
                    full = f"{obj_name}.{vr_name}"
                    index.add(MetadataRef("ValidationRule", full), vr_file)

    permsets_root = source_dir / "main" / "default" / "permissionsets"
    if permsets_root.is_dir():
        for ps_file in sorted(permsets_root.glob("*.permissionset-meta.xml")):
            ps_name = ps_file.name.replace(".permissionset-meta.xml", "")
            index.add(MetadataRef("PermissionSet", ps_name), ps_file)

    profiles_root = source_dir / "main" / "default" / "profiles"
    if profiles_root.is_dir():
        for prof_file in sorted(profiles_root.glob("*.profile-meta.xml")):
            prof_name = prof_file.name.replace(".profile-meta.xml", "")
            index.add(MetadataRef("Profile", prof_name), prof_file)

    return index


def parse_xml(path: Path) -> Optional[ET.Element]:
    try:
        return ET.parse(path).getroot()
    except ET.ParseError as exc:
        print(f"warn: cannot parse {path}: {exc}", file=sys.stderr)
        return None


def field_refs_in_formula(formula: str) -> Set[str]:
    """Regex-extract field references from a Salesforce formula string.

    Matches Object__c.Field__c and bare Field__c. Not a full formula parser —
    a full parser would need to handle function calls, cross-object references,
    and relationship traversal ($Profile, $User.Field__c, etc.). Explicitly
    called out as a demo-scope limitation.
    """
    tokens: Set[str] = set()
    tokens.update(re.findall(r"\b([A-Za-z0-9_]+__c\.[A-Za-z0-9_]+__c)\b", formula))
    tokens.update(re.findall(r"(?<![.\w])([A-Za-z0-9_]+__c)\b", formula))
    return tokens


def forward_refs(ref: MetadataRef, index: RepoIndex) -> List[Tuple[MetadataRef, str]]:
    """Items that `ref` explicitly references (based on its own file contents)."""
    out: List[Tuple[MetadataRef, str]] = []
    path = index.path_for(ref)
    if not path:
        return out
    root = parse_xml(path)
    if root is None:
        return out

    if ref.type == "CustomField":
        object_name = ref.name.split(".")[0]
        if object_name.endswith("__c"):
            out.append((MetadataRef("CustomObject", object_name), f"parent object of field {ref.name}"))

    elif ref.type == "ValidationRule":
        object_name = ref.name.split(".")[0]
        if object_name.endswith("__c"):
            out.append((MetadataRef("CustomObject", object_name), f"parent object of validation rule {ref.name}"))

        formula_elem = root.find("sf:errorConditionFormula", NS)
        if formula_elem is not None and formula_elem.text:
            for token in field_refs_in_formula(formula_elem.text):
                if "." in token:
                    field_full = token
                else:
                    field_full = f"{object_name}.{token}"
                candidate = MetadataRef("CustomField", field_full)
                if index.path_for(candidate):
                    out.append((candidate, f"referenced in {ref.name} errorConditionFormula"))

    elif ref.type == "PermissionSet" or ref.type == "Profile":
        for obj_perm in root.findall("sf:objectPermissions", NS):
            obj_elem = obj_perm.find("sf:object", NS)
            if obj_elem is not None and obj_elem.text and obj_elem.text.endswith("__c"):
                out.append((
                    MetadataRef("CustomObject", obj_elem.text),
                    f"objectPermissions in {ref.type} {ref.name}",
                ))
        for field_perm in root.findall("sf:fieldPermissions", NS):
            field_elem = field_perm.find("sf:field", NS)
            if field_elem is not None and field_elem.text and "." in field_elem.text:
                obj_name = field_elem.text.split(".")[0]
                if obj_name.endswith("__c"):
                    out.append((
                        MetadataRef("CustomField", field_elem.text),
                        f"fieldPermissions in {ref.type} {ref.name}",
                    ))

    return out


def inverse_refs(ref: MetadataRef, index: RepoIndex) -> List[Tuple[MetadataRef, str]]:
    """Items in the repo that reference `ref` (asymmetric lookups).

    This is the hard part of Salesforce metadata: the referenced item does
    not know about its referrers. We have to scan sibling files. In a real
    engine you'd maintain a persistent inverted index; here we do the scan
    per query because the source tree is small.
    """
    out: List[Tuple[MetadataRef, str]] = []

    if ref.type == "CustomField":
        for vr in index.all_of_type("ValidationRule"):
            vr_path = index.path_for(vr)
            if not vr_path:
                continue
            root = parse_xml(vr_path)
            if root is None:
                continue
            formula_elem = root.find("sf:errorConditionFormula", NS)
            if formula_elem is None or not formula_elem.text:
                continue
            object_name = vr.name.split(".")[0]
            tokens = field_refs_in_formula(formula_elem.text)
            field_full_short = ref.name.split(".")[-1]
            for token in tokens:
                if token == ref.name or (
                    "." not in token
                    and token == field_full_short
                    and vr.name.split(".")[0] == ref.name.split(".")[0]
                ):
                    out.append((vr, f"references {ref.name} in errorConditionFormula"))
                    break

        for ps in index.all_of_type("PermissionSet") + index.all_of_type("Profile"):
            ps_path = index.path_for(ps)
            if not ps_path:
                continue
            root = parse_xml(ps_path)
            if root is None:
                continue
            for field_perm in root.findall("sf:fieldPermissions", NS):
                field_elem = field_perm.find("sf:field", NS)
                if field_elem is not None and field_elem.text == ref.name:
                    out.append((ps, f"grants fieldPermissions on {ref.name}"))
                    break

    elif ref.type == "CustomObject":
        for candidate_type in ("CustomField", "ValidationRule"):
            for item in index.all_of_type(candidate_type):
                if item.name.startswith(f"{ref.name}."):
                    out.append((item, f"lives on object {ref.name}"))

        for ps in index.all_of_type("PermissionSet") + index.all_of_type("Profile"):
            ps_path = index.path_for(ps)
            if not ps_path:
                continue
            root = parse_xml(ps_path)
            if root is None:
                continue
            for obj_perm in root.findall("sf:objectPermissions", NS):
                obj_elem = obj_perm.find("sf:object", NS)
                if obj_elem is not None and obj_elem.text == ref.name:
                    out.append((ps, f"grants objectPermissions on {ref.name}"))
                    break

    return out


def resolve(
    seeds: Iterable[MetadataRef],
    index: RepoIndex,
    include_inverse: bool = True,
) -> Tuple[Set[MetadataRef], Dict[str, List[str]]]:
    """BFS over the dependency graph. Returns the resolved set + rationale trail."""
    resolved: Set[MetadataRef] = set()
    rationale: Dict[str, List[str]] = defaultdict(list)
    queue: List[Tuple[MetadataRef, str]] = [(s, "seed (user input)") for s in seeds]

    while queue:
        current, reason = queue.pop(0)
        if current in resolved:
            rationale[current.key()].append(reason)
            continue

        if not index.path_for(current):
            rationale[current.key()].append(
                f"{reason} — WARNING: not present in source tree, skipping (would need to exist in target org)"
            )
            continue

        resolved.add(current)
        rationale[current.key()].append(reason)

        for dep, why in forward_refs(current, index):
            if dep not in resolved:
                queue.append((dep, why))

        if include_inverse:
            for dep, why in inverse_refs(current, index):
                if dep not in resolved:
                    queue.append((dep, why))

    return resolved, dict(rationale)


def emit_package_xml(resolved: Set[MetadataRef], api_version: str) -> str:
    grouped: Dict[str, List[str]] = defaultdict(list)
    for ref in resolved:
        grouped[ref.type].append(ref.name)

    lines: List[str] = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<Package xmlns="{MD_NS}">',
    ]
    for type_name in sorted(grouped):
        lines.append("    <types>")
        for member in sorted(grouped[type_name]):
            lines.append(f"        <members>{member}</members>")
        lines.append(f"        <name>{type_name}</name>")
        lines.append("    </types>")
    lines.append(f"    <version>{api_version}</version>")
    lines.append("</Package>")
    lines.append("")
    return "\n".join(lines)


def load_seeds(input_path: Path) -> Tuple[List[MetadataRef], str]:
    data = json.loads(input_path.read_text(encoding="utf-8"))
    api_version = str(data.get("apiVersion", "61.0"))
    seeds: List[MetadataRef] = []
    for entry in data.get("seeds", []):
        seeds.append(MetadataRef(type=entry["type"], name=entry["name"]))
    return seeds, api_version


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--rationale", type=Path, default=None)
    parser.add_argument("--api-version", default=None)
    parser.add_argument(
        "--no-inverse",
        action="store_true",
        help="Walk only forward references (skip 'what references me' lookups).",
    )
    args = parser.parse_args()

    if not args.source_dir.is_dir():
        print(f"error: source-dir {args.source_dir} is not a directory", file=sys.stderr)
        return 2

    seeds, api_from_input = load_seeds(args.input)
    api_version = args.api_version or api_from_input

    print(f"Indexing metadata under {args.source_dir}...", file=sys.stderr)
    index = build_index(args.source_dir)
    print(f"  indexed {len(index.files)} items", file=sys.stderr)

    print(f"Resolving from {len(seeds)} seed(s)...", file=sys.stderr)
    for seed in seeds:
        print(f"  seed: {seed.type} {seed.name}", file=sys.stderr)

    resolved, rationale = resolve(seeds, index, include_inverse=not args.no_inverse)

    print(f"Expanded to {len(resolved)} items:", file=sys.stderr)
    for ref in sorted(resolved, key=lambda r: (r.type, r.name)):
        print(f"  {ref.type:20s} {ref.name}", file=sys.stderr)

    args.output.write_text(emit_package_xml(resolved, api_version), encoding="utf-8")
    print(f"Wrote {args.output}", file=sys.stderr)

    if args.rationale:
        payload = {
            "apiVersion": api_version,
            "seedCount": len(seeds),
            "resolvedCount": len(resolved),
            "trail": rationale,
        }
        args.rationale.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        print(f"Wrote {args.rationale}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
