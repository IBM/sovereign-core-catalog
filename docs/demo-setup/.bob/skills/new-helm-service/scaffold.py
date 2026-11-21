#!/usr/bin/env python3
"""
scaffold.py — scaffold the platform wrapper files for a new Helm service.

Creates everything under services/<name>helm/<version>/ EXCEPT the chart itself.
The Helm chart (chart/) is imported separately by the engineer (helm pull or manual copy).

Usage:
    python3 .bob/skills/new-helm-service/scaffold.py \\
        --name    <name>     # bare service name, lowercase alpha [a-z]+, ≤22 chars
                             # 'helm' suffix is added automatically → <name>helm
        --image   <ref>      # full upstream image ref, e.g. docker.io/osixia/openldap:2.6.15-alpha
        --display <label>    # human-readable name, e.g. "OpenLDAP Directory"
        [--description ...]  # one-line description (auto-generated if omitted)
        [--version v1]       # service version directory (default: v1)

Requires: jinja2  (pip install jinja2)
"""
import argparse
import re
import shutil
import sys
from pathlib import Path

try:
    from jinja2 import Environment, FileSystemLoader, StrictUndefined
except ImportError:
    sys.exit("ERROR: jinja2 is required — run: pip install jinja2")


TEMPLATES_DIR = Path(__file__).parent / "templates"


def parse_image(ref: str) -> dict:
    """Split a full image reference into its components."""
    m = re.match(r'^([^/]+)/(.+?)(?::([^:]+))?$', ref)
    if not m:
        sys.exit(
            f"ERROR: cannot parse image reference {ref!r}\n"
            "Expected format: <registry>/<repository>:<tag>\n"
            "Example:         docker.io/osixia/openldap:2.6.15-alpha"
        )
    registry, repository, tag = m.group(1), m.group(2), m.group(3) or "latest"
    return {
        "upstream_registry":   registry,
        "upstream_repository": repository,
        "tag":                 tag,
        "image_name":          repository.rsplit("/", 1)[-1],
        "byop_repository":     "byop/" + repository.rsplit("/", 1)[-1],
        "source_ref":          ref if ":" in ref else f"{ref}:{tag}",
    }


def validate_name(name: str) -> None:
    if not re.match(r'^[a-z]+$', name):
        sys.exit(f"ERROR: name '{name}' must be lowercase alphabetic only [a-z]+")
    if len(name) > 22:
        sys.exit(f"ERROR: name '{name}' is {len(name)} chars — must be ≤ 22")


def render_j2(env: Environment, template_name: str, ctx: dict) -> str:
    return env.get_template(template_name).render(**ctx)


def render_txt(template_name: str, replacements: dict) -> str:
    """Render a plain-text template using __TOKEN__ substitution (no templating engine)."""
    text = (TEMPLATES_DIR / template_name).read_text()
    for token, value in replacements.items():
        text = text.replace(token, value)
    return text


def write(dest: Path, content: str) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(content)
    print(f"  created  {dest}")


def copy(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(src, dest)
    print(f"  copied   {dest}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Scaffold platform wrapper files for a new Helm service",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--name",        required=True,  help="Bare service name [a-z]+, ≤22 chars (helm suffix added automatically)")
    parser.add_argument("--image",       required=True,  help="Full upstream image ref, e.g. docker.io/osixia/openldap:2.6.15-alpha")
    parser.add_argument("--display",     required=True,  help='Human-readable display name, e.g. "OpenLDAP Directory"')
    parser.add_argument("--description", default=None,   help="One-line description (auto-generated if omitted)")
    parser.add_argument("--version",     default="v1",   help="Service version directory (default: v1)")
    args = parser.parse_args()

    validate_name(args.name)
    img = parse_image(args.image)

    name      = args.name
    helm_name = f"{name}helm"
    display   = args.display
    description = args.description or (
        f"Full-lifecycle {display} service with broker-generated credentials "
        f"stored in Git, deployed with Helm"
    )

    # Context passed to Jinja2 templates
    ctx = {"name": name, "helm_name": helm_name, "display": display,
           "description": description, **img}

    base = Path(f"services/{helm_name}/{args.version}")
    env  = Environment(
        loader=FileSystemLoader(str(TEMPLATES_DIR)),
        undefined=StrictUndefined,
        keep_trailing_newline=True,
    )

    print(f"\n✦  Scaffolding  {base}/\n")

    # Static files — copied verbatim (no substitutions needed)
    copy(TEMPLATES_DIR / "applicationset-helm.yaml.tmpl",
         base / "argocd/applicationset-helm.yaml.tmpl")
    write(base / "catalog/metrics.json", '{"metrics": []}\n')

    # Jinja2-rendered files (output contains NO broker Jinja2 syntax)
    write(base / "catalog/catalog.yaml",       render_j2(env, "catalog.yaml.j2",       ctx))
    write(base / "catalog/schema.json",        render_j2(env, "schema.json.j2",         ctx))
    write(base / "imagesetconfiguration.yaml", render_j2(env, "imagesetconfiguration.yaml.j2", ctx))
    write(base / "values-test.yaml",           render_j2(env, "values-test.yaml.j2",    ctx))

    # Plain-text __TOKEN__ substitution — output contains broker Jinja2 syntax
    # (using a templating engine here would require escaping all {{ }} in the output)
    write(base / "template/values.yaml.tmpl",
          render_txt("values.yaml.tmpl.txt", {
              "__HELM_NAME__":  helm_name,
              "__IMAGE_NAME__": img["image_name"],
              "__TAG__":        img["tag"],
          }))

    # Create chart/ directory stub — the chart itself is imported by the engineer
    (base / "chart/templates").mkdir(parents=True, exist_ok=True)
    print(f"  created  {base}/chart/templates/  (stub — import chart here)")

    total = sum(1 for _ in base.rglob("*") if _.is_file())
    print(f"\n✓  {total} files created under {base}/\n")
    print("Next steps:")
    print(f"  1. Import the Helm chart into {base}/chart/")
    print(f"       helm pull <chart-ref> --untar --untardir {base}/chart/")
    print(f"     or copy chart files manually")
    print(f"  2. Fix chart/values.yaml — split image registry/repository, apply SCC defaults")
    print(f"     (see new-helm-service SKILL.md Steps 5–7)")
    print(f"  3. Extend catalog/schema.json with service-specific parameters")
    print(f"  4. Complete template/values.yaml.tmpl with chart-specific value overrides")
    print(f"  5. Complete values-test.yaml with chart-specific test values")
    print(f"  6. Add image-mapping.txt entry:")
    print(f"       {img['source_ref']}  ->  localhost:5000/{img['byop_repository']}:{img['tag']}")
    print(f"  7. Validate: python3 tools/service-validator --version {args.version} services/{helm_name}")
    print()


if __name__ == "__main__":
    main()
