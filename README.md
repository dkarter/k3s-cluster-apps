# K3S Cluster Apps

Repository for managing apps on my Raspberry Pi K3s bare metal cluster

## TODO:

- [ ] move onepassword-connect to be managed by ArgoCD
- [ ] Setup more apps:
  - [x] FreshRSS
  - [ ] LiveBook
  - [ ] LibReddit
  - [ ] PiAlert
  - [ ] WG Easy
  - [ ] Monica
  - [ ] Homebox
  - [ ] NTFY
  - [ ] SpeedTestExporter
  - [ ] \*arr suite?
  - [ ] GlueTun
    - [ ] Route FreshRSS + Arr
  - [ ] Sshwifty
  - [ ] ChangeDetection
- [ ] add readiness and liveness probes to deployments
- [ ] Set up a backup from longhorn using a NAS + [MinIO](https://min.io/)
  - find out if possible to automate this in the pvc provisioning

## Maybe

- Add MinIO operator https://github.com/minio/operator
- automate UptimeKuma service discovery
- automate prometheus service discovery
