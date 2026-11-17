---
layout: guide
title: "Stop leftover Docker Compose stacks on Mac"
description: "Find Docker Compose projects left running after a coding session, verify the Docker context, and check what happens to data when the stack stops."
permalink: /docker-cleanup/
media: demo
---

Use `docker compose ls` to find running Compose projects on your Mac. From the correct project directory, use `docker compose stop` to stop its containers without running a prune. Confirm the project and Docker endpoint first, especially if you also use remote engines.

## Identify the local stack

```sh
docker context ls
docker compose ls
```

Check the active context and its Docker endpoint. Environment variables such as `DOCKER_CONTEXT` or `DOCKER_HOST` can select a different engine. Use an explicit `docker --context` with your intended context if you switch between engines. Match the project and config file reported by Compose to the checkout your agent was using. From that project directory, run `docker compose ps` to review services and published ports. If you originally supplied custom Compose files or a project name, reuse the same Compose options when checking and stopping it. [Docker Compose project listing reference](https://docs.docker.com/reference/cli/docker/compose/ls/)

## Stop the stack and keep its data

When you confirm the project has finished using the stack, run `docker compose stop` from that project. Use `docker compose ps --all` to check that the services stopped. To bring existing containers back, run `docker compose start` with the same project settings. Regular Compose services can be restarted after a stop. A container launched with auto-remove can disappear on exit along with its anonymous volumes. Check how one-off containers were launched before stopping anything with data you need. [Docker Compose stop reference](https://docs.docker.com/reference/cli/docker/compose/stop/)

## Review and stop a stack from SpawnSweep

Open **Resources → Docker stacks** to see detected Compose projects and standalone containers in the Docker context the app uses. A row includes the container count, published ports where available, and an agent session if detected. Choose **Stop stack** and confirm the preview to stop those containers together. SpawnSweep issues a container stop. Docker applies the container’s exit policy, including auto-remove if configured. [Docker contexts](https://docs.docker.com/engine/manage-resources/contexts/) · [Docker auto-remove behavior](https://docs.docker.com/reference/cli/docker/container/run/#rm)

If a local port stays busy after the stack stops, [check which process still owns it](../port-3000-already-in-use-mac/).

## Does stopping Compose free disk space?

Stopping containers can free CPU and memory. Images and volumes typically remain on disk after a stop. Auto-remove can clean up a container and its anonymous volumes on exit. Use `docker system df` to inspect disk use separately, and confirm which projects still need that data before removing anything.
