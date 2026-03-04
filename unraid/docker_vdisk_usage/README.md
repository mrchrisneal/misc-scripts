# Docker vDisk Usage Analyzer for Unraid

A shell script for [Unraid](https://unraid.net/) that reports Docker vDisk usage at a glance — showing disk utilization, per-container sizes, image sizes, and volume usage in a cleanly formatted report.

Designed to run via the [User Scripts](https://forums.unraid.net/topic/48286-plugin-ca-user-scripts/) plugin directly from the Unraid web UI.

## Features

- Automatically locates your Docker vDisk image and reports its size, mount point, and utilization
- Lists all containers sorted by writable layer size (largest first) with status
- Lists all images sorted by size, excluding dangling intermediate layers
- Maps Docker volumes back to their owning containers (named and anonymous)
- Hides empty orphan volumes to reduce noise, with a summary count
- Provides cleanup tips for orphan volumes and dangling images when detected
- Browser-safe formatting using `&nbsp;` for proper column alignment in the Unraid UI

## Example Output

```
================================================================
  DOCKER vDISK USAGE REPORT
================================================================

  vDisk Image  :  /mnt/user/system/docker/docker-xfs.img
  Mounted At   :  /var/lib/docker
  vDisk Size   :  80GiB
  Used / Free  :  67G used  |  14G free  |  84% utilized

================================================================
  SYSTEM OVERVIEW
================================================================

  TYPE              TOTAL   ACTIVE  SIZE      RECLAIMABLE
  Images            121     90      57.94GB   2.658GB (4%)
  Containers        97      71      2.746GB   2.761MB (0%)
  Local Volumes     318     16      5.481GB   5.244GB (95%)
  Build Cache       0       0       0B        0B

================================================================
  Scanning containers... this may take a minute.
================================================================

  CONTAINER                   STATUS      SIZE

  tdarr                       running     917MB (virtual 5.1GB)
  OnlyOfficeDocumentServer    running     809MB (virtual 4.7GB)
  sonarr                      running     384MB (virtual 590MB)
  nextcloud                   running     315MB (virtual 1.4GB)
  radarr                      running     67.7MB (virtual 286MB)
  whisper-asr-webservice      running     67.0MB (virtual 4.9GB)
  ArchiveBox                  running     59.4MB (virtual 2.3GB)
  pihole                      running     32.5MB (virtual 130MB)
  ...

================================================================
  IMAGES
================================================================

  REPOSITORY:TAG                                  SIZE

  onerahmet/openai-whisper-asr-webservice:latest  4.8GB
  ghcr.io/haveagitgat/tdarr:latest               4.2GB
  onlyoffice/documentserver:latest                3.9GB
  c4illin/convertx:latest                         3.5GB
  lscr.io/linuxserver/calibre:latest              3.3GB
  ...

================================================================
  Scanning volumes... this may take a few minutes.
================================================================

  VOLUME                                                 SIZE

  b7cc7d889864... (orphan)                               1.5G
  e970dfa2e3dd... (orphan)                               1.2G
  71dca7c3d8ba... (orphan)                               311M
  authelia-foundation_postgres_data [authelia-postgres]   164M
  OnlyOfficeDocumentServer (anon)                        62.0M
  authelia_foundation_postgres_data                      48.0M
  ...

  (87 empty orphan volumes and 1 empty named volumes hidden)

================================================================

  TIP: 123 orphan volumes detected.
  Preview cleanup:  docker volume ls -f dangling=true
  Remove all:       docker volume prune

================================================================

  TIP: 31 dangling (untagged) images detected.
  Remove all:  docker image prune

================================================================

  Report generated: 2026-03-03 12:00:00
================================================================
```

## Installation

### Prerequisites

The [CA User Scripts](https://forums.unraid.net/topic/48286-plugin-ca-user-scripts/) plugin must be installed. If you don't have it yet, install it from the **Apps** tab in Unraid (search for "User Scripts").

### Adding the Script

1. In the Unraid web UI, go to **Settings** → **User Scripts** (under User Utilities).
2. Click **Add New Script** and give it a name (e.g. `docker_vdisk_usage`).
3. Click the gear icon next to your new script and select **Edit Script**.
4. Delete the default placeholder content and paste in the contents of `docker_vdisk_usage.sh`.
5. Click **Save Changes**.

### Running It

From the User Scripts page, click the **Run Script** button next to your script. The output will appear in a popup window. Note that the volume scanning step can take a few minutes depending on how many volumes you have.

You can also schedule it on a cron interval (e.g. weekly) using the dropdown next to the script if you'd like to keep an eye on disk growth over time.

## How It Works

The script reads `/boot/config/docker.cfg` to find your vDisk image path, locates the loop device mount, then queries the Docker daemon directly for container, image, and volume information. Volume ownership is resolved by inspecting each container's mount list and matching volume names back to their containers. Anonymous volumes are labeled with their owning container name, while unattached volumes are marked as orphans.

Size values under 100 are normalized to one decimal place for consistency (e.g. `67MB` → `67.0MB`, `4.59MB` → `4.5MB`). All column padding uses `&nbsp;` entities since the Unraid User Scripts UI renders output in a browser context where regular spaces get collapsed.

## License

MIT
