ifeq (,$(wildcard .env))
  $(error .env file not found. Run: cp .env.example .env)
endif

include .env
export

NSO_BUILD_IMAGE = cisco-nso-build:$(NSO_VERSION)
NSO_PROD_IMAGE  = cisco-nso-prod:$(NSO_VERSION)
NSO_CUSTOM_IMAGE = nso-custom-prod:$(NSO_VERSION)

.PHONY: build up up-netsim up-obs up-all down cli logs clean

## Build custom production image and compile all NED/service packages
build:
	build_missing=false; \
	docker image inspect $(NSO_BUILD_IMAGE) > /dev/null 2>&1 || build_missing=true; \
	prod_missing=false; \
	docker image inspect $(NSO_PROD_IMAGE) > /dev/null 2>&1 || prod_missing=true; \
	if [ "$$build_missing" = "true" ] || [ "$$prod_missing" = "true" ]; then \
		echo "Required NSO images not found locally. Checking for tarballs in images/..."; \
		loaded=false; \
		for tarball in images/*.tar.gz; do \
			if [ -f "$$tarball" ]; then \
				echo "Loading image tarball: $$tarball"; \
				docker load -i "$$tarball"; \
				loaded=true; \
			fi; \
		done; \
		if [ "$$loaded" = "false" ]; then \
			echo "ERROR: Required NSO images not found and no tarballs in images/" >&2; \
			echo "  Required: $(NSO_BUILD_IMAGE)" >&2; \
			echo "  Required: $(NSO_PROD_IMAGE)" >&2; \
			echo "" >&2; \
			echo "  To fix, either:" >&2; \
			echo "    1. Place NSO image .tar.gz files in images/ and re-run make build" >&2; \
			echo "    2. Load images manually: docker load -i <tarball>" >&2; \
			exit 1; \
		fi; \
		docker image inspect $(NSO_BUILD_IMAGE) > /dev/null 2>&1 || \
			{ echo "ERROR: $(NSO_BUILD_IMAGE) still not found after loading tarballs" >&2; exit 1; }; \
		docker image inspect $(NSO_PROD_IMAGE) > /dev/null 2>&1 || \
			{ echo "ERROR: $(NSO_PROD_IMAGE) still not found after loading tarballs" >&2; exit 1; }; \
		echo "NSO images loaded successfully"; \
	fi
	docker build --build-arg NSO_VERSION=$(NSO_VERSION) -t $(NSO_CUSTOM_IMAGE) -f images/Dockerfile.prod images/
	docker compose --profile build up -d nso-build
	docker compose exec nso-build test -f /build-packages.sh
	docker compose exec nso-build /build-packages.sh

## Start NSO in single-node topology
up:
	docker compose -f compose.yaml up -d

## Start NSO with netsim simulated devices
up-netsim:
	docker compose -f compose.yaml -f compose.netsim.yaml up -d

## Start NSO with full observability stack (OTel, Jaeger, InfluxDB, Prometheus, Grafana)
up-obs:
	docker compose -f compose.yaml -f compose.observability.yaml up -d

## Start NSO with netsim devices and full observability stack
up-all:
	docker compose -f compose.yaml -f compose.netsim.yaml -f compose.observability.yaml up -d

## Stop and remove all containers including build (preserves volumes)
down:
	docker compose --profile build -f compose.yaml -f compose.netsim.yaml -f compose.observability.yaml down

## Open NSO CLI (Cisco-style)
cli:
	docker compose exec nso ncs_cli -u $(ADMIN_USERNAME) -C

## Stream container logs
logs:
	docker compose logs -f

## Stop all containers and destroy volumes (full reset)
clean:
	docker compose --profile build -f compose.yaml -f compose.netsim.yaml -f compose.observability.yaml down -v
