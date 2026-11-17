---
layout: guide
title: "Find and release occupied localhost ports on macOS"
description: "List local TCP listeners, check their project and runner, and safely release the development port you need on a Mac."
permalink: /localhost-port-cleaner/
media: demo
---

List TCP listeners, identify the process and the project that owns the port, and stop it through its original terminal or service runner. For a single Next.js conflict, use the [port 3000 instructions](../port-3000-already-in-use-mac/).

## Match a listener to its project

```sh
lsof -nP -iTCP -sTCP:LISTEN
```

Read the local address and port in the `NAME` column. An IPv4 loopback address such as `127.0.0.1`, an IPv6 loopback such as `[::1]`, and a wildcard bind serve different interfaces. Look at both address families if one browser or client can reach a server while another cannot.

When a row belongs to a generic `node`, `python` or Docker process, use its working directory and runner to identify the service. If a Docker proxy owns the listener, [review the published port in the Compose project](../docker-cleanup/) instead of stopping the shared proxy.

## Free a port with SpawnSweep

The **Ports** view groups listener information with the project, branch, uptime and detected agent association when available. Review the stop action on the process you recognize. A pinned session or protected port prevents that stop action until its protection is changed.

## Why might a released port become busy again?

A watcher, active agent or runner can restart a process. Find the parent job and stop it through its own controls. If another project needs the service, configure your new app to use a different port.
