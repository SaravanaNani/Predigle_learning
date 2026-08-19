        ONE BOOTSTRAP SCRIPT
                │
                ├── creates directories
                ├── verifies Python
                ├── creates Python SBOM generator
                ├── creates systemd service
                ├── creates 5-hour systemd timer
                ├── runs first collection
                ├── stores SBOM
                └── creates logs
                         │
                         ▼
                /var/lib/host-sbom/
                         │
                         ├── latest.json
                         ├── sbom-<timestamp>.json
                         └── logs/
        
No Syft is required for this version. Dependency-Track upload is intentionally not enabled yet.

# What this script will discover

The generator will collect these layers:

    HOST
    │
    ├── OS / APT / DPKG packages
    │
    ├── Manually installed APT packages
    │
    ├── Python runtime
    │   └── pip packages
    │
    ├── Java runtime
    │   └── JAR/WAR dependency metadata where discoverable
    │
    ├── Node.js runtime
    │   └── npm packages
    │
    ├── Other installed executables/tools
    │
    ├── systemd services
    │
    └── Docker
        ├── Docker Engine
        ├── Docker containers
        └── Docker images

  
