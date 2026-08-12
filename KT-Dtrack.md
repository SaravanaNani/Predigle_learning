---
| Term              | Simple meaning                              |
| ----------------- | ------------------------------------------- |
| **SBOM**          | List of software/components                 |
| **Syft**          | Tool that generates SBOM                    |
| **CycloneDX**     | SBOM format                                 |
| **DPKG**          | Ubuntu's low-level package database/manager |
| **APT**           | Ubuntu package management tool              |
| **Component**     | Individual software item                    |
| **Project**       | Thing being monitored in DTrack             |
| **Portfolio**     | Group of projects                           |
| **Vulnerability** | Known security issue                        |
| **Policy**        | Rule for deciding acceptable risk           |
---

                 GCP VM
                   │
          sbom-agent.service
                   │
                   ▼
            SBOM scan script
                   │
             ┌─────┴─────┐
             │           │
        Host inventory  Docker
             │           │
             ▼           ▼
         Syft scan    Syft image scan
             │           │
             ▼           ▼
        host-sbom.json  image-sbom.json
             │           │
             └─────┬─────┘
                   ▼
          Dependency-Track
                   │
        ┌──────────┼──────────┐
        ▼          ▼          ▼
     Projects  Components  Vulnerabilities
                              │
                              ▼
                           Policies
---
    systemd timer
        │
        └── every 5 hours
                │
                ▼
          scan + upload
                │
                ▼
            journal logs                          
