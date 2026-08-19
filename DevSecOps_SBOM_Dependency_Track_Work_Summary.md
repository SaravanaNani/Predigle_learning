# DevSecOps SBOM + Dependency-Track – Work Summary

## 1. Objective
Build a repeatable host-level Software Bill of Materials (SBOM) for the `predigle-helpdesk-dev` VM and analyze it in Dependency-Track for components, vulnerabilities, licenses, policy violations, and risk.

## 2. Why SBOM?
An SBOM is an inventory of software present on a system. The collector identifies:
- APT/DPKG packages
- Runtime executables such as Python, Java and Node.js where present
- Docker images
- Running services
- Versions, PURLs and discovery evidence

Important distinction: **the collector generates the inventory; Dependency-Track analyzes the inventory for security and compliance risk.**

## 3. What I implemented
Main artifacts:
```text
/usr/local/bin/host-sbom-collector.py
/var/lib/host-sbom/host-sbom.json
/home/ubuntu/host-sbom.json
/etc/systemd/system/host-sbom.service
/etc/systemd/system/host-sbom.timer
```

The collector runs as its own Linux/systemd process. It does not intentionally stop or restart Docker, Java, Python, Jenkins, SonarQube, or other application services.

## 4. Discovery progression
Initially, package-only discovery produced a very small inventory (around 6 packages). This was insufficient because software can exist outside the package database.

Dynamic executable discovery was added so installed runtimes/tools could also be found. During testing the inventory increased into the hundreds. A final successful run showed approximately:
```text
Manual APT packages : 469
Dynamic executables : 3
Docker images       : 2
Running services    : 24
SBOM components     : 499
CycloneDX validation: PASS
```
The increase means discovery improved; it does not mean hundreds of packages were newly installed.

## 5. Problems and fixes
### Systemd termination
Some runs ended with `status=15/TERM` while the collector was still running. This was an execution/lifecycle issue and not an intentional stop of Docker or application services.

### Python discovery
Python existed at `/usr/bin/python3` / `/usr/bin/python3.10`, but an earlier BOM did not represent it as an executable component. The collector was improved to discover Python from the executable and retain the installed APT/DPKG package information.

### Collector logic error
One version failed with:
```text
ValueError: too many values to unpack (expected 2)
```
The caller and `classify_software()` return structure were corrected.

### DTrack schema error
An earlier upload returned:
```text
The uploaded BOM is invalid
Schema validation failed
```
The BOM structure and CycloneDX component types were corrected and validated. The final BOM uploaded successfully.

## 6. Dependency-Track project
Project:
```text
predigle-helpdesk-dev-vm
Version: 11.8.26
BOM format: CycloneDX 1.5
```

The project represents the VM's SBOM inventory. Keeping it in the portfolio gives a persistent place to review component and security risk.

## 7. Dependency-Track sections to explain
- **Dashboard:** portfolio-level security metrics.
- **Projects:** individual systems/applications and their SBOM history.
- **Components:** software components discovered by the SBOM.
- **Vulnerabilities:** known security findings associated with components.
- **Licenses:** licenses detected for components.
- **Policy Violations:** security, license and operational rules that were violated.
- **Dependency Graph:** relationships between components; usually more useful for application dependency trees than a broad host inventory.
- **Services:** service information associated with a project.
- **Vulnerability Audit:** human review and analysis decisions for findings.
- **Policy Violation Audit:** review of policy findings.

If the current dashboard shows zero vulnerabilities, it means no matching findings are currently reported; it does not mean the SBOM contains zero components.

## 8. Why create a DevSecOps team?
A dedicated team supports least privilege. Instead of giving an automation account administrator access, create a team for the SBOM workflow and give it only the permissions required.

A good explanation:
> “I created a dedicated DevSecOps team so the SBOM automation does not need administrator-level access. The API key belongs to that team and is scoped to the SBOM workflow.”

### BOM_UPLOAD
`BOM_UPLOAD` permits uploading BOMs.

It is different from:
- `ACCESS_MANAGEMENT` — manages users, teams, permissions and ACLs.
- `PORTFOLIO_MANAGEMENT` — modifies projects, metrics and policies.
- `PROJECT_CREATION_UPLOAD` — allows a BOM upload to create a project when required.

If Portfolio Access Control is enabled, the team also needs appropriate access to the intended project.

## 9. Team/project setup
1. Go to **Administration → Teams**.
2. Create or open the `DevSecOps` team.
3. Add the required users.
4. Assign only the required permissions.
5. Create an API key for the team if automation will upload the BOM.
6. If Portfolio Access Control is enabled, ensure the team is allowed to access the intended project.
7. Test with the team/API key rather than an administrator key.

## 10. Two-minute standup explanation
> “The task was to build host-level SBOM visibility for the Predigle Helpdesk development VM and integrate it with Dependency-Track.
>
> I initially used package-based discovery, but the inventory was very small because it only captured what was available through the package database.
>
> I then improved the collector with dynamic executable discovery so runtimes and tools installed outside the normal package database could also be identified.
>
> During testing I found issues with long-running systemd execution, Python discovery, a collector return-value error, and a CycloneDX schema validation error. I corrected those and validated the final BOM.
>
> The final run discovered hundreds of components, including APT packages, Python runtime information, Docker images and running services. The final CycloneDX 1.5 BOM passed validation and was successfully uploaded into Dependency-Track.
>
> Dependency-Track now gives us a central project where we can review components, vulnerabilities, licenses, policy violations and risk.
>
> I also want to use a dedicated DevSecOps team with least-privilege access. For the upload workflow, BOM_UPLOAD is the key permission rather than administrator-level access.” 

## 11. Current status
Completed:
- Host SBOM collector
- systemd service and timer
- APT/DPKG discovery
- Dynamic executable discovery
- Python discovery
- Docker image discovery
- Running-service discovery
- CycloneDX 1.5 generation
- Validation
- Local upload copy
- Dependency-Track project
- Successful SBOM upload
- Component inventory visible in DTrack

Next:
- Verify DevSecOps team
- Add users
- Create scoped API key
- Grant required permissions
- Verify project access if Portfolio ACL is enabled
- Demonstrate vulnerability, license and policy analysis
- Automate future SBOM uploads

## 12. Architecture
```text
Linux VM
   ↓
Host SBOM Collector
   ↓
CycloneDX 1.5 JSON
   ↓
Dependency-Track
   ↓
Components → Vulnerabilities → Licenses → Policies → Risk
```
