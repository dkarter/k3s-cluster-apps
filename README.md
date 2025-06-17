# K3S Cluster Apps

Repository for managing apps on my Raspberry Pi K3s bare metal cluster using GitOps with ArgoCD.

## Applications

### Infrastructure & Core Services
- **ArgoCD** - GitOps continuous delivery tool managing all applications
- **External Secrets** - Integrates with 1Password Connect for secure secret management
- **Longhorn** - Distributed block storage system for persistent volumes
- **Cert Manager** - Automatic TLS certificate provisioning and management
- **CNPG** - Cloud Native PostgreSQL operator for database management

### Media Management
- **Sonarr** - TV series collection manager and PVR
- **Radarr** - Movie collection manager and PVR
- **Bazarr** - Subtitle management for Sonarr and Radarr
- **Prowlarr** - Indexer manager for Sonarr and Radarr
- **Jellyfin** - Free media server for streaming movies and TV shows
- **Jellyseerr** - Request management and media discovery tool
- **SABnzbd** - Usenet newsreader and downloader
- **Browsarr** - Web browser interface for media management
- **Pinchflat** - YouTube channel archiver and downloader

### Monitoring & Observability
- **Monitoring Stack** - Grafana and Prometheus for metrics and dashboards
- **Uptime Kuma** - Uptime monitoring and status page

### Productivity & Tools
- **Homepage** - Customizable dashboard for accessing all services
- **Linkding** - Bookmark manager with tagging and search
- **Memos** - Lightweight note-taking and memo service
- **FreshRSS** - RSS/Atom feed aggregator and reader
- **Livebook** - Interactive notebooks for Elixir development
- **n8n** - Workflow automation platform
- **Paperless** - Document management system with OCR
- **Changedetection.io** - Website change monitoring and notifications

### Network & Security
- **AdGuard Home** - Network-wide ad blocker and DNS server
- **WG Easy** - Simple WireGuard VPN server management

## Usage

This repository uses [Task](https://taskfile.dev/) for common operations:

```bash
# List all available tasks
task

# Open ArgoCD web interface
task argo:open

# Open Longhorn web interface
task longhorn:open

# Scale down/up all media services (useful for maintenance)
task media:scale_down
task media:scale_up

# List and manage GitHub PRs
task gh:prs:list
task gh:automerge:renovate
```

## TODO

- [ ] move onepassword-connect to be managed by ArgoCD
- [ ] Setup more apps:
  - [ ] SpeedTestExporter
  - [ ] GlueTun
    - [ ] look into this https://github.com/thavlik/vpn-operator
    - [ ] Route FreshRSS + Arr
- [ ] Set up a backup from longhorn using a NAS + [MinIO](https://min.io/)
  - find out if possible to automate this in the pvc provisioning
- [ ] add redundancy to adguard - can't use the same app due to potential pvc corruption
- [ ] finish adding exportarr to all media services
- [ ] add additional observability
- [ ] look into setting up Tailscale operator

## Maybe

- Add MinIO operator https://github.com/minio/operator
- automate UptimeKuma service discovery
- automate prometheus service discovery
