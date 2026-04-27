IMAGE_NAME   := claude-sandbox
SERVICE_NAME := claude-sandbox
COMPOSE      := docker compose -f claude-sandbox-compose.yml

.PHONY: build run connect stop destroy clean logs status test help

## Build the container image (does not start it)
build:
	docker build -t $(IMAGE_NAME) --build-arg TZ=$${TZ:-America/New_York} .

## Start the container in the background (builds if image missing)
run:
	$(COMPOSE) up -d

## Attach an interactive bash shell to the running container
connect:
	docker exec -it $$($(COMPOSE) ps -q $(SERVICE_NAME)) bash

## Stop the container (preserves container and volumes)
stop:
	$(COMPOSE) stop

## Remove the container but keep image
destroy:
	$(COMPOSE) down

## Remove container AND image — full reset
clean:
	$(COMPOSE) down --rmi local

## Tail container logs
logs:
	$(COMPOSE) logs -f

## Show container status
status:
	$(COMPOSE) ps

## Run smoke tests for claude-sandbox-init
test:
	./test-init.sh

## Show this help
help:
	@echo "Targets:"
	@echo "  build    - Build the container image"
	@echo "  run      - Start the container in the background"
	@echo "  connect  - Attach a bash shell to the running container"
	@echo "  stop     - Stop the container (keeps state)"
	@echo "  destroy  - Remove the container (keeps image)"
	@echo "  clean    - Remove container and image"
	@echo "  logs     - Tail container logs"
	@echo "  status   - Show container status"
	@echo "  test     - Run smoke tests for claude-sandbox-init"
