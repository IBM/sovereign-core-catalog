#!/usr/bin/env python3
"""
scaffold.py - scaffold a NEW Helm service as an umbrella wrapper chart.

Creates services/<name>helm/<version>/ with the unmodified upstream chart vendored in
chart/charts/<subchart>/ and a thin platform wrapper around it. Unlike new-helm-service, the chart is
pulled for you and nothing inside it is ever edited: all platform behaviour (labels, annotations,
imagePullSecrets, fullnameOverride, image registry, storage, OpenShift SCC) is expressed as values
under the `<subchart>:` key.

Usage (run from the byop-sample-repo root):
    python3 .bob/skills/new-helm-wrapper-service/scaffold.py \\
        --name     rabbitmq                              # [a-z]+, <=22 chars; 'helm' suffix is added
        --display  "RabbitMQ Messaging"
        --chart    rabbitmq                              # chart name, or an oci:// reference
        --repo     https://groundhog2k.github.io/helm-charts/   # not needed for oci://
        [--chart-version 2.3.9]                          # default: latest published
        [--image-tag 4.3.6]                              # default: the chart's appVersion
        [--secret password=authentication.password.value ...]   # repeatable, see below
        [--description "..."] [--version v1]

--secret NAME=VALUES.PATH[:PREFIX]
    Exposes an auto-generated credential. Adds an `x-generate` property NAME to catalog/schema.json,
    a `<subchart>.VALUES.PATH: {{ spec.NAME | yaml_safe }}` line to template/values.yaml.tmpl and a test
    value to values-test.yaml. `| yaml_safe` is mandatory for x-generate fields (the charset includes
    '{' and '}', which Helm silently drops).
    With :PREFIX the value is written as a config line, e.g.  --secret password=valkeyConfig:requirepass
    renders   valkeyConfig: |\n    requirepass {{ spec.password | yaml_safe }}   (redis / valkey style).

Requires: python3, PyYAML, Jinja2, helm on PATH   (python3 -m venv /tmp/jv && /tmp/jv/bin/pip install jinja2 pyyaml)
Exit status: 0 scaffolded, 1 scaffolded with warnings that need attention, 2 error (nothing written).
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import yaml
    from jinja2 import Environment, FileSystemLoader, StrictUndefined
except ImportError:
    sys.exit("ERROR: PyYAML and Jinja2 are required - python3 -m venv /tmp/jv && /tmp/jv/bin/pip install jinja2 pyyaml")

SKILLS_DIR = Path(__file__).resolve().parent.parent
SHARED_TEMPLATES = SKILLS_DIR / "new-helm-service" / "templates"  # applicationset + catalog are reused
WARNINGS: list[str] = []

# Platform knobs: first one the vendored templates actually read wins.
WORKLOAD_LABELS = ("customLabels", "commonLabels")
WORKLOAD_ANNOTATIONS = ("customAnnotations", "commonAnnotations")
POD_LABELS = ("podLabels",)
POD_ANNOTATIONS = ("podAnnotations",)
UID_KEYS = ("fsGroup", "supplementalGroups", "runAsUser", "runAsGroup")
SECRET_ANNOTATIONS = ("crn", "account-id", "sub-account-id", "platform")
SERVICE_CTX = {"crn": "crn", "account-id": "account_id", "sub-account-id": "sub_account_id", "platform": "platform"}


sys.stdout.reconfigure(line_buffering=True)  # keep stdout/stderr ordered when piped


def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(2)


def warn(msg: str) -> None:
    WARNINGS.append(msg)
    print(f"  [WARN] {msg}")


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


# ---------------------------------------------------------------------------- upstream chart
def pull_chart(chart: str, repo: str | None, version: str | None, dest: Path) -> Path:
    if shutil.which("helm") is None:
        die("helm not found on PATH")
    cmd = ["helm", "pull", chart, "--untar", "--untardir", str(dest)]
    if not chart.startswith("oci://"):
        if not repo:
            die("--repo is required unless --chart is an oci:// reference")
        cmd += ["--repo", repo]
    if version:
        cmd += ["--version", version]
    proc = run(cmd)
    if proc.returncode != 0:
        die(f"helm pull failed: {proc.stderr.strip()}")
    dirs = [d for d in dest.iterdir() if d.is_dir()]
    if len(dirs) != 1:
        die(f"expected one chart directory after helm pull, found {[d.name for d in dirs]}")
    return dirs[0]


def reads_value(chart_dir: Path, key: str) -> bool:
    """True if any template of the vendored chart (or its helpers) reads .Values.<key>."""
    pat = re.compile(r"\.Values\." + re.escape(key) + r"\b")
    return any(pat.search(p.read_text(errors="ignore")) for p in (chart_dir / "templates").rglob("*") if p.is_file())


def pick_knob(chart_dir: Path, candidates: tuple[str, ...], what: str) -> str | None:
    for k in candidates:
        if reads_value(chart_dir, k):
            return k
    warn(f"upstream chart reads none of {list(candidates)} - {what} cannot be set through values "
         f"(do NOT patch the chart; tell the user)")
    return None


def find_image_blocks(values: dict, prefix: str = "") -> list[tuple[str, dict]]:
    """Dotted path -> block, for every mapping that looks like an image (has repository + tag)."""
    out = []
    for k, v in values.items():
        if isinstance(v, dict):
            path = f"{prefix}.{k}" if prefix else k
            if "repository" in v and "tag" in v:
                out.append((path, v))
            else:
                out.extend(find_image_blocks(v, path))
    return out


def norm_ref(ref: str) -> str:
    ref = ref.strip().strip('"').strip("'")
    ref = re.sub(r"^docker\.io/", "", ref)
    return re.sub(r"^library/", "", ref)


def rendered_images(chart_dir: Path) -> set[str] | None:
    """Image refs rendered with default values (None if the chart needs values to render)."""
    proc = run(["helm", "template", "x", str(chart_dir), "--set", "fullnameOverride=x"])
    if proc.returncode != 0:
        return None
    return {norm_ref(m) for m in re.findall(r"^\s*-?\s*image:\s*(\S+)\s*$", proc.stdout, re.M)}


def block_ref(block: dict, app_version: str, tag: str | None = None) -> tuple[str, str, str]:
    """(registry, repository, tag) for an image block; registry '' when the chart has no registry key."""
    reg = str(block.get("registry") or "")
    repo = str(block.get("repository"))
    t = tag or str(block.get("tag") or "") or app_version
    return reg, repo, t


def full_ref(reg: str, repo: str, tag: str) -> str:
    return f"{reg + '/' if reg else ''}{repo}:{tag}"


def mirror_ref(reg: str, repo: str, tag: str) -> str:
    """Upstream ref in the form used by imagesetconfiguration / image-mapping (docker.io/library/... )."""
    if not reg and "/" in repo and "." in repo.split("/")[0]:
        reg, repo = repo.split("/", 1)
    reg = reg or "docker.io"
    if reg == "docker.io" and "/" not in repo:
        repo = f"library/{repo}"
    return f"{reg}/{repo}:{tag}"


# ---------------------------------------------------------------------------- YAML text helpers
def deep_merge(a: dict, b: dict) -> dict:
    for k, v in b.items():
        if isinstance(v, dict) and isinstance(a.get(k), dict):
            deep_merge(a[k], v)
        else:
            a[k] = v
    return a


def tree_from_path(path: str, leaf: str) -> dict:
    node: dict | str = leaf
    for part in reversed(path.split(".")):
        node = {part: node}
    return node  # type: ignore[return-value]


def emit(tree: dict, indent: int, top: bool = True) -> str:
    """Render a nested dict as YAML; blank line between top-level blocks."""
    lines = []
    for k, v in tree.items():
        if isinstance(v, dict):
            lines.append(f"{' ' * indent}{k}:")
            lines.append(emit(v, indent + 2, top=False))
        elif isinstance(v, str) and "\n__BLOCK__" in v:
            head, body = v.split("\n__BLOCK__", 1)
            lines.append(f"{' ' * indent}{k}: {head}")
            lines.append(f"{' ' * (indent + 2)}{body}")
        else:
            lines.append(f"{' ' * indent}{k}: {v}")
        if top:
            lines.append("")
    return "\n".join(lines).rstrip("\n")


def q(s: str) -> str:
    return json.dumps(s)


def platform_blocks(name: str, sub: str, knobs: dict, test: bool) -> str:
    """fullnameOverride + labels + annotations + pod labels/annotations + imagePullSecrets."""
    def annos(key: str) -> str:
        rows = []
        for a in SECRET_ANNOTATIONS:
            if test:
                val = {"crn": "crn:unknown", "account-id": "local-test", "sub-account-id": "local-test", "platform": "local"}[a]
            else:
                val = f'{{{{ context.{SERVICE_CTX[a]} | default("{ "crn:unknown" if a == "crn" else "unknown" }") | yaml_safe }}}}'
            rows.append(f"    sovcore.byop.ibm.com/{a}: {val}")
        return f"  {key}:\n" + "\n".join(rows)

    def labels(key: str) -> str:
        return f"  {key}:\n    app: {name}\n    service-type: {name}"

    parts = []
    parts.append(f"  fullnameOverride: {name}helm-test" if test else
                 "  # Deterministic resource names: <service_type>-<instance_name> (== ArgoCD release name)\n"
                 "  fullnameOverride: {{ service_type }}-{{ instance_name }}")
    if knobs["labels"]:
        parts.append(labels(knobs["labels"]))
    if knobs["annotations"]:
        parts.append(annos(knobs["annotations"]))
    if knobs["pod_labels"]:
        parts.append(labels(knobs["pod_labels"]))
    if knobs["pod_annotations"]:
        parts.append(annos(knobs["pod_annotations"]))
    if knobs["pull_secrets"]:
        if test:
            parts.append("  imagePullSecrets: []")
        else:
            parts.append("  imagePullSecrets:\n{% if image_pull_secret_name %}\n    - name: {{ image_pull_secret_name }}\n"
                         "{% else %}\n    []\n{% endif %}")
    return "\n\n".join(parts)


# ---------------------------------------------------------------------------- main
def main() -> int:
    ap = argparse.ArgumentParser(description="Scaffold a new Helm service as an umbrella wrapper chart",
                                 formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    ap.add_argument("--name", required=True)
    ap.add_argument("--display", required=True)
    ap.add_argument("--chart", required=True, help="upstream chart name, or an oci:// reference")
    ap.add_argument("--repo", help="upstream Helm repository URL (not needed for oci://)")
    ap.add_argument("--chart-version", help="upstream chart version (default: latest)")
    ap.add_argument("--image-tag", help="application image tag to pin (default: chart appVersion)")
    ap.add_argument("--secret", action="append", default=[], metavar="NAME=VALUES.PATH")
    ap.add_argument("--description")
    ap.add_argument("--version", default="v1", help="service version directory (default: v1)")
    args = ap.parse_args()

    name, helm_name, display = args.name, f"{args.name}helm", args.display
    if not re.fullmatch(r"[a-z]+", name):
        die(f"name '{name}' must be lowercase alphabetic only [a-z]+ (the broker appends 'helm-<uuid>')")
    if len(name) > 22:
        die(f"name '{name}' is {len(name)} chars - must be <= 22")
    base = Path("services") / helm_name / args.version
    if base.exists():
        die(f"{base} already exists - refusing to overwrite (use upgrade-helm-wrapper / migrate-helm-wrapper)")
    secrets: list[tuple[str, str, str]] = []
    for s in args.secret:
        if "=" not in s or not re.fullmatch(r"[a-z][a-z0-9_]*", s.split("=", 1)[0]):
            die(f"--secret must be NAME=values.path with NAME in [a-z][a-z0-9_]*, got '{s}'")
        sname, spath = s.split("=", 1)
        spath, _, sprefix = spath.partition(":")
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_.]*", spath) or (sprefix and not re.fullmatch(r"[A-Za-z0-9_.-]+", sprefix)):
            die(f"--secret path/prefix invalid in '{s}' (use NAME=values.path or NAME=values.path:prefix)")
        secrets.append((sname, spath, sprefix))
    for p in (SHARED_TEMPLATES / "applicationset-helm.yaml.tmpl", SHARED_TEMPLATES / "catalog.yaml.j2"):
        if not p.is_file():
            die(f"shared template missing: {p} (new-helm-service skill must be present)")

    if not args.chart.startswith("oci://") and not args.repo:
        die("--repo is required unless --chart is an oci:// reference")

    tmp = Path(tempfile.mkdtemp(prefix="wrapper-scaffold-"))
    try:
        print(f"\n== pulling {args.chart} {args.chart_version or '(latest)'} ==")
        pulled = pull_chart(args.chart, args.repo, args.chart_version, tmp)
        chart_yaml = yaml.safe_load((pulled / "Chart.yaml").read_text())
        values = yaml.safe_load((pulled / "values.yaml").read_text()) or {}
        sub, sub_version = chart_yaml["name"], str(chart_yaml["version"])
        app_version = str(chart_yaml.get("appVersion") or "")
        print(f"  {sub} {sub_version} (appVersion {app_version})")

        for sname, path, _pfx in secrets:
            if path.split(".")[0] not in values:
                die(f"--secret {sname}: '{path.split('.')[0]}' is not a top-level key of {sub}/values.yaml")

        print("\n== inspecting what the vendored chart reads ==")
        knobs = {
            "labels": pick_knob(pulled, WORKLOAD_LABELS, "workload labels"),
            "annotations": pick_knob(pulled, WORKLOAD_ANNOTATIONS, "workload annotations"),
            "pod_labels": pick_knob(pulled, POD_LABELS, "pod labels"),
            "pod_annotations": pick_knob(pulled, POD_ANNOTATIONS, "pod annotations"),
            "pull_secrets": "imagePullSecrets" if reads_value(pulled, "imagePullSecrets") else None,
        }
        if not knobs["pull_secrets"]:
            warn("upstream chart does not read .Values.imagePullSecrets - pull secrets cannot be set through values")
        if not reads_value(pulled, "fullnameOverride"):
            warn("upstream chart does not read .Values.fullnameOverride - resource names will not be deterministic")
        has_storage = isinstance(values.get("storage"), dict) and "requestedSize" in values["storage"]
        if not has_storage:
            warn("upstream has no storage.requestedSize - map the PVC size key by hand (template + values-test)")
        print(f"  labels={knobs['labels']} annotations={knobs['annotations']} podLabels={knobs['pod_labels']} "
              f"podAnnotations={knobs['pod_annotations']} imagePullSecrets={knobs['pull_secrets']} storage={has_storage}")

        # ---- images actually rendered by default
        blocks = find_image_blocks(values)
        used = rendered_images(pulled)
        if used is None:
            warn("chart does not render with default values - could not detect which images are used; "
                 "only the main `image` block is included, add init/sidecar images by hand")
        images: list[dict] = []
        for path, block in blocks:
            is_main = path == "image"
            reg, repo, tag = block_ref(block, app_version, args.image_tag if is_main else None)
            if used is not None and not is_main and norm_ref(full_ref(reg, repo, block_ref(block, app_version)[2])) not in used:
                continue  # not rendered by default (e.g. metrics exporter) - mirrored only if enabled by hand
            images.append({"path": path, "reg": reg, "repo": repo, "tag": tag, "main": is_main,
                           "name": repo.rstrip("/").rsplit("/", 1)[-1]})
        if not any(i["main"] for i in images):
            die(f"{sub}/values.yaml has no `image` block with repository + tag - cannot pin the application image")
        if used is not None:
            known = {norm_ref(full_ref(i["reg"], i["repo"], i["tag"])) for i in images}
            for r in sorted(used - known):
                warn(f"rendered image '{r}' is not driven by a values.yaml image block (hard-coded in the chart) "
                     f"- it cannot be redirected to BYOP_REGISTRY through values")
        disabled = [p for p, _ in blocks if p not in {i["path"] for i in images}]
        if disabled:
            print(f"  images not rendered by default (not mirrored): {', '.join(disabled)}")
        for i in images:
            print(f"  image {i['path']}: {mirror_ref(i['reg'], i['repo'], i['tag'])}"
                  f"{'  (main)' if i['main'] else ''}")
        main_img = next(i for i in images if i["main"])
        pinned_tag = main_img["tag"]

        # ---- SCC
        print("\n== OpenShift restricted-v2 SCC ==")
        scc: dict[str, dict] = {}
        for ctx_key in ("podSecurityContext", "securityContext"):
            up = values.get(ctx_key)
            block: dict = {k: None for k in UID_KEYS if isinstance(up, dict) and up.get(k) is not None}
            block["seccompProfile"] = {"type": "RuntimeDefault"}
            scc[ctx_key] = block
            if not isinstance(up, dict):
                warn(f"upstream has no `{ctx_key}` value - SCC for it is a no-op, confirm the pod spec by rendering")
        print("  nulling: " + ", ".join(f"{c}.{k}" for c, b in scc.items() for k, v in b.items() if v is None))

        # ---- build files ----------------------------------------------------------------
        print(f"\n== writing {base}/ ==")
        dest_chart = base / "chart" / "charts" / sub
        shutil.copytree(pulled, dest_chart)
        files: dict[str, str] = {}

        files["chart/Chart.yaml"] = (
            "apiVersion: v2\n"
            f"name: {sub}-byop\n"
            f"description: BYOP platform wrapper around the unmodified {chart_yaml.get('description', sub)}\n"
            "type: application\n"
            'version: "1.0.0"\n'
            f'appVersion: "{pinned_tag}"\n'
            "dependencies:\n"
            f"  - name: {sub}\n"
            f'    version: "{sub_version}"\n'
            f'    repository: "file://./charts/{sub}"\n')
        scc_lines = []
        for c, b in scc.items():
            scc_lines.append(f"  {c}:")
            for k, v in b.items():
                if v is None:
                    scc_lines.append(f"    {k}: null")
                else:
                    scc_lines.append(f"    {k}:\n      type: RuntimeDefault")
            scc_lines.append("")
        files["chart/values.yaml"] = (
            f"# BYOP wrapper defaults for {helm_name}.\n"
            f"# The upstream {sub} chart is vendored unchanged in charts/{sub}/.\n"
            f"# Everything here is passed to it through the `{sub}:` subchart namespace.\n\n"
            f"{sub}:\n"
            "  # OpenShift restricted-v2 SCC: the SCC assigns UID/GID/fsGroup, so the upstream\n"
            "  # hard-coded values must be unset (null deletes the upstream key).\n"
            + "\n".join(scc_lines).rstrip() + "\n")
        files["chart/.helmignore"] = (dest_chart / ".helmignore").read_text() if (dest_chart / ".helmignore").is_file() else ".git/\n"

        # production template
        tree_prod: dict = {}
        tree_test: dict = {}
        for i in images:
            if i["reg"]:
                prod = {"registry": "BYOP_REGISTRY", "repository": f"byop/{i['name']}", "tag": q(i["tag"])}
                test = {"registry": q(i["reg"]), "repository": q(i["repo"] if "/" in i["repo"] or i["reg"] != "docker.io" else f"library/{i['repo']}"),
                        "tag": q(i["tag"])}
            else:
                prod = {"repository": f"BYOP_REGISTRY/byop/{i['name']}", "tag": q(i["tag"])}
                test = {"repository": q(i["repo"]), "tag": q(i["tag"])}
            deep_merge(tree_prod, tree_from_path(i["path"], prod))
            deep_merge(tree_test, tree_from_path(i["path"], test))
        for sname, path, pfx in secrets:
            test_val = f"test-{sname.replace('_', '-')}-local!!"
            if pfx:  # config-line style (redis/valkey): block scalar "<prefix> <value>"
                deep_merge(tree_prod, tree_from_path(path, f"|\n__BLOCK__{pfx} {{{{ spec.{sname} | yaml_safe }}}}"))
                deep_merge(tree_test, tree_from_path(path, f"|\n__BLOCK__{pfx} {test_val}"))
            else:
                deep_merge(tree_prod, tree_from_path(path, f"{{{{ spec.{sname} | yaml_safe }}}}"))
                deep_merge(tree_test, tree_from_path(path, q(test_val)))
        if has_storage:
            deep_merge(tree_prod, {"storage": {"requestedSize": "{{ storage_size }}"}})
            deep_merge(tree_prod, {"storage": {"# className": '"ceph-rbd-platform"'}})
            deep_merge(tree_test, {"storage": {"requestedSize": "1Gi", "className": '"local-path"'}})
        files["template/values.yaml.tmpl"] = (
            "# Helm values override for instance\n"
            f"# All keys live under `{sub}:` - the vendored subchart in chart/charts/{sub}/.\n"
            "# BYOP_REGISTRY is a literal placeholder resolved by service-render --mapping image-mapping.txt.\n"
            f"{sub}:\n" + platform_blocks(name, sub, knobs, test=False) + "\n\n" + emit(tree_prod, 2) + "\n")

        scc_test = (
            "  # Override SCC for local clusters that don't support null fsGroup/runAsUser\n"
            "  podSecurityContext:\n    fsGroup: 1000\n    seccompProfile:\n      type: RuntimeDefault\n\n"
            "  securityContext:\n    allowPrivilegeEscalation: false\n    privileged: false\n"
            "    readOnlyRootFilesystem: true\n    runAsNonRoot: true\n    runAsUser: 1000\n    runAsGroup: 1000\n"
            "    capabilities:\n      drop:\n        - ALL\n    seccompProfile:\n      type: RuntimeDefault\n")
        files["values-test.yaml"] = (
            f"# Test values for {helm_name} - local cluster, no image substitution.\n"
            "# Mirrors template/values.yaml.tmpl with every Jinja2 variable resolved; uses the upstream registry directly.\n"
            f"# All keys live under `{sub}:` (the vendored subchart).\n#\n# Usage:\n"
            f"#   helm upgrade --install {name}-test services/{helm_name}/{args.version}/chart \\\n"
            f"#     -f services/{helm_name}/{args.version}/values-test.yaml \\\n"
            f"#     --create-namespace --namespace {name}-test\n\n"
            f"{sub}:\n" + platform_blocks(name, sub, knobs, test=True) + "\n\n" + emit(tree_test, 2) + "\n\n" + scc_test)

        # schema.json
        props = {"cluster_url": {
            "type": "string",
            "description": "Target cluster server URL (optional, defaults to broker's cluster). Must be a registered ArgoCD cluster.",
            "format": "uri", "pattern": "^https://.*",
            "examples": ["https://kubernetes.default.svc", "https://192.168.2.89:6443"]}}
        for sname, _p, _x in secrets:
            props[sname] = {
                "type": "string",
                "description": f"{sname.replace('_', ' ').capitalize()} (auto-generated if not provided)",
                "minLength": 8, "maxLength": 128, "examples": ["SecureP@ssw0rd123"],
                "x-generate": {"type": "password", "length": 32, "include": "alphanumeric-symbols"}}
        files["catalog/schema.json"] = json.dumps({
            "$schema": "http://json-schema.org/draft-07/schema#", "type": "object",
            "title": f"{display} Instance Parameters",
            "description": f"Parameters for provisioning a {display} instance",
            "properties": props, "required": [], "additionalProperties": False}, indent=2) + "\n"
        files["catalog/metrics.json"] = '{"metrics": []}\n'

        env = Environment(loader=FileSystemLoader(str(SHARED_TEMPLATES)), undefined=StrictUndefined, keep_trailing_newline=True)
        description = args.description or (f"Full-lifecycle {display} service with broker-generated credentials "
                                           "stored in Git, deployed with Helm")
        files["catalog/catalog.yaml"] = env.get_template("catalog.yaml.j2").render(
            helm_name=helm_name, display=display, description=description)
        files["argocd/applicationset-helm.yaml.tmpl"] = (SHARED_TEMPLATES / "applicationset-helm.yaml.tmpl").read_text()

        mirror = [mirror_ref(i["reg"], i["repo"], i["tag"]) for i in images]
        files["imagesetconfiguration.yaml"] = (
            "kind: ImageSetConfiguration\napiVersion: mirror.openshift.io/v1alpha2\nstorageConfig:\n  local:\n    path: ./metadata\n"
            "mirror:\n  additionalImages:\n" + "".join(f"    - name: {m}\n" for m in mirror))

        sec_rows = "".join(f"| `{sub}.{p}` | `spec.{n}` (auto-generated, `yaml_safe`) |\n" for n, p, _x in secrets)
        param_rows = "".join(f"| `{n}` | | auto | {n.replace('_', ' ')} |\n" for n, _p, _x in secrets)
        files["README.md"] = (
            f"# {helm_name} - Service Definition\n\n{display} deployed via Helm. The broker renders a `values.yaml` per instance; "
            "ArgoCD applies the Helm release to the target cluster.\n\n"
            f"`{args.version}` is an **umbrella wrapper chart**: the upstream `{sub}` chart ({sub_version}) is vendored "
            f"**unmodified** in `chart/charts/{sub}/`, and all platform behaviour (labels, annotations, `imagePullSecrets`, "
            f"OpenShift SCC defaults, image registry, storage) is applied through values under the `{sub}:` key.\n\n"
            f"## Directory structure\n\n```\nservices/{helm_name}/{args.version}/\n├── chart/\n"
            f"│   ├── Chart.yaml          # wrapper ({sub}-byop), depends on file://./charts/{sub}\n"
            "│   ├── values.yaml         # platform defaults (OpenShift SCC)\n"
            f"│   └── charts/{sub}/{' ' * max(1, 14 - len(sub))}# UNMODIFIED upstream chart - never edit; replace to upgrade\n"
            "├── template/\n│   └── values.yaml.tmpl    # Jinja2 template rendered per instance\n"
            "├── catalog/\n│   ├── catalog.yaml\n│   ├── schema.json         # Instance parameter schema\n│   └── metrics.json\n"
            "└── argocd/\n    └── applicationset-helm.yaml.tmpl\n```\n\n"
            "## Instance parameters (`catalog/schema.json`)\n\n| Parameter | Required | Default | Description |\n|---|---|---|---|\n"
            "| `cluster_url` | | broker default | ArgoCD-registered cluster URL |\n" + param_rows + "\n"
            f"## Key Helm values set per instance\n\nAll paths are under the `{sub}:` subchart key.\n\n| values.yaml path | Source |\n|---|---|\n"
            f"| `{sub}.fullnameOverride` | `<service_type>-<instance_name>` |\n"
            f"| `{sub}.{knobs['labels'] or 'customLabels'}` / `{sub}.{knobs['pod_labels'] or 'podLabels'}` | `app`, `service-type` |\n"
            f"| `{sub}.{knobs['annotations'] or 'customAnnotations'}` / `{sub}.{knobs['pod_annotations'] or 'podAnnotations'}` | `sovcore.byop.ibm.com/*` from broker context |\n"
            f"| `{sub}.imagePullSecrets` | `image_pull_secret_name` |\n"
            + "".join(f"| `{sub}.{i['path']}.registry` | `BYOP_REGISTRY` (substituted by `service-render`) |\n" for i in images if i["reg"])
            + sec_rows + ("| `" + sub + ".storage.requestedSize` | `storage_size` |\n" if has_storage else "") + "\n"
            "## Upgrading the upstream chart\n\nUse the `upgrade-helm-wrapper` skill: replace `chart/charts/" + sub +
            "/` with the new release and bump the dependency `version` in `chart/Chart.yaml`.\n\n"
            f"## Testing\n\n```bash\nhelm template {name}-test services/{helm_name}/{args.version}/chart "
            f"-f services/{helm_name}/{args.version}/values-test.yaml\n```\n")

        for rel, content in files.items():
            p = base / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content)
        total = sum(1 for f in base.rglob("*") if f.is_file())
        print(f"  {total} files (upstream chart vendored byte-identical in chart/charts/{sub}/)")

        # ---- post checks
        print("\n== post-scaffold checks ==")
        tp = run(["helm", "template", f"{helm_name}-test", str(base / "chart"), "-f", str(base / "values-test.yaml")])
        if tp.returncode != 0:
            warn(f"helm template with values-test.yaml FAILED: {tp.stderr.strip()[:300]}")
        else:
            kinds = re.findall(r"^kind: (\S+)", tp.stdout, re.M)
            print(f"  helm template OK: {', '.join(kinds)}")
            if "StatefulSet" in kinds and "clusterIP: None" not in tp.stdout:
                warn("renders a StatefulSet but no Service with `clusterIP: None` - the upstream chart has no headless service; "
                     "see SKILL.md Step 7 before adding a wrapper chart/templates/service-headless.yaml")
            if "Deployment" in kinds and "StatefulSet" not in kinds:
                print("  (Deployment mode: no headless service needed)")

        print(f"\nNext: add to image-mapping.txt under '# {helm_name}':")
        for m, i in zip(mirror, images):
            print(f"  {m}  ->  localhost:5000/byop/{i['name']}:{i['tag']}")
        print(f"Then validate:\n  BYOP_BROKER_SRC=<byop-broker>/broker/src /tmp/jv/bin/python tools/service-render-check {helm_name}/{args.version}\n"
              f"  PATH=/tmp/jv/bin:$PATH bash tools/service-validator --version {args.version} {helm_name}\n")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if WARNINGS:
        print(f"{len(WARNINGS)} warning(s) need attention (see [WARN] lines above).")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
