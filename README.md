# rook-test
Create and play with a rook test cluster.

## How to use

1. Edit `Makefile` to set version parameters (eg. `ROOK_VERSION`) and `OSD_COUNT`.
2. Run `make create-cluster`.
3. Run `make gen` and edit manifests in the `manifest` directory as you like.
4. Run `make deploy` and wait until all of OSDs start up.
5. Run `make clean` to destroy the cluster.
