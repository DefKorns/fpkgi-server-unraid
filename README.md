# FPKGI Server (Unraid)

![Build Status](https://github.com/defkorns/fpkgi-server-unraid/actions/workflows/build.yml/badge.svg)
![Image](https://img.shields.io/badge/GHCR-defkorns%2Ffpkgi--server--unraid-blue?logo=docker)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

Docker-based HTTP server designed to host and catalog PKG files, compatible with FPKGi clients.

Built specifically for **Unraid**, with automated image publishing to **GitHub Container Registry (GHCR)**.

---

## Features

- Lightweight HTTP server
- Configurable storage directory
- Unraid-compatible XML template included
- Automatic build & push via GitHub Actions
- Persistent volume support
- Environment-based configuration

---

## Docker Image

Published at:

`ghcr.io/defkorns/fpkgi-server-unraid:latest`

Pull manually:

```bash
docker pull ghcr.io/defkorns/fpkgi-server-unraid:latest
```

## Install on Unraid
### Install via Template URL

1. Open **Unraid → Apps**
2. Click **Install via URL**
3. Paste:
`https://raw.githubusercontent.com/defkorns/fpkgi-server-unraid/main/templates/fpkgi.xml`
4. Adjust settings if needed
5. Click **Apply**

## ⚙️ Configuration
### Volume Mapping
| Name         | Container Path |
| ------------ | -------------- |
| Server Files | `/data`        |


Default Unraid path:
`/mnt/user/games/ps4`

### Environment Variables

| Variable   | Description                | Default                   |
| ---------- | -------------------------- | ------------------------- |
| HTTP_PORT  | HTTP server port           | 8080                      |
| SERVER_URL | Public server URL          | http://[UNRAID-IP]:[PORT] |
| HTTP_DIR   | Directory served over HTTP | /data                     |
| PUID       | User ID                    | 1000                      |
| PGID       | Group ID                   | 100                       |
| TZ         | Timezone                   | Europe/Lisbon             |
| LOG_DEBUG  | Enable debug logging       | 0                         |

## CI/CD Pipeline
This project uses GitHub Actions to:

- Automatically build Docker images
- Push to GHCR
- Maintain the `latest` tag

Workflow file:
`.github/workflows/build.yml`
## Project Structure
```
.
├── Dockerfile
├── entrypoint.sh
├── templates/
│   └── fpkgi.xml
├── icon.png
└── .github/workflows/
    └── build.yml
```
## Security

- Runs without privileged mode
- Configurable user/group permissions
- Only defined ports exposed
- No hardcoded credentials

### License
Project license is MIT for code structure only.
Commercial or redistribution usage is not permitted without permission.
