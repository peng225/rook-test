ROOK_VERSION := 1.10.6
CEPH_VERSION := 17.2.5
MINIKUBE_VERSION := 1.28.0
KUBECTL_VERSION := 1.25.4
YQ_VERSION := 4.30.4

BIN_DIR := bin
KUBECTL := $(BIN_DIR)/kubectl_$(KUBECTL_VERSION)
MINIKUBE := $(BIN_DIR)/minikube_$(MINIKUBE_VERSION)
YQ := $(BIN_DIR)/yq_$(YQ_VERSION)

# TODO: Support OSD_COUNT for raw mode (Currently, it cannot be changed)
OSD_COUNT := 1
OBJECT_STORE_CONSUMER_NS := default
# "raw" or "pvc"
DEVICE_MODE := pvc
# "docker" or "kvm"
DRIVER=docker

MANIFEST_DIR := manifest

MANIFEST_FILES := $(MANIFEST_DIR)/crds.yaml $(MANIFEST_DIR)/common.yaml $(MANIFEST_DIR)/operator.yaml $(MANIFEST_DIR)/cluster-test.yaml $(MANIFEST_DIR)/toolbox.yaml $(MANIFEST_DIR)/object-test.yaml $(MANIFEST_DIR)/storageclass-bucket-delete.yaml $(MANIFEST_DIR)/object-bucket-claim-delete.yaml
RBD_MANIFEST_FILES := $(MANIFEST_DIR)/storageclass-test.yaml $(MANIFEST_DIR)/pvc.yaml
RGW_MANIFEST_FILES := $(MANIFEST_DIR)/object-test.yaml $(MANIFEST_DIR)/storageclass-bucket-delete.yaml $(MANIFEST_DIR)/my-object-bucket-claim-delete.yaml

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

$(MANIFEST_FILES): | $(MANIFEST_DIR)
	curl -L https://github.com/rook/rook/raw/v$(ROOK_VERSION)/deploy/examples/$(notdir $@) -o $@

$(RBD_MANIFEST_FILES): | $(MANIFEST_DIR)
	curl -L https://github.com/rook/rook/raw/v$(ROOK_VERSION)/deploy/examples/csi/rbd/$(notdir $@) -o $@

.PHONY: $(MANIFEST_DIR)/my-operator.yaml
$(MANIFEST_DIR)/my-operator.yaml: $(MANIFEST_DIR)/operator.yaml | $(MANIFEST_DIR) $(YQ)
	$(YQ) '(select(.metadata.name == "rook-ceph-operator-config") | .data.ROOK_CEPH_ALLOW_LOOP_DEVICES) = "true"' $< > $@

.PHONY: $(MANIFEST_DIR)/my-cluster-test.yaml
$(MANIFEST_DIR)/my-cluster-test.yaml: $(MANIFEST_DIR)/cluster-test.yaml | $(MANIFEST_DIR) $(YQ)
	$(YQ) '(select(.spec.cephVersion) | .spec.cephVersion.image) = "quay.io/ceph/ceph:v$(CEPH_VERSION)"' $< | \
	$(YQ) '(select(.spec.storage) | .spec.storage.useAllNodes) = false' | \
	$(YQ) '(select(.spec.storage) | .spec.storage.useAllDevices) = false' > $@
ifeq ($(DEVICE_MODE), raw)
	$(YQ) -i '(select(.spec.storage) | .spec.storage.nodes) = [{"name": "minikube", "devices": [{"name": "loop0"}, {"name": "loop1"}]}]' $@
else ifeq ($(DEVICE_MODE), pvc)
	$(YQ) -i '(select(.spec.storage) | .spec.storage.storageClassDeviceSets) = [{"name": "set1", "count": $(OSD_COUNT), "volumeClaimTemplates": [{"metadata": {"name": "data0"}, "spec": {"resources":{"requests":{"storage": "6Gi"}}, "storageClassName": "", "volumeMode": "Block", "accessModes": ["ReadWriteOnce"]}}]}]' $@
else
	echo "Invalid DEVICE_MODE $(DEVICE_MODE)"
	rm $@
	exit 1
endif

.PHONY: $(MANIFEST_DIR)/my-object-bucket-claim-delete.yaml
$(MANIFEST_DIR)/my-object-bucket-claim-delete.yaml: $(MANIFEST_DIR)/object-bucket-claim-delete.yaml | $(MANIFEST_DIR) $(YQ)
	$(YQ) '.metadata.namespace = "$(OBJECT_STORE_CONSUMER_NS)"' $< > $@

.PHONY: gen
gen: $(MANIFEST_FILES) $(RBD_MANIFEST_FILES) $(RGW_MANIFEST_FILES) $(MANIFEST_DIR)/my-operator.yaml $(MANIFEST_DIR)/my-cluster-test.yaml

.PHONY: create-cluster
create-cluster: $(MINIKUBE)
	$(MINIKUBE) start --driver=$(DRIVER) --cpus=2 --memory 6g --disk-size 10gb
	for i in $$(seq 0 $$(expr $(OSD_COUNT) - 1)); do \
		$(MINIKUBE) ssh -- dd if=/dev/zero of=loop$${i} bs=1 count=0 seek=6G; \
		$(MINIKUBE) ssh -- sudo losetup /dev/loop$${i} loop$${i}; \
	done
	$(MINIKUBE) ssh -- lsblk
	$(MINIKUBE) ssh -- docker pull rook/ceph:v$(ROOK_VERSION)
	$(MINIKUBE) ssh -- docker pull quay.io/ceph/ceph:v$(CEPH_VERSION)

.PHONY: deploy
deploy: $(KUBECTL) $(MANIFEST_DIR)/crds.yaml $(MANIFEST_DIR)/common.yaml $(MANIFEST_DIR)/my-operator.yaml $(MANIFEST_DIR)/my-cluster-test.yaml $(MANIFEST_DIR)/toolbox.yaml pv
	$(KUBECTL) apply -f $(MANIFEST_DIR)/crds.yaml -f $(MANIFEST_DIR)/common.yaml -f $(MANIFEST_DIR)/my-operator.yaml
	$(KUBECTL) apply -f $(MANIFEST_DIR)/my-cluster-test.yaml -f $(MANIFEST_DIR)/toolbox.yaml

.PHONYE: pv
pv: $(MANIFEST_DIR)/pv-template.yaml
ifeq ($(DEVICE_MODE), pvc)
	for i in $$(seq 0 $$(expr $(OSD_COUNT) - 1)); do \
		$(YQ) ".metadata.name = \"pv$${i}\"" $< | \
		$(YQ) ".spec.local.path = \"/dev/loop$${i}\"" | \
		$(KUBECTL) apply -f -; \
	done
endif

.PHONY: rgw
rgw: $(KUBECTL) $(RGW_MANIFEST_FILES)
	$(KUBECTL) apply -f $(MANIFEST_DIR)/object-test.yaml
	$(KUBECTL) apply -f $(MANIFEST_DIR)/storageclass-bucket-delete.yaml
	$(KUBECTL) apply -f $(MANIFEST_DIR)/my-object-bucket-claim-delete.yaml

.PHONY: rbd
rbd: $(KUBECTL) $(MANIFEST_DIR)/storageclass-test.yaml
	$(KUBECTL) apply -f $(MANIFEST_DIR)/storageclass-test.yaml

.PHONY: clean
clean:
	if [ $(DRIVER) = "docker" ]; then \
		sudo losetup -D; \
	fi
	$(MINIKUBE) stop
	$(MINIKUBE) delete
