# Dependency-Track

## 1. Think of Dependency-Track like an enterprise security database.

    Dependency-Track
    │
    ├── Portfolio
    │     │
    │     ├── Project A
    │     │      ├── Version 1.0
    │     │      │      ├── Components
    │     │      │      ├── Vulnerabilities
    │     │      │      └── Licenses
    │     │      │
    │     │      └── Version 2.0
    │     │
    │     ├── Project B
    │     │
    │     └── Project C
    │
    └── Policies
          ├── Vulnerability policies
          ├── License policies
          └── Component policies
          
### The important relationship is:

    Portfolio → Projects → Versions → Components → Vulnerabilities/Licenses
---
## 2. What is a Project?

A Project represents one software/product/application/asset that you want Dependency-Track to track.

For your VM demo, we could create:
  
    Project: predigle-helpdesk-dev-vm    

Then:

    Project
    └── Version: current
          └── vm-sbom.json

The SBOM tells Dependency-Track:
"These are the components currently present in this asset."

---

## 3. What is a Project Version?

Dependency-Track needs to know which version/revision of the project the SBOM represents.

For an application:

    helpdesk-app
    │
    ├── 1.0.0
    ├── 1.1.0
    └── 2.0.0
 
For an POC VM:   
  
    predigle-helpdesk-dev-vm
    Version: current

The important thing is to establish a consistent naming/versioning convention before you automate dozens of assets

---
## 4. What is a Component?

A component is an individual software dependency/package identified inside the SBOM.

Your Syft SBOM might contain components such as:
  
    Python
    OpenSSL
    curl
    libssl
    Ubuntu packages
    pip packages
    Docker-related packages
 
Conceptually for an VM:   
    
    VM
     │
     ├── OpenSSL
     ├── Python
     ├── curl
     ├── ...
     └── ...

Dependency-Track takes these components and tries to identify:

    known vulnerabilities
    licenses
    component metadata
    dependency relationships

---

## 5. What is a Vulnerability?

A vulnerability is a known security weakness associated with a component.

For example:

    Component
       │
       ▼
    OpenSSL 3.x
       │
       ▼
    CVE
       │
       ▼
    CVSS score

Dependency-Track correlates the components from your SBOM against vulnerability intelligence.

That's one of the major reasons we're uploading the SBOM.

---

## 6. What is a Portfolio?


A Portfolio is essentially the collection/view of all your projects in Dependency-Track.

Think of it like your company's application inventory.
    
For example: This is important for your future 70 repositories.

    Predigle Portfolio
    │
    ├── Helpdesk Application
    ├── Payment Service
    ├── Authentication Service
    ├── Customer Portal
    ├── Mobile Backend
    ├── VM - Helpdesk Dev
    ├── VM - Production API
    └── ...

The portfolio lets security/platform teams look at the overall risk across many projects.

Portfolio ≠ Project.

A project is an individual tracked asset.
A portfolio is the overall collection of projects.

---

## 7. What is an SBOM?

Your: `vm-sbom.json` is the SBOM document.

It contains information about the software components Syft discovered.

You generated it as:
    
    sudo ~/tools/bin/syft dir:/ \
        -o cyclonedx-json=vm-sbom.json

SO:

    VM filesystem
          ↓
    Syft
          ↓
    CycloneDX JSON
          ↓
    vm-sbom.json
    
Dependency-Track consumes that SBOM.   

---

## 8. What do we actually need before uploading?

For the manual demo, we need:

Required
  
    1. Dependency-Track running
            ↓
    2. User account
            ↓
    3. Project
            ↓
    4. Project version
            ↓
    5. SBOM
            ↓
    6. API key OR UI upload
--- 

## 9. Where does the SBOM go?

Think of the upload like this:

    vm-sbom.json
          │
          │ Upload
          ▼
    Dependency-Track
          │
          ▼
    Project
          │
          ▼
    Project Version
          │
          ▼
    Components
          │
          ├── Vulnerabilities
          ├── Licenses
          └── Dependency relationships
          
The SBOM itself isn't normally something you browse as a big JSON file inside Dependency-Track.
Dependency-Track imports and parses it

---

## 10. What happens when we upload your VM SBOM?

This is the most important concept.
    
    You have: 42 MB vm-sbom.json
    
    Suppose Syft discovered: 10,000+ packages/files/components

When you upload it:
    
    Dependency-Track
           │
           ▼
    Parse CycloneDX
           │
           ▼
    Identify components
           │
           ▼
    Normalize component identities
           │
           ▼
    Match vulnerability intelligence
           │
           ├── CVEs
           ├── CVSS
           └── other findings
           │
           ▼
    Apply policies
           │
           ▼
    Dashboard

That's why the SBOM is valuable.

---

## 11. Where do Policies fit?

Later we'll create policies such as:

    IF vulnerability severity >= HIGH
    THEN policy violation

or:

    IF forbidden license
    THEN policy violation

Then Dependency-Track can show:

    Project
    │
    ├── 5 vulnerabilities
    ├── 2 policy violations
    └── 1 license risk
---
## 12. Your future 70-repository architecture

This is where the portfolio concept becomes useful.

    Imagine you onboard: 70 GitHub repositories
    
    You don't want:
    
    Portfolio
    └── Everything mixed together
    
  ### Instead, you could establish organizational conventions such as:
    
      Predigle Applications
    │
    ├── helpdesk
    ├── payment-service
    ├── auth-service
    └── customer-portal
    
    Predigle Infrastructure
    │
    ├── helpdesk-dev-vm
    ├── helpdesk-prod-vm
    └── api-prod-vm

NOTE: The exact portfolio/project organization should be decided with your lead/security team,
because naming and ownership conventions become important once you have dozens of repositories.

---

### 13. One very important concept: SBOM ≠ Scan

This connects directly to what we discussed earlier.

## Syft answers: What software/components are present?"
  
    VM
     ↓
    Syft
     ↓
    SBOM

## Dependency-Track answers: What risk is associated with those components?"
    
    SBOM
     ↓
    Dependency-Track
     ↓
    Vulnerability + license + policy analysis

## Trivy: Trivy can perform immediate scanning during CI/CD.

    Source/Image/Filesystem
     ↓
    Trivy
     ↓
    Security findings
## 
