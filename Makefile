ROOK_VERSION := 1.10.6
CEPH_VERSION := 17.2.5
MINIKUBE_VERSION := 1.28.0
KUBECTL_VERSION := 1.25.4
YQ_VERSION := 4.30.4

BIN_DIR := bin
KUBECTL := $(BIN_DIR)/kubectl_$(KUBECTL_VERSION)
MINIKUBE := $(BIN_DIR)/minikube_$(MINIKUBE_VERSION)
YQ := $(BIN_DIR)/yq_$(YQ_VERSION)

OSD_COUNT := 2

MANIFEST_DIR := manifest

$(BIN_DIR):
	mkdir $(BIN_DIR)

$(MINIKUBE): | $(BIN_DIR)
	curl -LO https://storage.googleapis.com/minikube/releases/v$(MINIKUBE_VERSION)/minikube-linux-amd64
	mv minikube-linux-amd64 $(MINIKUBE)
	chmod +x $(MINIKUBE)

$(KUBECTL): | $(BIN_DIR)
	curl -LO https://dl.k8s.io/release/v1.25.0/bin/linux/amd64/kubectl
	mv kubectl $(KUBECTL)
	chmod +x $(KUBECTL)

$(YQ): | $(BIN_DIR)
	curl -LO https://github.com/mikefarah/yq/releases/download/v$(YQ_VERSION)/yq_linux_amd64
	mv yq_linux_amd64 $(YQ)
	chmod +x $(YQ)

$(MANIFEST_DIR):
	mkdir $(MANIFEST_DIR)

$(MANIFEST_DIR)/crds.yaml: | $(MANIFEST_DIR)
	curl -L https://github.com/rook/rook/raw/v$(ROOK_VERSION)/deploy/examples/crds.yaml -o $@

$(MANIFEST_DIR)/common.yaml: | $(MANIFEST_DIR)
	curl -L https://github.com/rook/rook/raw/v$(ROOK_VERSION)/deploy/examples/common.yaml -o $@

$(MANIFEST_DIR)/operator.yaml: | $(MANIFEST_DIR) $(YQ)
	curl -L https://github.com/rook/rook/raw/v$(ROOK_VERSION)/deploy/examples/operator.yaml -o $@
	$(YQ) -i '(select(.metadata.name == "rook-ceph-operator-config") | .data.ROOK_CEPH_ALLOW_LOOP_DEVICES) = "true"' $@

$(MANIFEST_DIR)/cluster-test.yaml: | $(MANIFEST_DIR) $(YQ)
	curl -L https://github.com/rook/rook/raw/v$(ROOK_VERSION)/deploy/examples/cluster-test.yaml -o $@
	$(YQ) -i '(select(.spec.cephVersion) | .spec.cephVersion.image) = "quay.io/ceph/ceph:v$(CEPH_VERSION)"' $@
	$(YQ) -i '(select(.spec.storage) | .spec.storage.useAllNodes) = false' $@
	$(YQ) -i '(select(.spec.storage) | .spec.storage.useAllDevices) = false' $@
	$(YQ) -i '(select(.spec.storage) | .spec.storage.nodes) = [{"name": "minikube", "devices": [{"name": "loop0"}, {"name": "loop1"}]}]' $@

.PHONY: gen
gen: $(MANIFEST_DIR)/crds.yaml $(MANIFEST_DIR)/common.yaml $(MANIFEST_DIR)/operator.yaml $(MANIFEST_DIR)/cluster-test.yaml

.PHONY: create-cluster
create-cluster: $(MINIKUBE)
	$(MINIKUBE) start --driver=docker --cpus=2 --memory=2g --disk-size 10gb
	for i in $$(seq 0 $$(expr $(OSD_COUNT) - 1)); do \
		dd if=/dev/zero of=loop$${i} bs=1 count=0 seek=6G; \
		sudo losetup /dev/loop$${i} loop$${i}; \
	done

.PHONY: deploy
deploy: $(KUBECTL) $(MANIFEST_DIR)/crds.yaml $(MANIFEST_DIR)/common.yaml $(MANIFEST_DIR)/operator.yaml $(MANIFEST_DIR)/cluster-test.yaml
	$(KUBECTL) apply -f $(MANIFEST_DIR)/crds.yaml -f $(MANIFEST_DIR)/common.yaml -f $(MANIFEST_DIR)/operator.yaml
	$(KUBECTL) apply -f $(MANIFEST_DIR)/cluster-test.yaml
# tools and RGW

.PHONY: clean
clean:
	$(MINIKUBE) stop
	$(MINIKUBE) delete
	sudo losetup -D
	for i in $$(seq 0 $$(expr $(OSD_COUNT) - 1)); do \
		rm -rf loop$${i}; \
	done
