#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# HOST SBOM - FINAL CLEAN SETUP
# Ubuntu/Debian GCP VM
#
# - Replaces ONLY host-sbom.service / host-sbom.timer
# - Does NOT stop Docker/Jenkins/Java/Node/Python/etc.
# - Generates CycloneDX 1.5 JSON
# - Discovers APT packages, Docker images, and installed
#   executables/runtimes including Python, Java, Node.js, etc.
# - Discovers Python pip packages when pip is available
# - Copies the successful SBOM to the invoking user's home
# - Runs immediately and then every 5 hours
# ============================================================

SERVICE="/etc/systemd/system/host-sbom.service"
TIMER="/etc/systemd/system/host-sbom.timer"
COLLECTOR="/usr/local/bin/host-sbom-collector.py"
DATA_DIR="/var/lib/host-sbom"
SBOM="${DATA_DIR}/host-sbom.json"
LOCK="/run/host-sbom.lock"

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo/root."
    exit 1
fi

mkdir -p "$DATA_DIR"
chmod 755 "$DATA_DIR"

# Find the user who invoked sudo. If this script is run directly as root,
# use the first normal home directory found.
TARGET_USER="${SUDO_USER:-}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    TARGET_USER="$(awk -F: '$3 >= 1000 && $6 ~ /^\/home\// {print $1; exit}' /etc/passwd || true)"
fi

if [[ -n "$TARGET_USER" ]] && id "$TARGET_USER" >/dev/null 2>&1; then
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
else
    TARGET_USER="root"
    TARGET_HOME="/root"
fi

echo "[host-sbom-setup] Target user : $TARGET_USER"
echo "[host-sbom-setup] Target home : $TARGET_HOME"

# IMPORTANT: only replace this SBOM service/timer.
systemctl stop host-sbom.timer 2>/dev/null || true
systemctl disable host-sbom.timer 2>/dev/null || true
systemctl stop host-sbom.service 2>/dev/null || true
systemctl reset-failed host-sbom.service 2>/dev/null || true

cat > "$COLLECTOR" <<'PY'
#!/usr/bin/env python3
import json
import os
import re
import shutil
import socket
import subprocess
import time
from pathlib import Path
from datetime import datetime, timezone

DATA_DIR = Path("/var/lib/host-sbom")
SBOM = DATA_DIR / "host-sbom.json"
EXPORT_DIRS = []

# ---------- safe command helpers ----------

def run(cmd, timeout=20):
    try:
        p = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=timeout,
            check=False,
        )
        return p.stdout.strip()
    except Exception:
        return ""

def version_from_output(text):
    if not text:
        return ""
    # Prefer a normal semantic-ish version.
    m = re.search(r"\b\d+(?:\.\d+){1,4}(?:[-+~][A-Za-z0-9._-]+)?\b", text)
    return m.group(0) if m else text.splitlines()[0][:120]

def executable_version(path):
    p = str(path)
    base = os.path.basename(p)

    candidates = [
        [p, "--version"],
        [p, "-version"],
        [p, "version"],
        [p, "-v"],
    ]

    # Python can reliably report itself this way.
    if "python" in base.lower():
        candidates.insert(0, [p, "--version"])

    for cmd in candidates:
        out = run(cmd, timeout=8)
        if out:
            return version_from_output(out), out.replace("\n", " ")[:250]
    return "", ""

def purl_escape(value):
    return str(value).replace(" ", "%20")

# ---------- CycloneDX component handling ----------

components = []
seen_refs = set()

def add_component(name, version, ctype, source="", evidence="", purl=""):
    name = str(name or "").strip()
    version = str(version or "").strip()

    if not name or not version:
        return

    allowed = {
        "application", "framework", "library", "container",
        "operating-system", "device", "firmware", "file"
    }
    if ctype not in allowed:
        ctype = "application"

    # Keep the reference stable and unique.
    raw = f"{ctype}:{name}:{version}:{source}"
    ref = "sbom-" + re.sub(r"[^A-Za-z0-9_.-]+", "-", raw).strip("-")
    if ref in seen_refs:
        return
    seen_refs.add(ref)

    props = []
    if source:
        props.append({"name": "inventory.source", "value": source})
    if evidence:
        props.append({"name": "inventory.evidence", "value": evidence})

    # Do NOT use "runtime" or "tool" as CycloneDX component type.
    # Runtime/tool classification is represented as a property.
    lower = (name + " " + source + " " + evidence).lower()
    if any(x in lower for x in (
        "python", "java", "openjdk", "node", "nodejs", "ruby",
        "perl", "php", "golang", "go version"
    )):
        props.append({"name": "inventory.category", "value": "runtime"})
    elif any(x in lower for x in (
        "terraform", "ansible", "maven", "gradle", "kubectl",
        "helm", "docker", "podman", "packer", "gitlab-runner"
    )):
        props.append({"name": "inventory.category", "value": "tool"})
    else:
        props.append({"name": "inventory.category", "value": "path-discovered"})

    c = {
        "type": ctype,
        "bom-ref": ref,
        "name": name,
        "version": version,
        "properties": props,
    }
    if purl:
        c["purl"] = purl

    components.append(c)

# ---------- APT ----------

def discover_apt():
    out = run([
        "dpkg-query", "-W",
        "-f=${Package}\t${Version}\t${Architecture}\n"
    ], timeout=30)

    count = 0
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        name, version = parts[0].strip(), parts[1].strip()
        arch = parts[2].strip() if len(parts) > 2 else ""
        if not name or not version:
            continue
        purl = f"pkg:deb/ubuntu/{purl_escape(name)}@{purl_escape(version)}"
        if arch:
            purl += f"?arch={purl_escape(arch)}"
        add_component(
            name, version, "library",
            source="dpkg",
            evidence=f"installed APT/DPKG package; architecture={arch}",
            purl=purl,
        )
        count += 1
    return count

# ---------- Docker images ----------

def discover_docker():
    if not shutil.which("docker"):
        return 0

    out = run([
        "docker", "images", "--no-trunc",
        "--format", "{{.Repository}}\t{{.Tag}}\t{{.ID}}"
    ], timeout=30)

    count = 0
    for line in out.splitlines():
        repo, tag, image_id = (line.split("\t") + ["", "", ""])[:3]
        repo, tag, image_id = repo.strip(), tag.strip(), image_id.strip()
        if not repo or repo == "<none>":
            continue
        if not tag or tag == "<none>":
            tag = "latest"

        name = repo
        version = tag
        purl = f"pkg:docker/{purl_escape(repo)}@{purl_escape(tag)}"

        add_component(
            name, version, "container",
            source="docker",
            evidence=f"local Docker image; image-id={image_id}",
            purl=purl,
        )
        count += 1
    return count

# ---------- executable/runtime discovery ----------

COMMON_DIRS = [
    "/usr/bin",
    "/usr/sbin",
    "/usr/local/bin",
    "/usr/local/sbin",
    "/opt",
    "/snap/bin",
    "/bin",
    "/sbin",
]

NAME_PATTERNS = [
    # Python
    r"^python(?:3(?:\.\d+)?)?$",
    r"^python3(?:\.\d+)?$",
    r"^pip(?:3(?:\.\d+)?)?$",
    # Java
    r"^java$",
    r"^javac$",
    r"^jre$",
    # Node
    r"^node$",
    r"^nodejs$",
    r"^npm$",
    # Go
    r"^go$",
    # Ruby / PHP / Perl
    r"^ruby(?:\d+(?:\.\d+)?)?$",
    r"^php(?:\d+(?:\.\d+)?)?$",
    r"^perl$",
    # DevOps tools
    r"^terraform$",
    r"^ansible(?:-playbook)?$",
    r"^mvn$",
    r"^mvnw$",
    r"^gradle$",
    r"^gradlew$",
    r"^kubectl$",
    r"^helm$",
    r"^docker$",
    r"^podman$",
    r"^packer$",
    r"^gitlab-runner$",
]

COMPILED = [re.compile(x, re.I) for x in NAME_PATTERNS]

def looks_interesting(name):
    return any(r.search(name) for r in COMPILED)

def discover_executables():
    paths = set()

    # 1. Explicit PATH lookup. This guarantees common runtimes are checked.
    explicit = [
        "python3", "python", "python3.10", "python3.11", "python3.12",
        "pip3", "pip",
        "java", "javac",
        "node", "nodejs", "npm",
        "go", "ruby", "php", "perl",
        "terraform", "ansible", "ansible-playbook",
        "mvn", "gradle", "kubectl", "helm",
        "docker", "podman", "packer", "gitlab-runner",
    ]
    for name in explicit:
        p = shutil.which(name)
        if p:
            paths.add(os.path.realpath(p))

    # 2. Search standard installation directories.
    # Limit depth/work so the collector remains safe on a production VM.
    roots = [
        Path("/usr/bin"),
        Path("/usr/local/bin"),
        Path("/opt"),
        Path("/snap/bin"),
    ]

    for root in roots:
        if not root.exists():
            continue
        try:
            if str(root) in ("/usr/bin", "/usr/local/bin", "/snap/bin"):
                for p in root.iterdir():
                    if p.is_file() or p.is_symlink():
                        if looks_interesting(p.name):
                            try:
                                paths.add(os.path.realpath(str(p)))
                            except Exception:
                                pass
            else:
                # /opt: inspect bin directories only.
                for bin_dir in root.glob("*/bin"):
                    if not bin_dir.is_dir():
                        continue
                    for p in bin_dir.iterdir():
                        if p.is_file() or p.is_symlink():
                            if looks_interesting(p.name):
                                try:
                                    paths.add(os.path.realpath(str(p)))
                                except Exception:
                                    pass
        except Exception:
            pass

    # 3. User-local paths for all normal users.
    try:
        passwd = Path("/etc/passwd").read_text(errors="ignore")
        for line in passwd.splitlines():
            parts = line.split(":")
            if len(parts) < 7:
                continue
            try:
                uid = int(parts[2])
            except Exception:
                continue
            home = parts[5]
            if uid < 1000 or not home.startswith("/home/"):
                continue

            for base in (
                Path(home) / ".local/bin",
                Path(home) / "bin",
            ):
                if not base.is_dir():
                    continue
                try:
                    for p in base.iterdir():
                        if (p.is_file() or p.is_symlink()) and looks_interesting(p.name):
                            paths.add(os.path.realpath(str(p)))
                except Exception:
                    pass
    except Exception:
        pass

    count = 0
    for path in sorted(paths):
        if not os.path.exists(path) or not os.access(path, os.X_OK):
            continue

        name = os.path.basename(path)
        version, raw = executable_version(path)
        if not version:
            continue

        category = "runtime" if any(x in name.lower() for x in (
            "python", "java", "javac", "node", "nodejs",
            "ruby", "php", "perl", "go"
        )) else "tool"

        add_component(
            name,
            version,
            "application",
            source="executable",
            evidence=f"{category}; path={path}; version-output={raw}",
        )
        count += 1

    return count

# ---------- Python pip packages ----------

def discover_pip():
    count = 0
    python_paths = set()

    for name in ("python3", "python", "python3.10", "python3.11", "python3.12"):
        p = shutil.which(name)
        if p:
            python_paths.add(os.path.realpath(p))

    # Explicit standard system locations.
    for p in Path("/usr/bin").glob("python3*"):
        if p.is_file() and os.access(p, os.X_OK):
            python_paths.add(os.path.realpath(str(p)))

    for py in sorted(python_paths):
        out = run([py, "-m", "pip", "list", "--format=json"], timeout=30)
        if not out:
            continue
        try:
            packages = json.loads(out)
        except Exception:
            continue

        for pkg in packages:
            name = str(pkg.get("name", "")).strip()
            version = str(pkg.get("version", "")).strip()
            if not name or not version:
                continue
            purl = f"pkg:pypi/{purl_escape(name.lower())}@{purl_escape(version)}"
            add_component(
                name,
                version,
                "library",
                source="pip",
                evidence=f"Python environment={py}",
                purl=purl,
            )
            count += 1

    return count

# ---------- service/executable evidence ----------

def discover_service_evidence():
    # This is intentionally evidence only. It does not execute or stop services.
    out = run([
        "systemctl", "list-units",
        "--type=service",
        "--state=running",
        "--no-legend",
        "--no-pager",
    ], timeout=20)

    count = 0
    for line in out.splitlines():
        parts = line.split()
        if not parts:
            continue
        unit = parts[0]
        if not unit.endswith(".service"):
            continue

        # Do not add every service as an application component; the installed
        # executable inventory is the authoritative component list.
        count += 1

    return count

# ---------- build ----------

def build_bom():
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    apt_count = discover_apt()
    exe_count = discover_executables()
    docker_count = discover_docker()
    pip_count = discover_pip()
    service_count = discover_service_evidence()

    bom = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "serialNumber": "urn:uuid:" + os.urandom(16).hex(),
        "version": 1,
        "metadata": {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "authors": [{"name": "Host SBOM Collector"}],
            "component": {
                "type": "operating-system",
                "bom-ref": "host-os",
                "name": socket.gethostname(),
                "version": run(["uname", "-r"]) or "unknown",
            },
            "properties": [
                {"name": "host.name", "value": socket.gethostname()},
                {"name": "host.os", "value": run([". /etc/os-release; echo $PRETTY_NAME"], timeout=5) or "Ubuntu/Debian"},
                {"name": "inventory.service.count", "value": str(service_count)},
            ],
        },
        "components": components,
    }

    tmp = SBOM.with_suffix(".tmp")
    tmp.write_text(json.dumps(bom, indent=2, sort_keys=False), encoding="utf-8")
    tmp.replace(SBOM)

    # Strict local JSON/schema sanity checks that do not require external packages.
    with SBOM.open(encoding="utf-8") as f:
        check = json.load(f)

    if check.get("bomFormat") != "CycloneDX":
        raise RuntimeError("Invalid bomFormat")
    if check.get("specVersion") != "1.5":
        raise RuntimeError("Invalid CycloneDX specVersion")
    if not isinstance(check.get("components"), list):
        raise RuntimeError("components is not a list")

    allowed = {
        "application", "framework", "library", "container",
        "operating-system", "device", "firmware", "file"
    }
    bad = []
    for c in check["components"]:
        if c.get("type") not in allowed:
            bad.append((c.get("name"), c.get("type")))
    if bad:
        raise RuntimeError(f"Invalid component types: {bad[:10]}")

    print("=== Host SBOM generation complete ===")
    print("Hostname             :", socket.gethostname())
    print("OS                   :", run(["bash", "-c", ". /etc/os-release && echo ${PRETTY_NAME:-unknown}"]))
    print("Manual APT packages  :", apt_count)
    print("Dynamic executables  :", exe_count)
    print("Python pip packages  :", pip_count)
    print("Docker images        :", docker_count)
    print("Running services     :", service_count)
    print("SBOM components      :", len(components))
    print("SBOM                 :", SBOM)
    print("CycloneDX validation : SUCCESS")

if __name__ == "__main__":
    # Prevent overlapping executions.
    import fcntl
    lock_file = open("/run/host-sbom.lock", "w")
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("Another host-sbom collector is already running; exiting.")
        raise SystemExit(0)

    build_bom()
PY

chmod 755 "$COLLECTOR"
chown root:root "$COLLECTOR"

cat > "$SERVICE" <<EOF
[Unit]
Description=Generate Host CycloneDX SBOM
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 $COLLECTOR
User=root
StandardOutput=journal
StandardError=journal
TimeoutStartSec=30min
Nice=10
EOF

cat > "$TIMER" <<'EOF'
[Unit]
Description=Generate Host SBOM Every 5 Hours

[Timer]
OnBootSec=2min
OnUnitActiveSec=5h
Persistent=true
Unit=host-sbom.service

[Install]
WantedBy=timers.target
EOF

# Validate Python before installing/enabling the service.
python3 -m py_compile "$COLLECTOR"

systemctl daemon-reload
systemctl enable host-sbom.timer

# Run once NOW so the file exists for immediate demo/upload.
systemctl start host-sbom.service

# Copy only after successful generation.
if [[ ! -s "$SBOM" ]]; then
    echo "[host-sbom-setup] ERROR: SBOM was not generated."
    exit 1
fi

# Validate JSON one more time.
python3 -m json.tool "$SBOM" >/dev/null

EXPORT_FILE="${TARGET_HOME}/host-sbom.json"
install -o "$TARGET_USER" -g "$(id -gn "$TARGET_USER")" -m 0644 "$SBOM" "$EXPORT_FILE"

echo
echo "============================================================"
echo "HOST SBOM SETUP COMPLETE"
echo "============================================================"
echo "Collector : $COLLECTOR"
echo "SBOM      : $SBOM"
echo "Export    : $EXPORT_FILE"
echo "Service   : host-sbom.service"
echo "Timer     : host-sbom.timer"
echo "Schedule  : every 5 hours"
echo
echo "--- Timer ---"
systemctl status host-sbom.timer --no-pager || true
echo
echo "--- Service (last run) ---"
systemctl status host-sbom.service --no-pager || true
echo
echo "--- Files ---"
ls -lh "$SBOM" "$EXPORT_FILE"
echo
echo "Existing application services were NOT stopped."
