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



# Uploading SBOM and Setting Up Project:

Create the Team

In Dependency-Track:

    Administration
       ↓
    Access Management
       ↓
    Teams
       ↓
    Create Team
    
## Create: `DevSecOps-BOM-Uploader`

Then assign: BOM_UPLOAD
