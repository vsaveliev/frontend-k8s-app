# Copyright 2017 Kubernetes Community Authors. All rights reserved.
# Use of this source code is governed by a MIT-style
# license that can be found in the LICENSE file.

APP?=my-app
REGISTRY?=registry.k8s.community
CA_DIR?=certs

# Use the 0.0.0 tag for testing, it shouldn't clobber any release builds
RELEASE?=0.4.10

K8SAPP_LOCAL_HOST?=0.0.0.0
K8SAPP_LOCAL_PORT?=8080

# Namespace: dev, prod, release, cte, username ...
NAMESPACE?=default

# Infrastructure (dev, stable, test ...) and kube-context for helm
INFRASTRUCTURE?=stable
KUBE_CONTEXT?=inventory
VALUES?=values-${INFRASTRUCTURE}

CONTAINER_IMAGE?=${REGISTRY}/${NAMESPACE}/${APP}
CONTAINER_NAME?=${APP}-${NAMESPACE}

REPO_INFO=$(shell git config --get remote.origin.url)

ifndef COMMIT
	COMMIT := git-$(shell git rev-parse --short HEAD)
endif

BUILDTAGS=

.PHONY: all
all: build

.PHONY: vendor
vendor: clean
	npm install

.PHONY: build
build: vendor test certs
	@echo "+ $@"
	npm run build
	docker build --pull -t $(CONTAINER_IMAGE):$(RELEASE) .

.PHONY: certs
certs:
# ifeq ("$(wildcard $(CA_DIR)/ca-certificates.crt)","")
# 	@echo "+ $@"
# 	@docker run --name ${CONTAINER_NAME}-certs -d alpine:edge sh -c "apk --update upgrade && apk add ca-certificates && update-ca-certificates"
# 	@docker wait ${CONTAINER_NAME}-certs
# 	@mkdir -p ${CA_DIR}
# 	@docker cp ${CONTAINER_NAME}-certs:/etc/ssl/certs/ca-certificates.crt ${CA_DIR}
# 	@docker rm -f ${CONTAINER_NAME}-certs
# endif

.PHONY: push
push: build
	@echo "+ $@"
	@docker push $(CONTAINER_IMAGE):$(RELEASE)

.PHONY: run
run: build
	@echo "+ $@"
	@docker run --name ${CONTAINER_NAME} -p ${K8SAPP_LOCAL_PORT}:${K8SAPP_LOCAL_PORT} \
		-e "K8SAPP_LOCAL_HOST=${K8SAPP_LOCAL_HOST}" \
		-e "K8SAPP_LOCAL_PORT=${K8SAPP_LOCAL_PORT}" \
		-d $(CONTAINER_IMAGE):$(RELEASE)
	@sleep 1
	@docker logs ${CONTAINER_NAME}

HAS_RUNNED := $(shell docker ps | grep ${CONTAINER_NAME})
HAS_EXITED := $(shell docker ps -a | grep ${CONTAINER_NAME})

.PHONY: logs
logs:
	@echo "+ $@"
	@docker logs ${CONTAINER_NAME}

.PHONY: stop
stop:
ifdef HAS_RUNNED
	@echo "+ $@"
	@docker stop ${CONTAINER_NAME}
endif

.PHONY: start
start: stop
	@echo "+ $@"
	@docker start ${CONTAINER_NAME}

.PHONY: rm
rm:
ifdef HAS_EXITED
	@echo "+ $@"
	@docker rm ${CONTAINER_NAME}
endif

.PHONY: deploy
deploy: push
	helm upgrade ${CONTAINER_NAME} -f charts/${VALUES}.yaml charts --kube-context ${KUBE_CONTEXT} --namespace ${NAMESPACE} --version=${RELEASE} -i --wait

.PHONY: test
test: vendor
	@echo "+ $@"
	# @go test -v -race -cover -tags "$(BUILDTAGS) cgo" ${GO_LIST_FILES}

.PHONY: clean
clean: stop rm
	@rm -rf dist/
	@rm -rf node_modules/
