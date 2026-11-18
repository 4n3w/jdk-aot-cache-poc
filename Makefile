# Run the tests:  make  (or make help) lists the targets.
# Works with the GNU Make 3.81 that ships with macOS. The only tool needed is Docker.

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Knobs, passed through to the scripts.
JDK_IMAGE ?= container-registry.oracle.com/java/jdk-no-fee-term:25
GEMFIRE_IMAGE ?= gemfire/gemfire:10.3.2-jdk17
PLATFORM ?=
RUNS ?= 5
CPUS ?= 2
ACCEPT_TERMS ?=
IMAGE := aot-poc
export GEMFIRE_IMAGE PLATFORM RUNS CPUS ACCEPT_TERMS IMAGE

PLATFORM_FLAG := $(if $(PLATFORM),--platform $(PLATFORM))
IN_TEST_IMAGE := docker run --rm $(PLATFORM_FLAG) --cpus $(CPUS) -e RUNS=$(RUNS) $(IMAGE):tools bash

.PHONY: help image 01 02 03 04 05 06 all clean

##@ General
help: ## List targets and knobs
	@awk 'BEGIN {FS = ":.*## "} /^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0, 5)} /^[0-9a-zA-Z_-]+:.*## / {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Knobs: JDK_IMAGE=$(JDK_IMAGE)  (any image with a full JDK 25)"
	@echo "       PLATFORM=$(PLATFORM)  (for example linux/amd64; empty = this machine's)"
	@echo "       RUNS=$(RUNS)  CPUS=$(CPUS)  (timed runs per measurement, CPUs per container)"
	@echo "       05:  ACCEPT_TERMS=y  GEMFIRE_IMAGE=$(GEMFIRE_IMAGE)"

image: ## Build the test images: JDK + stand-in agent (base), plus sample applications and tests (tools)
	@echo "Building the test images from $(JDK_IMAGE) (the first build downloads Gradle and the sample application's dependencies) ..." >&2
	@docker build -q $(PLATFORM_FLAG) --build-arg JDK_IMAGE=$(JDK_IMAGE) --target base -t $(IMAGE):base . >/dev/null
	@docker build -q $(PLATFORM_FLAG) --build-arg JDK_IMAGE=$(JDK_IMAGE) --target tools -t $(IMAGE):tools . >/dev/null

clean: ## Remove the images, the test cluster and the files the tests copied or logged
	-docker rm -f aot-poc-gemfire 2>/dev/null
	-docker network rm aot-poc-net 2>/dev/null
	-docker rmi $(IMAGE):tools $(IMAGE):base $(IMAGE):before $(IMAGE):after $(IMAGE):gemfire-client 2>/dev/null
	rm -rf 06-end-to-end/build 06-end-to-end/before/build 06-end-to-end/after/build

##@ Tests (each prints what it ran and what happened, and marks outcomes that differ from our run)
01: image ## What has to match between the training run and the production run
	@$(IN_TEST_IMAGE) /poc/01-option-matching/test.sh

02: image ## What a Java agent gets to see when the cache is in use
	@$(IN_TEST_IMAGE) /poc/02-java-agent/test.sh

03: image ## -XX:CompressedClassSpaceSize and Metaspace: training fails at 40M, runtime is fine
	@$(IN_TEST_IMAGE) /poc/03-class-space-size/test.sh

04: image ## Spring Boot executable WAR: packed, extracted, and what cannot be extracted
	@$(IN_TEST_IMAGE) /poc/04-executable-war/test.sh

05: image ## GemFire client with the cache, trained with and without a cluster (needs ACCEPT_TERMS=y)
	@05-gemfire-client/test.sh

06: image ## The image build end to end: before and after, production-style JAVA_OPTS, startup time
	@06-end-to-end/test.sh

all: image ## 01-04 and 06, and 05 as well when ACCEPT_TERMS=y
	@failed=; for t in 01 02 03 04 $(if $(filter y,$(ACCEPT_TERMS)),05) 06; do \
	  printf '\n######## make %s\n' $$t; \
	  $(MAKE) --no-print-directory $$t || failed="$$failed $$t"; \
	done; \
	if [ -n "$$failed" ]; then echo; echo "Outcomes differed from our run, or a test failed, in:$$failed"; exit 1; fi
