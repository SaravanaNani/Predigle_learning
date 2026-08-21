# Now your bigger question: why do you have multiple Cloud Build YAML files?

This is completely valid.
A repository can absolutely have multiple Cloud Build configuration files.

Cloud Build does not work like:

    cloudbuild.yaml
      ↓
    cloudbuild-2.yaml
      ↓
    cloudbuild-3.yaml
    
just because the files are sitting in the same directory.
This is the most important thing to understand.
The filename itself does NOT create a hierarchy.

For example, having:
  
    cloudbuild.yaml
    cloudbuild-base.yaml
    cloudbuild-deployment.yaml
    cloudbuild.workflow.yaml
    
doesn't automatically mean:

    cloudbuild.yaml
          ↓
    cloudbuild-base.yaml
          ↓
    cloudbuild-deployment.yaml

No, They are simply four YAML files until something actually invokes them.
---
### Think of Cloud Build YAML files as "recipes"

Imagine you have:

    cloudbuild.yaml
    cloudbuild-base.yaml
    cloudbuild-deployment.yaml

Each file can describe a different build process.

For example:

    cloudbuild.yaml
        = Build application
    
    
    cloudbuild-base.yaml
        = Build base Docker image
    
    
    cloudbuild-deployment.yaml
        = Deploy application
    
    
    cloudbuild.workflow.yaml
        = Another build/deployment process
    
---
# How does Cloud Build know which YAML to use?

### Method 1 — Someone explicitly specifies the config

For example:

    gcloud builds submit \  --config=cloudbuild-deployment.yaml

That means:
    
    gcloud   
    ↓
    Cloud Build   
    ↓
    cloudbuild-deployment.yaml

If someone instead runs:

    gcloud builds submit \
      --config=cloudbuild-base.yaml
then:

    gcloud
       ↓
    Cloud Build
       ↓
    cloudbuild-base.yaml
So the command chooses the YAML.

---
### Method 2 — Cloud Build Trigger chooses it

This is very common in real environments.

A Cloud Build trigger can be configured roughly like:

    GitHub
    ↓
    Cloud Build Trigger
    ↓
    Configuration file:
    cloudbuild-base.yaml

Another trigger might be:
    
    GitHub
      ↓
    Cloud Build Trigger
      ↓
    Configuration file:
    cloudbuild-deployment.yaml
    
### Same repository. Different Cloud Build configuratio
    
    GitHub repository
           |
           +------------------+
           |                  |
           v                  v
    Trigger A             Trigger B
           |                  |
           v                  v
    cloudbuild.yaml      cloudbuild-deployment.yaml

---
### Method 3 — One Cloud Build file can invoke another process

A YAML file can also contain shell commands.
For example:

    steps:
      - name: ubuntu
        entrypoint: bash
        args:
          - -c
          - |
            ./deploy.sh

Then:

    cloudbuild.yaml
          ↓
    deploy.sh
          ↓
    docker build

Or it could invoke another Cloud Build command.
But again, we cannot assume your repository does this until we read the files.

---
#  Now let's understand your Dockerfiles

You have at least:

    Dockerfile
    base.dockerfile
    docker/nginx.Dockerfile

Again, there is no automatic hierarchy.
Having:
       
        Dockerfile
        base.dockerfile
    
does NOT mean Docker automatically does:
    
    Dockerfile
        ↓
    base.dockerfile

### Docker only uses a Dockerfile when a build command tells it to.
---

### Normal Docker behavior

If you run: `docker build .`

Docker looks for:
        
        ./Dockerfile

So:
    
    docker build .
           ↓
    Dockerfile

But you can explicitly specify another one:

    docker build -f base.dockerfile .

Then:

    docker build
         |
         +-- -f base.dockerfile
                  ↓
           base.dockerfile
    
And:

    docker build -f docker/nginx.Dockerfile .
    
    means:
    
    docker build
         |
         +-- docker/nginx.Dockerfile

So multiple Dockerfiles are completely normal.
---

# Dockerfiles CAN have a hierarchy

This is where it gets interesting.

### A Dockerfile can use another image as its base:

    FROM python:3.10
    
    or:
    
    FROM my-company-base:1.0
    
So you might have:

    base.dockerfile
          ↓
    build base image
          ↓
    company/python-base:1.0
          ↓
    Dockerfile
          ↓
    application image

### But again, this is determined by the FROM instruction and build commands, not by the filenames.
---

# Your repository might therefore have something like this

You could have:

                         GitHub
                           |
                           v
                     Cloud Build
                           |
              +------------+-------------+
              |                          |
              v                          v
       Base image build           Application build
              |                          |
              v                          v
       base.dockerfile             Dockerfile
              |                          |
              v                          v
       base image                 application image
                                         |
                                         v
                                    VM deployment

And separately:

    docker/nginx.Dockerfile
              |
              v
         nginx image

This would explain why a repository contains several Dockerfiles.
---

# Where do Compose files fit?

This is another important distinction.

You have:
    
    docker-compose.yml
    docker-compose.grpc.yml
    docker-compose.model.trainer.yml
    docker-compose.bot.optimizer.yml

### A Compose file describes services that should run together.

For example:
  
  services:
  
  
    web:
      build:
        context: .
        dockerfile: Dockerfile
  
  
    nginx:
      build:
        context: .
        dockerfile: docker/nginx.Dockerfile
  
  
    redis:
      image: redis:7

The relationship becomes:

    docker-compose.yml
           |
           +---- web
           |      |
           |      └── Dockerfile
           |
           +---- nginx
           |      |
           |      └── nginx.Dockerfile
           |
           └---- redis
                  |
                  └── redis:7

So Compose doesn't necessarily build everything itself.

It tells Docker:

    "For this service, build this image."
    
    or:
    
    "For this service, use this existing image."

---
### This is exactly why your SBOM needs to start from the deployment image

Now consider:

    requirements.txt
    Pipfile
    Pipfile.lock
    Dockerfile
    Compose files
    Cloud Build files

If I scan only: requirements.txt
I don't know exactly what ended up in the final image.

But if I scan: `FINAL_IMAGE`

I get the actual artifact.

That's why your requirement: "SBOM for images only"
is actually very sensible.

---
# Eventual SBOM pipeline should look like this

Assuming Cloud Build creates the production image:

                GitHub Repository
                       |
                       v
                 Cloud Build
                       |
                       v
                Docker build
                       |
                       v
              Final Docker image
                       |
                       v
               Artifact Registry
                       |
                       v
              GitHub Actions
                       |
                       v
                    Trivy
                       |
                       v
             CycloneDX image SBOM
                       |
              +--------+--------+
              |                 |
              v                 v
       GitHub Artifact    Dependency-Track

This is the architecture I now recommend for your requirement.
---

###  But there's an important architectural question

You have both:

    GitHub Actions
        and:
    Cloud Build

So we need to determine who actually builds the production image.

There are two possibilities.

Scenario A

GitHub Actions builds it:
    
    GitHub
      ↓
    GitHub Actions
      ↓
    docker build
      ↓
    Image
  
Then our SBOM can simply run after that build.

Scenario B

    Cloud Build builds it:
    
    GitHub
      ↓
    Cloud Build
      ↓
    Docker build
      ↓
    Artifact Registry
      ↓
    VM

Then I would prefer:

    GitHub Actions
          ↓
    identify exact image/tag
          ↓
    pull exact production image
          ↓
    Trivy
          ↓
    SBOM

rather than rebuilding the image in GitHub Actions. Why?
Because you want to scan the exact artifact that is deployed.
