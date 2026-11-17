---
layout: guide
title: "Stop leftover Docker Compose stacks on Mac"
description: "Find Docker Compose projects left running after a coding session and stop their containers while keeping local volumes and database files."
permalink: /guides/stop-leftover-docker-stacks-mac/
---

Use `docker compose ls` to find running Compose projects on your Mac. From the correct project directory, use `docker compose stop` to stop its containers while keeping them and their volumes available for the next session. Confirm the project first if you have several checkouts running similar services.

## Identify the local stack

```sh
docker context show
docker compose ls
```

Check that the current Docker context is your local engine. Match the project and config file reported by Compose to the checkout your agent was using. From that project directory, run `docker compose ps` to review services and published ports. If you originally supplied custom Compose files or a project name, reuse the same Compose options when checking and stopping it. [Docker Compose project listing reference](https://docs.docker.com/reference/cli/docker/compose/ls/)

## Stop the stack and keep its data

When you confirm the project has finished using the stack, run `docker compose stop` from that project. Use `docker compose ps --all` to check that the services stopped. To bring existing containers back, run `docker compose start` with the same project settings. Stop preserves the containers and storage so they are ready for the next session. [Docker Compose stop reference](https://docs.docker.com/reference/cli/docker/compose/stop/)

## Review and stop a stack from SpawnSweep

Open **Resources → Docker stacks** to see local Compose projects and standalone containers grouped into stacks. A row includes the container count, published ports where available, and an agent session if detected. Choose **Stop stack** and confirm the preview to stop those containers together. The action keeps volumes and local database files on disk.

If a local port stays busy after the stack stops, [check which process still owns it](../port-3000-already-in-use-mac/).
