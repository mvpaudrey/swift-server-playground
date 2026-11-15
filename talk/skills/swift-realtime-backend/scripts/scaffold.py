#!/usr/bin/env python3
"""Scaffold a real-time Swift backend (Vapor + grpc-swift 2.x) from the
templates bundled with this skill.

Usage:
    python3 scaffold.py --project MyLiveOrdersServer --entity Order --entity-plural Orders --out ./MyLiveOrdersServer

--entity-plural is optional; if omitted, an "s" is appended to --entity.
"""
import argparse
import shutil
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
TEMPLATES_DIR = SKILL_DIR / "assets" / "templates"


def substitute(text: str, replacements: dict[str, str]) -> str:
    for key, value in replacements.items():
        text = text.replace(key, value)
    return text


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True, help="Package/project name, e.g. LiveOrdersServer")
    parser.add_argument("--entity", required=True, help="Singular entity name, capitalized, e.g. Order")
    parser.add_argument("--entity-plural", default=None, help="Plural entity name, capitalized, e.g. Orders (default: entity + 's')")
    parser.add_argument("--out", required=True, help="Output directory (must not already exist)")
    args = parser.parse_args()

    entity = args.entity
    entity_plural = args.entity_plural or (entity + "s")
    entity_lower = entity[0].lower() + entity[1:]

    replacements = {
        "{{PROJECT_NAME}}": args.project,
        "{{ENTITY_PLURAL}}": entity_plural,
        "{{ENTITY_LOWER}}": entity_lower,
        "{{ENTITY}}": entity,
    }

    out = Path(args.out)
    if out.exists():
        raise SystemExit(f"Output directory {out} already exists — pick a fresh path.")

    # (relative output path, template filename)
    layout = [
        ("Package.swift", "Package.swift.template"),
        ("README.md", "README.md.template"),
        (f"Sources/App/Protos/{entity_lower}.proto", "entity.proto.template"),
        ("Sources/App/configure.swift", "configure.swift.template"),
        ("Sources/App/Services/CacheService.swift", "CacheService.swift.template"),
        (f"Sources/App/Services/{entity}Broadcaster.swift", "Broadcaster.swift.template"),
        ("Sources/App/Services/AdaptivePoller.swift", "AdaptivePoller.swift.template"),
        ("Sources/Run/main.swift", "main.swift.template"),
        ("Tests/AppTests/AppTests.swift", "AppTests.swift.template"),
    ]

    for rel_path, template_name in layout:
        template_path = TEMPLATES_DIR / template_name
        dest_path = out / rel_path
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        content = substitute(template_path.read_text(), replacements)
        dest_path.write_text(content)

    print(f"Scaffolded {args.project} at {out}")
    print(f"  entity: {entity} / {entity_plural}")
    print("Next: cd into it, run `swift build`, then follow README.md's 'Next steps'.")


if __name__ == "__main__":
    main()
