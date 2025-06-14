ROOK_VERSION := 1.17.1
CEPH_VERSION := 19.2.2
MINIKUBE_VERSION := 1.35.0
YQ_VERSION := 4.45.4
HELM_VERSION := 3.18.2

BIN_DIR := bin
MINIKUBE := $(BIN_DIR)/minikube_$(MINIKUBE_VERSION)
YQ := $(BIN_DIR)/yq_$(YQ_VERSION)
HELM := $(BIN_DIR)/helm_$(HELM_VERSION)

OSD_COUNT := 1
OBJECT_STORE_CONSUMER_NS := default
# "raw" or "pvc"
DEVICE_MODE ?= pvc
# "docker" or "kvm"
DRIVER := docker

MANIFEST_DIR := manifest

$(BIN_DIR):
	mkdir $(BIN_DIR)

$(MINIKUBE): | $(BIN_DIR)
	curl -LO https://storage.googleapis.com/minikube/releases/v$(MINIKUBE_VERSION)/minikube-linux-amd64
	mv minikube-linux-amd64 $(MINIKUBE)
	chmod +x $(MINIKUBE)

$(YQ): | $(BIN_DIR)
	curl -LO https://github.com/mikefarah/yq/releases/download/v$(YQ_VERSION)/yq_linux_amd64
	mv yq_linux_amd64 $(YQ)
	chmod +x $(YQ)

$(HELM): | $(BIN_DIR)
	curl -L https://get.helm.sh/helm-v$(HELM_VERSION)-linux-amd64.tar.gz | tar xzv
	mv linux-amd64/helm $(HELM)
	rm -rf linux-amd64
	chmod +x $(HELM)

generate: $(MANIFEST_DIR)/overrided_operator_values.yaml $(MANIFEST_DIR)/overrided_pvc_cluster_values.yaml $(MANIFEST_DIR)/overrided_raw_cluster_values.yaml

.PHONY: $(MANIFEST_DIR)/overrided_operator_values.yaml
$(MANIFEST_DIR)/overrided_operator_values.yaml: $(MANIFEST_DIR)/operator_values.yaml $(YQ)
	$(YQ) '.image.tag = "v$(ROOK_VERSION)"' $< > $@

.PHONY: $(MANIFEST_DIR)/overrided_pvc_cluster_values.yaml
$(MANIFEST_DIR)/overrided_pvc_cluster_values.yaml: $(MANIFEST_DIR)/pvc_cluster_values.yaml $(YQ)
	$(YQ) '.cephClusterSpec.cephVersion.image = "quay.io/ceph/ceph:v$(CEPH_VERSION)"' $< | \
	$(YQ) '.cephClusterSpec.storage.storageClassDeviceSets[0].count = $(OSD_COUNT)' > $@

.PHONY: $(MANIFEST_DIR)/overrided_raw_cluster_values.yaml
$(MANIFEST_DIR)/overrided_raw_cluster_values.yaml: $(MANIFEST_DIR)/raw_cluster_values.yaml $(YQ)
	$(YQ) '.cephClusterSpec.cephVersion.image = "quay.io/ceph/ceph:v$(CEPH_VERSION)"' $< > $@
	for i in $$(seq 0 $$(expr $(OSD_COUNT) - 1)); do \
		$(YQ) -i ".cephClusterSpec.storage.nodes[0].devices[$${i}].name = \"loop$${i}\"" $@; \
	done

.PHONY: create-cluster
create-cluster: $(MINIKUBE)
	$(MINIKUBE) start --driver=$(DRIVER) --cpus=2 --memory 2200mb --disk-size 10gb
	for i in $$(seq 0 $$(expr $(OSD_COUNT) - 1)); do \
		$(MINIKUBE) ssh -- dd if=/dev/zero of=loop$${i} bs=1 count=0 seek=6G; \
		$(MINIKUBE) ssh -- sudo losetup /dev/loop$${i} loop$${i}; \
	done
	$(MINIKUBE) ssh -- lsblk
	$(MINIKUBE) ssh -- docker pull rook/ceph:v$(ROOK_VERSION)
	$(MINIKUBE) ssh -- docker pull quay.io/ceph/ceph:v$(CEPH_VERSION)

.PHONY: deploy
deploy: $(HELM) pv generate
	$(HELM) repo add rook-release https://charts.rook.io/release
	$(HELM) repo update
	$(HELM) install --version ${ROOK_VERSION} --create-namespace --namespace rook-ceph rook-ceph rook-release/rook-ceph -f $(MANIFEST_DIR)/overrided_operator_values.yaml
ifeq ($(DEVICE_MODE), pvc)
	$(HELM) install --version ${ROOK_VERSION} --namespace rook-ceph rook-ceph-cluster rook-release/rook-ceph-cluster -f $(MANIFEST_DIR)/overrided_pvc_cluster_values.yaml
else ifeq ($(DEVICE_MODE), raw)
	$(HELM) install --version ${ROOK_VERSION} --namespace rook-ceph rook-ceph-cluster rook-release/rook-ceph-cluster -f $(MANIFEST_DIR)/overrided_raw_cluster_values.yaml
endif

.PHONYE: pv
pv: $(MANIFEST_DIR)/pv-template.yaml $(MINIKUBE) $(YQ)
ifeq ($(DEVICE_MODE), pvc)
	for i in $$(seq 0 $$(expr $(OSD_COUNT) - 1)); do \
		$(YQ) ".metadata.name = \"pv$${i}\"" $< | \
		$(YQ) ".spec.local.path = \"/dev/loop$${i}\"" | \
		$(MINIKUBE) kubectl -- apply -f -; \
	done
endif

.PHONY: clean
clean: $(MINIKUBE)
	if [ $(DRIVER) = "docker" ]; then \
		sudo losetup -D; \
	fi
	$(MINIKUBE) stop
	$(MINIKUBE) delete
