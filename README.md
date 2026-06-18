# JB-PRECHECK

A diagnostic / pre-check script for **JetBackup 5** (JB5) environments. It runs a series of read-only health checks against the server and prints a categorized report, making it easy to spot common configuration, connectivity, licensing, and service problems before escalating a support ticket.

Each check prints a colored `[Category]` header so the output is easy to scan, followed by the findings for that section. Most sections end in either `OK` or a `[WARN]` / `[ERROR]` message describing the problem and, where relevant, a link to the JetApps Knowledgebase.

---

## Requirements

- A Linux server running **JetBackup 5**.
- Supported OS families: **RHEL / AlmaLinux / CloudLinux** and **Debian / Ubuntu**.
- **Run as root.** Several checks (MongoDB auth, `journalctl`, license protocol lookup) require root; the script warns and pauses if not run as root.
- Common userland tools: `bash`, `curl`, `date`, `grep`, `find`, `systemctl`.

---

## Report Sections

The script runs the following checks, in order. Each corresponds to a `[Category]` header in the output.

### `[Network]`
Determines the server's outgoing public IP address. It first reads the IP protocol preference (IPv4/IPv6) configured in JB5, then queries an external service to resolve the public IP, falling back between IPv4 and IPv6 as needed.
**Use:** Confirms the server can reach the internet and surfaces the public IP used for license verification. A failure here usually points to a firewall/CSF block.

### `[Server Details]`
Reports basic OS facts: distribution and version, kernel version, cgroups version (v1 / hybrid / v2), and the detected package manager (`yum`/`dnf` vs `apt`).
**Use:** Establishes the baseline environment and confirms the OS/package manager are supported, which downstream checks depend on.

### `[Panel & License]`
Detects the installed control panel (cPanel & WHM, DirectAdmin, Plesk, InterWorx, Webuzo, or none/Linux) and its version, the installed JetBackup version(s), and the panel's own license status where applicable. It then queries the JetApps billing endpoint for the JetBackup license status (created date, type, partner, status).
**Use:** Confirms the panel is recognized and the JetBackup license is valid and active — a frequent root cause of functionality issues.

### `[Update Status]`
Compares the installed JB5 version against the latest available version in the JetApps repository for the current update tier and OS.
**Use:** Flags an out-of-date JetBackup install and provides the exact command to update (or where to check update logs for blockers).

### `[Timezone & Offset]`
Shows the server's local time, UTC time, and the offset between them (e.g. "Server is 10 hours ahead of UTC time").
**Use:** JB5 logs in UTC. Knowing the server's offset makes it much easier to correlate server logs and scheduled events with JetBackup's UTC timestamps.

### `[JetLicense Connectivity]`
Tests outbound connectivity to the JetLicense service (`check.jetlicense.com`) and the JetApps software repository (`repo.jetlicense.com`).
**Use:** Confirms the server can reach the licensing and update infrastructure. Failures here typically indicate firewall/DNS issues and should be escalated.

### `[Destinations]`
Lists the JetBackup destinations configured on the server, counted by type.
**Use:** Gives a quick overview of where backups are being stored and confirms the JetBackup API is responsive.

### `[Fraud Check]`
Scans for indications that the JetBackup 5 installation has been tampered with or that licensing has been circumvented. If such indications are found, the script reports the affected items and aborts.
**Use:** Identifies an installation as ineligible for support due to license circumvention or modification.

> **Note:** Any binary, cron, or entry flagged by this section is **not** developed or distributed by JetApps and has no relation to JetBackup software.

### `[Crons]`
Checks for missing JetBackup/JetApps cron files (which can stop schedules or auto-updates from running) and for additional/custom JetBackup-related crons that could conflict.
**Use:** Ensures the scheduling and auto-update mechanisms are present and that no conflicting custom crons are interfering.

### `[Binaries]`
Compares the expected set of JetBackup binaries in `/usr/bin` (`jetapps`, `jetbackup5`, `jetbackup5api`, `jetmongo`, …) against what is actually present, reporting anything unexpected or missing.
**Use:** Catches a broken or incomplete installation where core binaries are missing or unexpected ones are present.

### `[Permissions & Ownership]`
Checks MongoDB-related paths for common ownership and permission problems: JetBackup's MongoDB data/log/run directories and socket should be owned by the `mongod` user, `/tmp` should be `1777`, and `/dev/null` should be `666`.
**Use:** These are frequent causes of `jetmongod` failing to start. Findings include a Knowledgebase link with remediation steps.

### `[Service Status]`
Reports whether services need restarting (via `needs-restarting` where available), and checks that the `jetbackup5d` and `jetmongod` services are active. If a service is down, it prints the last several relevant log/journal entries; if `jetmongod` is up, it also runs a live MongoDB ping to confirm the database is accepting connections.
**Use:** Confirms the core JetBackup services are running and healthy, and surfaces recent errors when they are not.

---

## Interpreting Output

- **`OK`** — the section passed with no issues found.
- **`[INFO]`** — informational; may warrant a look but is not necessarily a problem.
- **`[WARN]`** — a potential problem worth investigating.
- **`[ERROR]`** — a problem likely to cause JetBackup malfunction; should be resolved.
- **`ABORTED` / non-zero exit** — the Fraud Check found indications of tampering or license circumvention and stopped the run.

## Notes

- The script is **read-only** with respect to JetBackup configuration — it inspects state and reports findings; it does not modify settings, restart services, or change files.
- Output is designed to be copy/pasted into a JetApps support ticket. Redirect to a file (which disables colors automatically) for a clean capture.
