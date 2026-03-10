# 🛡️ Disk Guardian

Disk Guardian is a lightweight Bash-based monitoring script that tracks disk usage, sends notifications, and can automatically stop specified Docker containers when disk usage exceeds defined thresholds. It's designed to work with webhook services like [ntfy](https://ntfy.sh) for real-time alerts.

---

## ✨ Features

- Monitor multiple directories for disk usage in real-time
- Configurable warning and stopping thresholds
- Sends alerts via webhooks (ntfy compatible only)
- Automatically stops designated Docker containers if disk usage reaches critical levels
- Lightweight — no external dependencies beyond Docker and Bash

---

## 🚀 Quick Start (Docker Compose)

Here's an example `docker-compose.yml` to get started:

```yaml
services:
  disk-guardian:
    image: kiansd/disk-guardian:latest
    container_name: disk-guardian
    environment:
      DOWNLOADER_CONTAINERS: "sonarr qbittorrent"
      POLLING_RATE: 5
      WARNING_THRESHOLD: 90
      STOPPING_THRESHOLD: 95
      WEBHOOK_URL: "ntfy:80/disk-guardian"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock #important to allow the script to stop other docker containers
      #just mount the drives you want to monitor
      - /home:/check/home:ro 
      - /mnt/drive1:/check/drive1:ro

  ntfy:
    image: binwiederhier/ntfy
    container_name: ntfy
    command:
      - serve
    environment:
      - TZ=UTC
    volumes:
      - /var/cache/ntfy:/var/cache/ntfy
      - /etc/ntfy:/etc/ntfy
    ports:
      - 80:80
    healthcheck:
      test: [ "CMD-SHELL", "wget -q --tries=1 http://localhost:80/v1/health -O - | grep -Eo '\"healthy\"\\s*:\\s*true' || exit 1" ]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 40s
    restart: unless-stopped
    init: true
```
​

---

## ⚙️ Configuration

Environment variables allow easy customization:

| Variable | Default | Description |
|---|---|---|
| `DOWNLOADER_CONTAINERS` | `""` | Space-separated list of Docker container names to stop when disk usage exceeds the stopping threshold. |
| `POLLING_RATE` | `10` | Seconds between disk usage checks. |
| `WARNING_THRESHOLD` | `90` | Disk usage percentage to trigger a warning notification. |
| `STOPPING_THRESHOLD` | `95` | Disk usage percentage to stop containers. |
| `WEBHOOK_URL` | `http://localhost:80/disk_guard` | URL to send notifications (ntfy compatible). |

> **Notes:**
> - All directories to monitor should be mounted under `/check` inside the container.
> - Containers specified in `DOWNLOADER_CONTAINERS` must exist and be running in Docker.
> - Disk Guardian uses `df` internally, so mounted directories must be accessible.

---

## 🔍 How It Works

1. Disk Guardian periodically polls each mounted directory.
2. If disk usage exceeds `WARNING_THRESHOLD`, a notification is sent via the webhook.
3. If disk usage exceeds `STOPPING_THRESHOLD`, it stops the listed Docker containers *(once per disk until usage drops)*.

State flags (`diskWarned` and `diskStopped`) prevent duplicate notifications and repeated container stops.

---

## 🔔 Example ntfy Notification

When thresholds are reached, notifications look like:
```
2026-03-09 12:00:00 WARNING DRIVE USAGE ABOVE 90%
Warning: Disk /check/home usage at 92%
2026-03-09 12:01:00 CRITICAL WARNING DRIVE USAGE ABOVE 95%
Disk /check/home usage at 97% — stopping downloaders due to high disk usage
```

---

## 🛠️ Development & Deployment

**Build the image:**
```bash
docker build -t disk-guardian:latest .
```

**Start services:**
```bash
docker-compose up -d
```

**Check logs for alerts:**
```bash
docker logs -f disk-guardian
```

---

## 🤝 Contributing
- Open an issue for bugs or feature requests.
