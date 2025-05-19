# self-hosting-superbase

# 🛠️ How to Self-Host Supabase on a VPS Server (in 2 minutes)

Self-hosting Supabase on a VPS server is a practical approach for developers seeking greater control, customization, and cost efficiency. By deploying Supabase on your own infrastructure, you can tailor the backend services to your specific needs. Here's a comprehensive guide to help you set up Supabase on a VPS:

---

## Prerequisites

Before you begin, ensure you have the following:

- **VPS Server**: A virtual private server running Ubuntu 20.04 or later.
- **Docker & Docker Compose**: Install Docker and Docker Compose on your VPS to manage containerized applications.
- **Domain Name (Optional)**: For accessing your Supabase instance via a custom domain.

---

## 🚀 Step-by-Step Deployment

### 1. Clone the Supabase Repository

```bash
cd /
git clone --depth 1 https://github.com/supabase/supabase
cd supabase/docker
````

### 2. Configure Environment Variables

```bash
cp .env.example .env
```

use `openssl rand -base64 64` to generate random secure keys

Edit the `.env` file to set secure values for your database passwords, API keys, and other configurations.
**See " Supabase Self-Hosting - Explanation of what each `.env` variable does" below for more information about .env variables.**


### 3. Pull Docker Images

```bash
docker compose pull
```

### 4. Start Supabase Services

```bash
docker compose up -d
```

This command starts all the services defined in the `docker-compose.yml` file.

---

### 6. Access Supabase Studio

Once the services are running, access Supabase Studio by navigating to:

```
http://<your-vps-ip>:8000
```

Log in using the credentials set in your `.env` file.

---

## 🔐 Securing Your Deployment

To ensure your Supabase instance is secure:

* **Change Default Credentials**: Update all default passwords and API keys in your `.env` file.
* **Set Up a Reverse Proxy**: Use Nginx or Traefik to manage incoming traffic.
* **Enable HTTPS**: Use Let's Encrypt to install an SSL certificate.
* **Configure Firewall Rules**: Restrict access to necessary ports and services.

---

## 🧩 Optional: Minimal Service Deployment

For a lightweight setup, start only essential services:

```bash
docker compose up kong db meta rest auth functions --no-deps -d
```
This runs the PostgreSQL database, REST API, authentication service, API gateway and edge functions.

For all services, read docker-compose.yml or view all the services in the commmand below:
```bash
docker compose up studio kong auth rest realtime storage meta db functions imgproxy analytics vector supavisor --no-deps -d
```

---

## 📚 Additional Resources

* [Supabase Self-Hosting Documentation](https://supabase.com/docs/guides/self-hosting)
* [Ultimate Supabase Self-Hosting Guide](https://blog.activeno.de/the-ultimate-supabase-self-hosting-guide)
* [Video Tutorial on YouTube](https://www.youtube.com/watch?v=lHfgnFmQ1Ds)

---

By following these steps, you can successfully deploy and manage a self-hosted Supabase instance on your VPS, granting you full control over your backend infrastructure.


<br><br>
<br><br>


# 📘 Supabase Self-Hosting - Explanation of what each `.env` variable does:

This document provides a detailed explanation of each environment variable found in the `.env` file used for self-hosting Supabase.

---

## 🔐 Secrets

| Key | Description |
|-----|-------------|
| `POSTGRES_PASSWORD` | Password for the default PostgreSQL `postgres` user. |
| `JWT_SECRET` | Secret key used to sign and verify JWTs (used across Auth and APIs). Must be at least 32 characters. |
| `ANON_KEY` | JWT with the `anon` role, typically used by frontend clients with limited access. |
| `SERVICE_ROLE_KEY` | JWT with the `service_role`, used server-side with full access to the database. Keep this private. |
| `DASHBOARD_USERNAME` | Username for logging into Supabase Studio (admin UI). |
| `DASHBOARD_PASSWORD` | Password for Studio login. Change it from the insecure default. |
| `SECRET_KEY_BASE` | Rails-style secret for Studio and internal apps; used for session encryption. |
| `VAULT_ENC_KEY` | 32+ char encryption key used by Vault (secrets manager) if enabled. |

---

## 🛢️ Database Settings

| Key | Description |
|-----|-------------|
| `POSTGRES_HOST` | Hostname for the PostgreSQL container (typically `db`). |
| `POSTGRES_DB` | Name of the database (default: `postgres`). |
| `POSTGRES_PORT` | Port PostgreSQL listens on (default: `5432`). |

---

## 🧩 Supavisor (PostgreSQL Pooler)

| Key | Description |
|-----|-------------|
| `POOLER_PROXY_PORT_TRANSACTION` | Port used for transactional pooling (default: `6543`). |
| `POOLER_DEFAULT_POOL_SIZE` | Number of connections in each pool. |
| `POOLER_MAX_CLIENT_CONN` | Max concurrent client connections allowed. |
| `POOLER_TENANT_ID` | Unique ID for multi-tenant setups (optional for single-tenant). |

---

## 🌐 Kong API Gateway (Reverse Proxy)

| Key | Description |
|-----|-------------|
| `KONG_HTTP_PORT` | HTTP port for Kong (default: `8000`). |
| `KONG_HTTPS_PORT` | HTTPS port for Kong (default: `8443`). |

---

## 📡 PostgREST API Config

| Key | Description |
|-----|-------------|
| `PGRST_DB_SCHEMAS` | Comma-separated list of database schemas that PostgREST exposes via API. Default includes `public`, `storage`, and `graphql_public`. |

---

## 🔐 GoTrue (Auth Server)

### General

| Key | Description |
|-----|-------------|
| `SITE_URL` | Base URL of your app (used for email links, redirects, etc.). |
| `ADDITIONAL_REDIRECT_URLS` | Optional comma-separated list of allowed redirect URLs. |
| `JWT_EXPIRY` | JWT token expiration time in seconds (default: `3600` = 1 hour). |
| `DISABLE_SIGNUP` | If `true`, disables all signups. |
| `API_EXTERNAL_URL` | External API base URL for GoTrue callbacks and communication. |

### Mailer

| Key | Description |
|-----|-------------|
| `MAILER_URLPATHS_CONFIRMATION` | Path for confirmation emails. |
| `MAILER_URLPATHS_INVITE` | Path for invitation emails. |
| `MAILER_URLPATHS_RECOVERY` | Path for password recovery emails. |
| `MAILER_URLPATHS_EMAIL_CHANGE` | Path for email change verification emails. |

### Email Auth

| Key | Description |
|-----|-------------|
| `ENABLE_EMAIL_SIGNUP` | Enables sign-up via email/password. |
| `ENABLE_EMAIL_AUTOCONFIRM` | If `true`, users are auto-confirmed (skip email verification). |
| `SMTP_ADMIN_EMAIL` | Admin email shown as sender or reply-to. |
| `SMTP_HOST`, `SMTP_PORT` | Mail server address and port. |
| `SMTP_USER`, `SMTP_PASS` | SMTP credentials. |
| `SMTP_SENDER_NAME` | Friendly name shown in emails. |
| `ENABLE_ANONYMOUS_USERS` | If `true`, allows anonymous (unregistered) users. |

### Phone Auth

| Key | Description |
|-----|-------------|
| `ENABLE_PHONE_SIGNUP` | Enables sign-up via phone. |
| `ENABLE_PHONE_AUTOCONFIRM` | Auto-confirms phone users after OTP validation. |

---

## 🖥️ Studio (Dashboard UI)

| Key | Description |
|-----|-------------|
| `STUDIO_DEFAULT_ORGANIZATION` | Default organization name shown in Studio. |
| `STUDIO_DEFAULT_PROJECT` | Default project name shown in Studio. |
| `STUDIO_PORT` | Port Studio runs on (default: `3000`). |
| `SUPABASE_PUBLIC_URL` | Public URL of your Supabase instance (used by Studio). |
| `IMGPROXY_ENABLE_WEBP_DETECTION` | Enables WebP image detection support in Studio. |
| `OPENAI_API_KEY` | Optional OpenAI API key to enable SQL editor assistant (AI autocomplete). |

---

## 🧠 Edge Functions

| Key | Description |
|-----|-------------|
| `FUNCTIONS_VERIFY_JWT` | If `true`, all edge functions require JWT verification. |

---

## 📈 Logflare (Analytics / Logs)

| Key | Description |
|-----|-------------|
| `LOGFLARE_LOGGER_BACKEND_API_KEY` | Backend key for Logflare logging. |
| `LOGFLARE_API_KEY` | Public Logflare API key (usually same as above). |
| `DOCKER_SOCKET_LOCATION` | Location of the Docker socket for analytics/logging (usually `/var/run/docker.sock`). |

### Google Cloud Integration (Optional)

| Key | Description |
|-----|-------------|
| `GOOGLE_PROJECT_ID` | Google Cloud project ID (if using GCP logging). |
| `GOOGLE_PROJECT_NUMBER` | Google Cloud project number. |
