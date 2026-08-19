# Host SBOM — Clean, Run & Verify

## Final confirmation

**YES — the final script generates an SBOM for the HOST VM.**

It discovers host-level software/components such as APT/DPKG packages, dynamically discovered executables/runtimes, Docker images, and running services, then generates a CycloneDX SBOM JSON.

## 1. Check current SBOM service/timer

```bash
sudo systemctl status host-sbom.service --no-pager
sudo systemctl status host-sbom.timer --no-pager
sudo systemctl list-timers host-sbom.timer --no-pager
pgrep -af "host-sbom|host-sbom-collector"
```

## 2. Stop only the SBOM service/timer

**Do NOT stop Docker, Jenkins, SonarQube, Java, Python, Node.js, or other application services.**

```bash
sudo systemctl stop host-sbom.timer
sudo systemctl stop host-sbom.service
sudo pkill -TERM -f "/usr/local/bin/host-sbom-collector.py" 2>/dev/null || true
```

Check:

```bash
pgrep -af "host-sbom-collector"
```

No output means the collector is not running.

## 3. Disable the old timer

```bash
sudo systemctl disable host-sbom.timer
sudo systemctl daemon-reload
sudo systemctl reset-failed host-sbom.service host-sbom.timer
```

## 4. Remove old SBOM systemd definitions

Use this when replacing the complete setup:

```bash
sudo rm -f /etc/systemd/system/host-sbom.service
sudo rm -f /etc/systemd/system/host-sbom.timer
sudo systemctl daemon-reload
sudo systemctl reset-failed
```

## 5. Remove the old collector

```bash
sudo rm -f /usr/local/bin/host-sbom-collector.py
```

Verify:

```bash
ls -l /usr/local/bin/host-sbom-collector.py
```

## 6. Remove previous SBOM files for a completely fresh run

```bash
sudo rm -f /var/lib/host-sbom/host-sbom.json
sudo rm -f /home/ubuntu/host-sbom.json
```

## 7. Run the final setup script

Assuming:

```text
/root/setup-host-sbom-final.sh
```

Run:

```bash
sudo chmod 700 /root/setup-host-sbom-final.sh
sudo /root/setup-host-sbom-final.sh
```

## 8. Verify successful generation

```bash
sudo systemctl status host-sbom.service --no-pager
sudo journalctl -u host-sbom.service -n 50 --no-pager
```

Look for:

```text
code=exited, status=0/SUCCESS
CycloneDX validation: PASS
Finished Generate Host CycloneDX SBOM.
```

## 9. Verify the timer

```bash
sudo systemctl status host-sbom.timer --no-pager
sudo systemctl list-timers host-sbom.timer --no-pager
sudo systemctl is-enabled host-sbom.timer
```

Expected:

```text
Active: active (waiting)
enabled
```

The timer remains active; the collector itself runs only when triggered and then exits.

## 10. Verify SBOM files

```bash
sudo ls -lh /var/lib/host-sbom/host-sbom.json
sudo ls -lh /home/ubuntu/host-sbom.json
```

## 11. Verify CycloneDX structure

```bash
sudo python3 - <<'PY'
import json

path = "/var/lib/host-sbom/host-sbom.json"

with open(path) as f:
    bom = json.load(f)

print("Format:", bom.get("bomFormat"))
print("Spec version:", bom.get("specVersion"))
print("Serial:", bom.get("serialNumber"))
print("Components:", len(bom.get("components", [])))
PY
```

Expected:

```text
Format: CycloneDX
Spec version: 1.5
Components: <number greater than 0>
```

## 12. Verify Python is represented

```bash
sudo python3 - <<'PY'
import json

path = "/var/lib/host-sbom/host-sbom.json"

with open(path) as f:
    bom = json.load(f)

found = []

for component in bom.get("components", []):
    text = json.dumps(component).lower()
    if any(x in text for x in ["python3", "python 3", "python-3", "python"]):
        found.append(component)

print("Python-related components:", len(found))

for component in found:
    print(component.get("name"), component.get("version"), component.get("type"))
PY
```

## 13. Verify collector is not continuously running

```bash
pgrep -af "host-sbom-collector"
sudo systemctl status host-sbom.service --no-pager
```

After a completed run, it is normal for the service to show:

```text
Active: inactive (dead)
code=exited, status=0/SUCCESS
```

The timer is what starts it again at the configured interval.

## 14. Verify application services were not stopped

Docker:

```bash
sudo systemctl is-active docker
sudo docker ps
```

Optional process check:

```bash
pgrep -af "java|node|python"
```

The SBOM setup should not intentionally stop these application services.

## 15. Final BOM validation before Dependency-Track upload

```bash
sudo python3 - <<'PY'
import json

path = "/var/lib/host-sbom/host-sbom.json"

with open(path) as f:
    bom = json.load(f)

allowed = {
    "application", "framework", "library", "container",
    "platform", "operating-system", "device", "device-driver",
    "firmware", "file", "machine-learning-model", "data",
    "cryptographic-asset"
}

bad = [c for c in bom.get("components", [])
       if c.get("type") not in allowed]

print("BOM format:", bom.get("bomFormat"))
print("Spec version:", bom.get("specVersion"))
print("Total components:", len(bom.get("components", [])))
print("Invalid component types:", len(bad))

if bad:
    for c in bad[:10]:
        print(c.get("name"), "=>", c.get("type"))
else:
    print("CycloneDX component types: PASS")
PY
```

Upload only after this validation passes.

## Important safety rule

These cleanup commands target only the SBOM service, timer, collector, and SBOM files. **They do not stop or remove Docker, Jenkins, SonarQube, Java, Node.js, Python, or other application services.**

## Architecture

```text
HOST VM
   |
   +-- APT / DPKG packages
   +-- Runtime executables
   +-- Python / Java / Node etc.
   +-- Docker images
   +-- Running services
   |
   v
host-sbom-collector.py
   |
   v
CycloneDX 1.5 SBOM
   |
   +-- /var/lib/host-sbom/host-sbom.json
   +-- /home/ubuntu/host-sbom.json
   |
   v
Dependency-Track
   |
   +-- Components
   +-- Vulnerabilities
   +-- Licenses
   +-- Policy Violations
   +-- Risk
```
