# First: The complete flow

Let's do the REST API/cURL method properly. Since you're on Dependency-Track 4.13.0, I'll use the 4.13 behavior, especially its API-key model.

For your local lab:

    Windows laptop
       │
       │ vm-sbom.json
       │
       ▼
    curl
       │
       │ HTTPS/HTTP POST
       │ X-Api-Key
       │ multipart/form-data
       ▼
    Dependency-Track API
    localhost:8081
       │
       ▼
    Project
    predigle-helpdesk-dev-vm
       │
       ▼
    Version
    2026-08-10
       │
       ▼
    BOM processing
       │
       ├── Components
       ├── Vulnerabilities
       ├── Licenses
       └── Dependency relationships

The important point is:

    Your browser UI is on port 8080, but the REST API is on port 8081 in our Docker setup.
    Dependency-Track's documentation also notes that the backend/OpenAPI endpoints are on the API server, not the frontend

### 1. What is an API key?

An API key is a secret credential that allows a program such as:

    curl
    GitHub Actions
    Jenkins
    Python script

to authenticate to Dependency-Track's REST API.

---

# Uploading SBOM and Setting Up Project:

## 1. Create the Team

In Dependency-Track:
    
    Administration
       ↓
    Access Management
       ↓
    Teams
       ↓
    Create Team
---
## 2. Create an API key

Open the team: DevSecOps-BOM-Uploader

    Find: -> API Keys -> Create: New API Key

## NOTE: 

Dependency-Track 4.13 changed API keys significantly:
keys are stored as SHA3-256 hashes and the full secret is shown only once when created. New keys use the format:

So copy the complete key immediately and store it securely.

For example, conceptually:

    odt_a1b2c3d4_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

---

## Why does the API key need a Team?

Because Dependency-Track needs to answer:

"What is this API client allowed to do?"

For example:
    
    API key
       ↓
    DevSecOps-BOM-Uploader
       ↓
    BOM_UPLOAD
    
    So when cURL says:
    
    X-Api-Key: odt_...

Dependency-Track can determine:

    Who/what owns this key?
            ↓
    Team
            ↓
    Permissions
            ↓
    Allow / deny API operation

That's authorization.

---

## 3. Create Project: `DevSecOps-BOM-Uploader` 

Then assign Permission : `BOM_UPLOAD`

For our first test, do not give it full administration permissions.

---

## 4. Find your Project UUID

You can create the project in the UI first:
    
    Projects
     ↓
    predigle-helpdesk-dev-vm
    
    Dependency-Track assigns it a UUID.

It will look like:

    f90934f5-cb88-47ce-81cb-db06fc67d4b4

Use the UUID from your actual project.
You can get it from the project page or API.

## Why do we need the Project UUID?

Because the API needs to know:

"Which Dependency-Track project should receive this SBOM?"

So the request becomes:

    SBOM
     +
    Project UUID
     +
    API key
---
# Uploading methods of SBOM

## 1. Now the actual cURL POST

    Your file is: vm-sbom.json
    
    Your local Dependency-Track API is: http://localhost:8081
    
    The endpoint is: POST /api/v1/bom

Dependency-Track documents POST as a multipart upload method that does not require Base64 encoding.

PowerShell command

Since you're using Windows PowerShell:

    curl.exe -X POST `
      "http://localhost:8081/api/v1/bom" `
      -H "X-Api-Key: YOUR_API_KEY" `
      -F "project=YOUR_PROJECT_UUID" `
      -F "bom=@C:\Users\hp\Downloads\vm-sbom.json"

Replace: YOUR_API_KEY with your newly generated key.

Replace: YOUR_PROJECT_UUID with the actual project's UUID.

And make sure the SBOM path is correct.

---

## Why curl.exe instead of curl?

    You're on Windows PowerShell.
    
    PowerShell can treat curl as an alias depending on environment/version.

    I prefer: curl.exe - because we explicitly mean the actual cURL executable.

What does -F mean?

This: -F means multipart form data.

We are sending:
    
    project = UUID
    bom     = file

Conceptually:
    
    POST /api/v1/bom
    
    multipart/form-data
    
    ┌─────────────────────────────┐
    │ project = UUID              │
    │                             │
    │ bom = vm-sbom.json          │
    └─────────────────────────────┘
    
    That's why we don't need Base64.

## Is your vm-sbom.json Base64?

No. Your file is:

    CycloneDX
    +
    JSON

For example:

    {
      "bomFormat": "CycloneDX",
      "specVersion": "...",
      "components": [...]
    }

That's your actual SBOM.

## With the POST method:

    vm-sbom.json
           ↓
    multipart/form-data
           ↓
    Dependency-Track
    
No Base64 conversion.
Dependency-Track explicitly documents this distinction: POST supports direct multipart BOM upload, while its PUT JSON method requires the BOM to be Base64 encoded in the bom field.
---

## 2. What does the PUT method look like?

You should understand this too, but don't use it yet.

PUT looks conceptually like:

    CycloneDX JSON
          ↓
    Base64 encode
          ↓
    JSON payload
    {
      "project": "PROJECT_UUID",
      "bom": "BASE64_ENCODED_DATA"
    }

Then:

    curl.exe -X PUT `
      "http://localhost:8081/api/v1/bom" `
      -H "Content-Type: application/json" `
      -H "X-Api-Key: YOUR_API_KEY" `
      -d "@payload.json"

## The official CI/CD documentation shows this PUT pattern and the POST alternative.

For your 42 MB SBOM, I prefer the POST multipart method.
---
## What should the POST response look like?

Dependency-Track accepts BOM processing asynchronously.
You should receive a response containing a processing token, conceptually:
    
    {
      "token": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    }

Then Dependency-Track processes:
    
    Upload
      ↓
    Queue
      ↓
    Parse BOM
      ↓
    Component identification
      ↓
    Vulnerability analysis

## So don't expect cURL itself to return the entire vulnerability report immediately.
---
## 3. Alternative: let cURL create the Project

There is another POST method:
    
    curl.exe -X POST `
      "http://localhost:8081/api/v1/bom" `
      -H "X-Api-Key: YOUR_API_KEY" `
      -F "autoCreate=true" `
      -F "projectName=predigle-helpdesk-dev-vm" `
      -F "projectVersion=2026-08-10" `
      -F "bom=@C:\Users\hp\Downloads\vm-sbom.json"
    
Dependency-Track supports autoCreate=true with project name/version.

But notice the security implication: BOM_UPLOAD

alone isn't enough for automatic project creation.

You need: PROJECT_CREATION_UPLOAD as well.

Enterprise recommendation
    
    For your future 70 repositories:
    
    Prefer pre-created projects + restricted BOM upload permissions where your onboarding process can manage project creation separately.
    
    Use autoCreate when your enterprise workflow deliberately wants CI/CD to create projects automatically.
---
# SBOM Extracting: 

### Script to SBOM INSTALLATION and EXTRACTION:


### COMMAND to RUN on VM to test - SBOM extraction of host
    
    sudo ~/tools/bin/syft dir:/usr \
      --exclude './var/lib/docker/**' \
      --exclude './var/lib/containerd/**' \
      -o cyclonedx-json@1.6=/root/tools/test-host-sbom.json
      
### COMMAND TO FECTH ALL HOST SBOM EXCEPT DOCKER     
    sudo ~/tools/bin/syft dir:/ \
      --exclude './var/lib/docker/**' \
      --exclude './var/lib/containerd/**' \
      -o cyclonedx-json@1.6=vm-host-sbom.json
      
