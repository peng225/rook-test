# rook-test

Create and play with a rook test cluster.

## Prerequisites

If you would like to use RBD, please set up kvm.

## How to use

1. Edit `Makefile` to set version parameters (eg. `ROOK_VERSION`) and `OSD_COUNT`.
   - If you would like to deploy OSD in the raw mode, set `DEVICE_MODE` to "raw".
   - If you would like to use RGW, RBD or CephFS, you should write configurations in appropriate values file.
     - raw mode: manifest/raw_cluster_values.yaml
     - pvc mode: manifest/pvc_cluster_values.yaml
   - If you would like to use RBD, set `DRIVER` to "kvm".
2. Run `make create-cluster`.
3. Run `make deploy` and wait until all of OSDs start up.
4. Run `make clean` to destroy the cluster.
