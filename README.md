# pbs-docker

Proxmox Backup Server in a container, built from the **official Proxmox
packages** for Debian trixie (`pbs-no-subscription`) and supervised by
[s6-overlay](https://github.com/just-containers/s6-overlay). Nothing is compiled
from source, so the binaries are the same ones a bare metal PBS install gets.

```
ghcr.io/alexdelprete/pbs-docker:latest
ghcr.io/alexdelprete/pbs-docker:4.2.6-1
```

Version tags are derived at build time from the installed package
(`dpkg-query -W proxmox-backup-server`), so a tag always reflects the actual PBS
version. A scheduled build runs daily at 12:00 UTC and picks up whatever Proxmox
currently ships. Every build runs a smoke test that starts the container
and waits for the web UI to answer before anything is pushed.

## Why

The widely used community image compiles PBS from source to support ARM64, and
its published tags can lag upstream by months. On amd64 that work is
unnecessary: Proxmox publishes signed .debs, and this image is a thin wrapper
around them. The supply chain is Proxmox's repository, s6-overlay's release
tarballs (checksum pinned in the Dockerfile), and this repo.

## Running

```yaml
services:
  pbs:
    image: ghcr.io/alexdelprete/pbs-docker:latest
    container_name: pbs
    hostname: pbs
    restart: unless-stopped
    mem_limit: 4G
    environment:
      - TZ=Europe/Rome
      - FILE__PBS_ROOT_PASSWORD=/run/secrets/pbs_root_password
    secrets:
      - pbs_root_password
    volumes:
      - $PWD/etc:/etc/proxmox-backup
      - $PWD/logs:/var/log/proxmox-backup
      - $PWD/lib:/var/lib/proxmox-backup
      - /backups/pbs:/backups/pbs
    tmpfs:
      - /run:exec,mode=0755
    ports:
      - 8007:8007

secrets:
  pbs_root_password:
    file: ./pbs_root_password
```

`/run` on tmpfs is **required**, and it must be mounted with `exec`. s6-overlay
stages its init under `/run/s6` at boot, and Docker mounts tmpfs `noexec` by
default, so a plain `- /run` fails with `Permission denied` before anything
starts. `/run:exec,mode=0755` is the working form in both `docker run --tmpfs`
and compose.

The three PBS directories should be bind mounts or volumes. The container warns
at startup if they are not, since their contents are otherwise lost when the
container is recreated. Ownership and permissions are set on every start, so
empty host directories are fine.

## First login

The official packages ship no `admin@pbs` user. The bootstrap account is
`root@pam`, which authenticates through PAM against the container's root
account. `/etc/shadow` is not persisted, so the password is set on every start
from one of:

- `PBS_ROOT_PASSWORD=<password>`
- `FILE__PBS_ROOT_PASSWORD=/path/to/file` (Docker secrets, or any mounted file)

Once you have created your own users in PBS, the variable can be dropped.

## Environment

| Variable | Default | Purpose |
|---|---|---|
| `TZ` | `Europe/Rome` | Container time zone |
| `PBS_ROOT_PASSWORD` | unset | Password for `root@pam` |
| `FILE__<NAME>` | unset | Read `<NAME>` from a file instead of the environment |

Any variable can be supplied as `FILE__<NAME>`. The file's contents become
`<NAME>` for every service in the container.

## Init

s6-overlay runs the following, in dependency order:

1. `init-envfile` resolves `FILE__*` variables
2. `init-pbs` creates and fixes ownership of the PBS directories, clears stale
   locks, sets the root password and time zone
3. `init-custom-scripts` runs any executables found in `/custom-cont-init.d`
4. `svc-proxmox-backup-api` starts the API, ready when `127.0.0.1:82` accepts
   connections
5. `svc-proxmox-backup-proxy` starts the web and backup endpoint as the `backup`
   user, ready when `127.0.0.1:8007` answers

Readiness is checked with `s6-notifyoncheck`, so the proxy does not start until
the API is actually accepting connections, not merely running. If any init step
fails or a service never becomes ready, the container **stops** rather than
running half-configured (`S6_BEHAVIOUR_IF_STAGE2_FAILS=2`). Both daemons log to
stdout and stderr.

`docker stop` sends SIGTERM, s6 brings the proxy down first, then the API, then
exits. No custom `stop_signal` is needed.

The syslogd overlay provides a real `/dev/log` listener. PAM writes `root@pam`
authentication failures there, and anything else that uses syslog lands under
`/var/log/syslogd/` inside the container, one directory per facility.

### Custom init scripts

Mount a directory at `/custom-cont-init.d`. Executable files in it run once, in
name order, after the PBS directories are prepared and before the daemons start.

## Upgrades

Pull a newer tag and recreate the container. Configuration, users, ACLs, job
definitions and the datastore all live in the mounted paths.

With [What's Up Docker](https://github.com/fmartinou/whats-up-docker), label
the container so new releases are reported:

```yaml
labels:
  - wud.watch=true
  - wud.tag.include=^\d+\.\d+\.\d+-\d+$$
  - wud.link.template=https://github.com/alexdelprete/pbs-docker/pkgs/container/pbs-docker
```

(The `$$` is compose escaping for a literal `$`.)

## Not included

There is deliberately no cron service for `proxmox-daily-update`. In a
container, apt based updates are replaced by rebuilding the image, and running
it would make the update panel in the web UI misleading.

No `PUID`/`PGID` remapping. PBS's Debian package creates a fixed `backup` user
and the daemons, config permissions and datastore ownership all assume it.

## Caveats

Some PBS features do not work in a container, notably disk and SMART management
and ZFS. As a backup target using a directory datastore on the host's
filesystem, none of that matters.

## License

MIT
