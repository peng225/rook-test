# rook-test
Create and play with a rook test cluster.

## How to use

1. Edit `Makefile` to set version parameters (eg. `ROOK_VERSION`) and `OSD_COUNT`.
   - If you would like to deploy RGW later, set `OBJECT_STORE_CONSUMER_NS`, too.
   - If you would like to deploy a PVC-based cluster, set `DEVICE_MODE`, too.
2. Run `make create-cluster`.
3. Run `make gen` and edit manifests in the `manifest` directory as you like.
4. Run `make deploy` and wait until all of OSDs start up.
   - If you would like to deply RGW, run `make rgw` after the cluster has started.
5. Run `make clean` to destroy the cluster.
