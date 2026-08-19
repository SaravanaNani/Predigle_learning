# Host SBOM + Dependency-Track Demo Notes

## 1. Quick update to Hari

Hi Hari, quick update on the Host SBOM task:

- I implemented a native host SBOM collector on the GCP VM using Python 3.
- The collector dynamically discovers installed APT/DPKG packages, executables/runtimes, Docker images, running services, and related software evidence.
- I configured it as a Linux `systemd` service with a `systemd` timer to run every 5 hours.
- The generated BOM is CycloneDX JSON and passes local CycloneDX validation.
- The latest run successfully generated **499 components** and copied the SBOM to `/home/ubuntu/host-sbom.json`.
- Python is now correctly represented in the SBOM, including the installed Python 3.10 package and the `/usr/bin/python3.10` executable.
- I also successfully uploaded the latest BOM into Dependency-Track.
- Next, I will walk through the Dependency-Track dashboard, component inventory, vulnerabilities, policy violations, audit, and project/team configuration.

---

# 2. Standup explanation

## What was the task?

The objective was to generate a **host-level Software Bill of Materials (SBOM)** for the GCP VM and make it available in Dependency-Track.

The SBOM gives an inventory of software/components present on the VM so that Dependency-Track can analyze those components for:

- Known vulnerabilities
- License risk
- Security policy violations
- Operational/component risk
- Component usage and impact

Dependency-Track is designed to consume CycloneDX SBOMs and continuously analyze their components against vulnerability intelligence.

## Why did I use a custom script?

The VM is not just one application. It contains operating-system packages, runtimes, developer tools, Docker, services, and other software.

The custom collector was used to create one host-level inventory from the VM itself rather than depending on one application build.

The collector does not stop or restart Docker, Java, Jenkins, Node.js, or other application services as part of normal SBOM generation. It runs as its own Linux process through `systemd`.

---

# 3. What the final collector does

The current collector:

1. Runs with Python 3.
2. Collects manually installed/available APT/DPKG packages.
3. Dynamically discovers executable software instead of maintaining only a fixed Java/Node/Python checklist.
4. Detects runtime/tool evidence from executable paths and version output.
5. Detects Docker images.
6. Detects running Linux services.
7. Builds a CycloneDX JSON SBOM.
8. Adds inventory evidence/properties to components.
9. Validates the generated CycloneDX document.
10. Stores the primary SBOM at:

`/var/lib/host-sbom/host-sbom.json`

11. Copies the successful SBOM to the upload/demo location:

`/home/ubuntu/host-sbom.json`

12. Runs automatically through:

`host-sbom.service`

and:

`host-sbom.timer`

with a 5-hour schedule.

---

# 4. Latest successful run

The latest successful systemd run showed:

- Python: `/usr/bin/python3`
- Python version: `3.10.12`
- Manual APT packages: **469**
- Dynamic executables: **3**
- Python pip packages: **0**
- Docker images: **2**
- Running services: **24**
- SBOM components: **499**
- CycloneDX validation: **PASS**
- Upload copy: `/home/ubuntu/host-sbom.json`

The service completed successfully with exit status `0`.

The timer is enabled and configured to run the SBOM generation every 5 hours.

---

# 5. Python discovery issue — what happened and how it was fixed

Initially, Python was visible as a runtime in the collector output, but Python was not appearing as a proper component in the generated SBOM.

The reason was in the discovery/classification logic: the executable discovery path was calling the classifier and incorrectly expecting two return values while the classifier could return more information. This caused errors such as:

`ValueError: too many values to unpack (expected 2)`

There were also earlier versions where the dynamic runtime classification did not correctly create a Python component.

The collector was then rewritten so that:

- executable discovery and classification are separated cleanly;
- Python is discovered from the actual executable path;
- the installed APT/Dpkg Python package is retained;
- the executable itself is represented as an application/runtime component;
- evidence such as `/usr/bin/python3.10` and `Python 3.10.12` is stored in the SBOM.

The latest SBOM inspection confirms Python is now present, for example:

- `python3.10-minimal`
- `python3.10`
- executable evidence for `/usr/bin/python3.10`
- version evidence: `Python 3.10.12`
- inventory category: `runtime`

So the Python discovery requirement is now working.

---

# 6. Why there were earlier service failures

During development, the service sometimes showed:

`status=15/TERM`

and sometimes:

`status=1/FAILURE`

These were not Docker/Java/Jenkins failures.

The main causes were:

### A. Long-running SBOM generation

The earlier collector scanned many filesystem/executable locations. Some runs took several minutes.

### B. Development/replacement of the collector

The service was being restarted while different collector versions were being tested.

### C. Collector logic bug

The dynamic executable discovery/classification code had the tuple-unpacking error described above.

The final collector has now completed successfully with:

`code=exited, status=0/SUCCESS`

and:

`CycloneDX validation: PASS`

---

# 7. What is an SBOM?

SBOM = **Software Bill of Materials**.

Think of it as an inventory/ingredients list for software.

For this VM, instead of only saying:

> "This is an Ubuntu server"

the SBOM can say:

> "This host contains these OS packages, runtimes, tools, Docker images, services, and other software components."

A CycloneDX SBOM can contain component names, versions, package URLs (PURLs), types, licenses, hashes/evidence, and relationships/properties depending on what the generator knows.

---

# 8. What is a vulnerability?

A vulnerability is a weakness/defect in software that could potentially be exploited to affect confidentiality, integrity, availability, or otherwise create security risk.

Example:

A VM contains:

`some-package 1.2.3`

If a vulnerability database says that version `1.2.3` is affected by a known CVE, Dependency-Track can associate that vulnerability with the component and therefore with the project containing the component.

---

# 9. What is a CVE?

CVE = **Common Vulnerabilities and Exposures**.

A CVE is a standardized identifier for a publicly known vulnerability.

Example format:

`CVE-2026-XXXXX`

Dependency-Track can correlate SBOM components with vulnerability intelligence and show affected components/projects.

Important point:

**The SBOM itself does not magically prove that a component is vulnerable.**

The SBOM provides the component identity/version. Dependency-Track performs vulnerability analysis against vulnerability intelligence.

---

# 10. What is a zero-day vulnerability?

A zero-day vulnerability is a vulnerability that is unknown to the organization/vendor or for which there is not yet an effective available fix/mitigation at the time it is being exploited or disclosed.

SBOM + Dependency-Track is primarily useful for **known vulnerability exposure and software supply-chain visibility**. It does not guarantee detection of every zero-day.

---

# 11. Dependency-Track — what it does

Dependency-Track is a Software Composition Analysis / component analysis platform.

The flow is:

```text
GCP VM
   |
   | Host SBOM collector
   v
CycloneDX SBOM
   |
   | Upload
   v
Dependency-Track
   |
   +--> Component inventory
   +--> Vulnerability analysis
   +--> License analysis
   +--> Policy evaluation
   +--> Risk prioritization
   +--> Audit / triage
   +--> Impact analysis
```

Dependency-Track can continuously analyze components and identify known vulnerabilities and other risks.

---

# 12. Dependency-Track dashboard — what the main sections mean

## Dashboard / Portfolio

The portfolio is the collection of projects being tracked.

It gives the security/team a high-level view of risk across projects.

For this demo, the host VM is represented as a project.

---

## Projects

A project represents an application, system, environment, device, or other logical software grouping.

Our project represents the host SBOM being tracked.

Inside a project, Dependency-Track can show:

- Components
- Vulnerabilities
- Services
- Dependency Graph
- Audit findings
- Policy violations
- Metrics

---

## Components

This is the actual software inventory received from the SBOM.

For our host SBOM, examples include:

- Ubuntu/Debian packages
- Python packages/runtime components
- Executables
- Docker images
- Other discovered software

The latest collector generated **499 SBOM components**.

Earlier test versions produced different component counts because the collector was still being developed and its discovery logic was changing.

---

## Vulnerabilities

This section shows vulnerabilities associated with components.

The important relationship is:

```text
Component
   ↓
Known vulnerability
   ↓
Affected project
   ↓
Risk / severity
```

Dependency-Track uses vulnerability intelligence sources and analyzers to determine known vulnerability exposure.

---

## Dependency Graph

Shows relationships between projects/components/dependencies.

For a normal application SBOM, this can help answer:

> "What depends on this component?"

For a host-level SBOM, the graph depends on how much dependency relationship information the collector can establish.

---

## Services

Services represent external/internal service dependencies recorded in a BOM.

For our current host SBOM, the collector is separately discovering running Linux services as inventory information. We should distinguish that from Dependency-Track's service model rather than claiming every Linux service is automatically a Dependency-Track service dependency.

---

## Audit / Vulnerability Audit

Audit is used to investigate findings and record decisions.

For example:

- Is this finding actually applicable?
- Is it a false positive?
- Is the vulnerability being accepted temporarily?
- Has the component been reviewed?

This provides an audit trail for security decisions.

---

## Policy Violations

Policies allow the organization to define rules for:

### Security

Example:

> Critical vulnerabilities are not allowed.

### License

Example:

> A particular license family is not permitted.

### Operational

Example:

> Do not allow components older than a defined age or outside approved coordinates.

Policies are evaluated when BOMs are uploaded/processed.

---

## Licenses

This helps identify the licenses associated with components.

This matters because organizations may have rules about which open-source licenses are acceptable.

---

## Tags

Tags can be used to organize/classify projects and components.

Examples could be:

- production
- development
- critical
- backend
- infrastructure

---

## Administration

Administration is where the Dependency-Track platform itself is configured.

Depending on permissions/version, this can include:

- Users
- Teams
- Permissions
- API keys
- System configuration
- Integrations
- Repositories
- Notifications
- Policy configuration

---

# 13. What is a Team in Dependency-Track?

A **Team** is a collection of managed/unmanaged users and API keys.

Teams are mainly useful for:

- grouping users;
- assigning permissions;
- managing access;
- using API keys for automation;
- controlling who can perform actions such as BOM upload, vulnerability analysis, policy management, etc.

Example:

```text
Security Team
   |
   +-- Security Engineer
   +-- Security Analyst
   +-- API Key
```

A team is therefore **not the same thing as a project**.

Simple distinction:

```text
Project = What are we tracking?

Team   = Who can access/manage it?
```

---

# 14. Why Dependency-Track is useful for our VM

Without the SBOM:

```text
VM
 ├── many packages
 ├── runtimes
 ├── tools
 ├── containers
 └── services

Security team has to manually identify everything.
```

With the SBOM:

```text
VM
  ↓
CycloneDX SBOM
  ↓
Dependency-Track
  ↓
Central component inventory
  ↓
Known vulnerability analysis
  ↓
Risk / policy / license visibility
```

This makes the VM's software supply-chain inventory easier to review and track.

---

# 15. What worked

- Host-level SBOM generation works.
- Python 3.10 is now represented correctly.
- APT/DPKG package discovery works.
- Dynamic executable discovery works.
- Docker image discovery works.
- Running service discovery works.
- CycloneDX JSON is generated.
- Local CycloneDX validation passes.
- The SBOM is copied to `/home/ubuntu/host-sbom.json`.
- The systemd service runs successfully.
- The systemd timer is enabled for every 5 hours.
- The latest BOM was successfully uploaded into Dependency-Track.
- Dependency-Track accepted the latest BOM after the previous invalid-schema upload issue was resolved.

---

# 16. What did not work earlier

### Python was missing from the SBOM

Cause:
- Earlier runtime classification/discovery logic did not create the correct Python component.

Resolution:
- Reworked executable/runtime discovery and component creation.
- Verified Python 3.10 package and executable evidence in the generated BOM.

### Collector failed with tuple-unpacking error

Error:

`ValueError: too many values to unpack (expected 2)`

Cause:
- `classify_software()` return handling and the caller did not match.

Resolution:
- Corrected the collector logic.

### Some early runs were terminated

Error:

`status=15/TERM`

Cause:
- Earlier generation runs were being terminated while the collector/service was being changed or restarted, and some scans were long-running.

Resolution:
- Final run completed normally with status `0/SUCCESS`.

### Dependency-Track rejected an earlier BOM

The UI showed:

`The uploaded BOM is invalid`
`Schema validation failed`

Cause:
- The earlier generated BOM did not satisfy the CycloneDX schema expected by Dependency-Track.

Resolution:
- The final generator now performs local CycloneDX validation before the upload copy is produced.
- The latest BOM passed validation and was accepted by Dependency-Track.

---

# 17. Current state

### Host SBOM

Primary:

`/var/lib/host-sbom/host-sbom.json`

Upload/demo copy:

`/home/ubuntu/host-sbom.json`

### Service

`host-sbom.service`

### Timer

`host-sbom.timer`

### Schedule

Every 5 hours.

### Latest generation

Successful.

### Latest component count

499.

### CycloneDX validation

PASS.

### Dependency-Track upload

Successful.

---

# 18. Demo flow for the team

Use this order during the demo:

### Step 1 — Show the VM

Explain:

> "This is the GCP VM from which I am generating a host-level SBOM."

### Step 2 — Show the service

Show:

`systemctl status host-sbom.service`

Explain:

> "The SBOM collector runs as a Linux systemd service."

### Step 3 — Show the timer

Show:

`systemctl status host-sbom.timer`

Explain:

> "The timer triggers the SBOM generation every 5 hours."

### Step 4 — Show the generated file

Show:

`ls -lh /var/lib/host-sbom/host-sbom.json /home/ubuntu/host-sbom.json`

Explain:

> "The validated CycloneDX SBOM is stored locally and a copy is placed in the upload location."

### Step 5 — Show Python

Search the JSON for:

`python3.10`

Explain:

> "Python is dynamically detected and represented with package and executable evidence."

### Step 6 — Show Dependency-Track

Open the project and explain:

- Components
- Vulnerabilities
- Dependency Graph
- Audit
- Policy Violations
- Licenses
- Tags

### Step 7 — Explain the security value

Finish with:

> "The important part is that the SBOM gives us an inventory of what is actually present on the host, while Dependency-Track turns that inventory into vulnerability, license, policy, and risk visibility."

---

# 19. Important clarification for the demo

Do not say:

> "The SBOM detects every vulnerability."

Say:

> "The SBOM identifies the components and versions present on the host. Dependency-Track correlates those components with vulnerability intelligence and other risk data."

Also do not say:

> "Zero vulnerabilities means the host is completely secure."

Say:

> "At the time of analysis, Dependency-Track has not identified a matching known vulnerability in the analyzed components."

---

# 20. Next steps

1. Demonstrate the Dependency-Track project.
2. Verify the latest component count in the UI.
3. Review vulnerability analysis.
4. Review licenses.
5. Configure security/license/operational policies.
6. Review audit workflow.
7. Configure appropriate Dependency-Track users/teams and permissions.
8. Later, automate SBOM upload directly to Dependency-Track instead of using the local upload copy.
9. Consider integrating the SBOM generation/upload into CI/CD after the host-level implementation is accepted.
