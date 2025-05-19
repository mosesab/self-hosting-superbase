# Supabase Self-Hosting Automation Script (`self_host.sh`)

This script automates the deployment and initial configuration of a self-hosted Supabase instance on one or more Virtual Private Servers (VPS).

## Features

-   Reads server connection details and configurations from a `servers.json` file.
-   Connects to each specified server via SSH.
-   **Automated Dependency Installation**:
    -   Updates system packages.
    -   Installs Git, cURL, GnuPG, OpenSSL, and other essential tools.
    -   Installs Docker Engine and Docker Compose plugin if not already present.
    -   Installs Nginx web server if not already present.
-   **Supabase Setup**:
    -   Clones the official Supabase GitHub repository (or pulls updates if it already exists) into a configurable path (default: `/opt/supabase_instance`).
    -   Copies `docker/.env.example` to `docker/.env`.
    -   Automatically generates and sets secure random values for critical `.env` variables:
        -   `POSTGRES_PASSWORD`
        -   `JWT_SECRET` (at least 32 characters, used for signing all JWTs)
        -   `DASHBOARD_PASSWORD` (for Supabase Studio login)
    -   Configures `SITE_URL`, `API_EXTERNAL_URL`, and `SUPABASE_PUBLIC_URL` in `.env` based on the provided domain or IP.
    -   Pulls the latest Supabase Docker images.
    -   Starts all Supabase services using `docker compose up -d`.
-   **Nginx Reverse Proxy Configuration**:
    -   **For Domain Names**:
        -   Configures Nginx to serve Supabase initially over HTTP.
        -   Installs Certbot (if not present).
        -   Uses Certbot with the `--nginx` plugin to obtain a free SSL certificate from Let's Encrypt.
        -   Automatically configures Nginx for HTTPS and sets up HTTP to HTTPS redirection.
        -   Enables Certbot's auto-renewal cron job/systemd timer.
    -   **For IP Addresses**:
        -   Configures Nginx to serve Supabase over HTTP.
        -   Sets up an HTTPS listener (port 443) using self-signed "snakeoil" certificates to redirect all HTTPS traffic to HTTP. (Browser warnings will appear for direct HTTPS access to the IP due to the self-signed cert).
-   **Firewall (UFW) Configuration**:
    -   Optionally installs and configures UFW (Uncomplicated Firewall).
    -   Allows traffic on SSH (22), HTTP (80), and HTTPS (443) ports.
    -   Denies other incoming connections by default.

## Prerequisites

### Local Machine (where you run `self_host.sh`)

-   `bash` shell.
-   `jq`: For parsing the `servers.json` file. Install via your package manager (e.g., `sudo apt install jq` on Debian/Ubuntu).
-   `ssh` client.
-   `scp` client (typically included with `ssh`).
-   `sshpass`: (Optional) Only if you intend to use password-based SSH authentication. Key-based authentication is strongly recommended. Install via `sudo apt install sshpass`.
-   The following files must be in the same directory as `self_host.sh`:
    -   `servers.json`: Configuration file for your VPS instances.
    -   `supabase.nginx.secure.template`: Nginx template for domain-based setups.
    -   `supabase.nginx.insecure.template`: Nginx template for IP-based setups.

### Remote VPS

-   A Debian or Ubuntu-based Linux distribution (e.g., Ubuntu 20.04, 22.04; Debian 10, 11).
-   Root access or a user account with `sudo` privileges (the script executes most commands with `sudo`).
-   Internet connectivity for downloading packages and Docker images.
-   Ensure your VPS firewall (if managed by your cloud provider) allows inbound traffic on SSH (22), HTTP (80), and HTTPS (443) ports.

## `servers.json` Configuration File

Create a `servers.json` file in the same directory as the `self_host.sh` script. It should be an array of server objects:

```json
[
  {
    "name": "MySupabaseServer1",
    "host": "your_server_ip_or_hostname",
    "user": "root",
    "password": "your_ssh_password",
    "domain_or_ip": "supabase.yourdomain.com",
    "certbot_email": "youremail@example.com",
    "supabase_path": "/opt/supabase_main",
    "enable_ufw": true
  },
  {
    "name": "SupabaseTestIP",
    "host": "another_server_ip",
    "user": "your_sudo_user",
    "domain_or_ip": "the_same_server_ip_as_host",
    "certbot_email": "dev@example.com",
    "supabase_path": "/opt/supabase_test",
    "enable_ufw": false
  }
]
