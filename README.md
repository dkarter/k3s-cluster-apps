# K3S Cluster Apps

Repository for managing apps on my Raspberry Pi K3s bare metal cluster

## TODO:

- [ ] move onepassword-connect to be managed by ArgoCD
- [ ] Setup more apps:
  - [ ] WG Easy
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
