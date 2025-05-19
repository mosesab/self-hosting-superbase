#!/bin/bash

# =========================================================================
# Supabase Self-Hosting Script: self_host.sh
#
# Purpose:
#   Automates the deployment and configuration of a self-hosted Supabase
#   instance on one or more VPS servers.
#
# Workflow:
#   1. Reads server configurations from 'servers.json'.
#   2. For each server:
#      a. Connects via SSH.
#      b. Executes a remote script that:
#         i.   Updates package lists and installs essential prerequisites
#              (git, curl, gnupg, etc.).
#         ii.  Installs Docker and Docker Compose plugin if not present.
#         iii. Installs Nginx if not present.
#         iv.  Clones the Supabase repository (or pulls updates).
#         v.   Sets up Supabase .env file with generated secrets and
#              configured URLs.
#         vi.  Pulls Supabase Docker images and starts services.
#         vii. Configures Nginx as a reverse proxy:
#              - For domain names: Sets up HTTP, then uses Certbot for SSL
#                (HTTPS) and auto-renewal.
#              - For IP addresses: Sets up HTTP, and redirects HTTPS to HTTP
#                using self-signed (snakeoil) certificates.
#         viii.Installs and configures UFW firewall (optional, enabled by default).
#
# Prerequisites (Local Machine):
#   - jq (JSON processor)
#   - ssh client
#   - scp client
#   - sshpass (if using password-based SSH authentication)
#   - 'servers.json' file in the same directory as this script.
#   - 'supabase.secure.template.txt' and 'supabase.insecure.template.txt'
#     Nginx templates in the same directory.
#
# Prerequisites (Remote VPS - script attempts to install):
#   - Ubuntu or Debian-based Linux distribution.
#   - Internet access for downloading packages and Docker images.
#   - Root or sudo access for the SSH user.
#
# servers.json structure:
# [
#   {
#     "name": "MySupabaseServer1",
#     "host": "server1.example.com", # or IP address
#     "user": "root", # or a sudo-enabled user
#     "password": "your_ssh_password", # Optional, key-based auth preferred
#     "domain_or_ip": "supabase.example.com", # Domain for SSL or server IP
#     "certbot_email": "youremail@example.com", # For Let's Encrypt (if using domain)
#     "supabase_path": "/opt/supabase_instance", # Path to install supabase repo
#     "enable_ufw": true # Optional, true by default to setup UFW firewall
#   }
# ]
#
# Usage:
#   bash ./self_host.sh
#   LOG_LEVEL=2 bash ./self_host.sh  (For verbose debug output)
# =========================================================================

set -eo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
SERVERS_CONFIG_FILE="$SCRIPT_DIR/servers.json"
NGINX_SECURE_TEMPLATE_FILE="$SCRIPT_DIR/supabase.secure.template.txt"
NGINX_INSECURE_TEMPLATE_FILE="$SCRIPT_DIR/supabase.insecure.template.txt"

# Log levels: 0=silent, 1=info, 2=debug
LOG_LEVEL="${LOG_LEVEL:-1}"

# --- Helper Functions ---
log_info() {
    if [ "$LOG_LEVEL" -ge 1 ]; then echo "INFO: $1"; fi
}

log_debug() {
    if [ "$LOG_LEVEL" -ge 2 ]; then echo "DEBUG: $1"; fi
}

run_ssh_command() {
    local host=$1 user=$2 password=$3 command_to_run=$4
    log_debug "SSH CMD to $user@$host: $command_to_run"
    if [ -n "$password" ]; then
        if ! command -v sshpass &> /dev/null; then
            echo "ERROR: sshpass is not installed. Please install it (e.g., sudo apt install sshpass) or use SSH key authentication." >&2
            return 1
        fi
        sshpass -p "$password" ssh -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -o "ConnectTimeout=30" "$user@$host" "$command_to_run"
    else
        ssh -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -o "ConnectTimeout=30" "$user@$host" "$command_to_run"
    fi
}

# --- Sanity Checks ---
if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is not installed locally. Please install it (e.g., sudo apt install jq)." >&2
    exit 1
fi
if [ ! -f "$SERVERS_CONFIG_FILE" ]; then
    echo "ERROR: Server configuration file '$SERVERS_CONFIG_FILE' not found." >&2
    exit 1
fi
if [ ! -f "$NGINX_SECURE_TEMPLATE_FILE" ]; then
    echo "ERROR: Nginx secure template '$NGINX_SECURE_TEMPLATE_FILE' not found." >&2
    exit 1
fi
if [ ! -f "$NGINX_INSECURE_TEMPLATE_FILE" ]; then
    echo "ERROR: Nginx insecure template '$NGINX_INSECURE_TEMPLATE_FILE' not found." >&2
    exit 1
fi

# Load Nginx templates into variables (Base64 encoded for safe transfer)
NGINX_SECURE_TEMPLATE_B64=$(base64 -w 0 < "$NGINX_SECURE_TEMPLATE_FILE")
NGINX_INSECURE_TEMPLATE_B64=$(base64 -w 0 < "$NGINX_INSECURE_TEMPLATE_FILE")

# --- Main Loop ---
jq -c '.[]' "$SERVERS_CONFIG_FILE" | while IFS= read -r server_json; do
    SERVER_NAME=$(echo "$server_json" | jq -r '.name')
    SERVER_HOST=$(echo "$server_json" | jq -r '.host')
    SERVER_USER=$(echo "$server_json" | jq -r '.user')
    SERVER_PASSWORD=$(echo "$server_json" | jq -r '.password // empty')
    DOMAIN_OR_IP=$(echo "$server_json" | jq -r '.domain_or_ip')
    CERTBOT_EMAIL=$(echo "$server_json" | jq -r '.certbot_email // "default@example.com"') # Provide a default or make mandatory
    SUPABASE_INSTALL_PATH=$(echo "$server_json" | jq -r '.supabase_path // "/opt/supabase_instance"')
    ENABLE_UFW=$(echo "$server_json" | jq -r '.enable_ufw // "true"')


    log_info "--- Starting Supabase deployment to $SERVER_NAME ($SERVER_HOST) for $DOMAIN_OR_IP ---"

    # heredoc content must be carefully escaped if variables are expanded locally.
    # Here, variables like $LOG_LEVEL are expanded locally.
    # Variables like \$REMOTE_VAR are for remote expansion.
    REMOTE_SCRIPT=$(cat <<EOF
        set -eo pipefail
        export DEBIAN_FRONTEND=noninteractive # Supress interactive prompts during apt installs

        LOG_LEVEL=$LOG_LEVEL # Inherited from parent script
        TARGET_DOMAIN_OR_IP="$DOMAIN_OR_IP"
        TARGET_CERTBOT_EMAIL="$CERTBOT_EMAIL"
        TARGET_SUPABASE_PATH="$SUPABASE_INSTALL_PATH"
        TARGET_ENABLE_UFW="$ENABLE_UFW"
        NGINX_SECURE_TEMPLATE_CONTENT_B64="$NGINX_SECURE_TEMPLATE_B64"
        NGINX_INSECURE_TEMPLATE_CONTENT_B64="$NGINX_INSECURE_TEMPLATE_B64"

        # --- Remote Helper Functions ---
        log_remote_info() { if [ "\$LOG_LEVEL" -ge 1 ]; then echo "REMOTE INFO (\$HOSTNAME): \$1"; fi }
        log_remote_debug() { if [ "\$LOG_LEVEL" -ge 2 ]; then echo "REMOTE DEBUG (\$HOSTNAME): \$1"; fi }
        log_remote_error() { echo "REMOTE ERROR (\$HOSTNAME): \$1" >&2; }

        exec_cmd() {
            log_remote_debug "Executing: \$@"
            if [ "\$LOG_LEVEL" -ge 2 ]; then
                sudo "\$@" # Assuming sudo is needed for most system changes
            else
                sudo "\$@" > /dev/null 2>&1
            fi
            local status=\$?
            if [ \$status -ne 0 ]; then
                log_remote_error "Command '\$@' failed with status \$status"
            fi
            return \$status
        }
        exec_cmd_nosudo() { # For commands that should not run with sudo (e.g. user-level git)
            log_remote_debug "Executing (no sudo): \$@"
            if [ "\$LOG_LEVEL" -ge 2 ]; then
                "\$@"
            else
                "\$@" > /dev/null 2>&1
            fi
            local status=\$?
            if [ \$status -ne 0 ]; then
                log_remote_error "Command '\$@' failed with status \$status"
            fi
            return \$status
        }
        exec_cmd_visible() {
            log_remote_debug "Executing (visible): \$@"
            sudo "\$@"
            local status=\$?
            if [ \$status -ne 0 ]; then
                log_remote_error "Command (visible) '\$@' failed with status \$status"
            fi
            return \$status
        }

        is_ip_address() {
            if [[ "\$1" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then return 0; else return 1; fi
        }
        
        # --- 1. System Update and Prerequisites ---
        log_remote_info "Updating system packages..."
        exec_cmd apt-get update -y
        # exec_cmd apt-get upgrade -y # Can be time-consuming, optional

        log_remote_info "Installing essential tools (git, curl, gnupg, openssl, lsb-release, ca-certificates)..."
        exec_cmd apt-get install -y git curl gnupg openssl lsb-release ca-certificates apt-transport-https software-properties-common

        # --- 2. Docker and Docker Compose Installation ---
        if ! command -v docker &> /dev/null; then
            log_remote_info "Installing Docker..."
            exec_cmd install -m 0755 -d /etc/apt/keyrings
            local docker_gpg_key="/etc/apt/keyrings/docker.gpg"
            if [ -f "\$docker_gpg_key" ]; then exec_cmd rm -f "\$docker_gpg_key"; fi
            
            # Add Docker's official GPG key:
            local os_id=\$(. /etc/os-release && echo "\$ID")
            curl -fsSL "https://download.docker.com/linux/\${os_id}/gpg" | sudo gpg --dearmor -o "\$docker_gpg_key"
            exec_cmd chmod a+r "\$docker_gpg_key"

            echo "deb [arch=\$(dpkg --print-architecture) signed-by=\$docker_gpg_key] https://download.docker.com/linux/\${os_id} \$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            exec_cmd apt-get update -y
            exec_cmd apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            exec_cmd systemctl enable docker
            exec_cmd systemctl start docker
            log_remote_info "Docker installed."
        else
            log_remote_info "Docker is already installed."
            exec_cmd systemctl enable docker # Ensure it's enabled
            exec_cmd systemctl start docker  # Ensure it's running
        fi

        if ! sudo docker compose version &> /dev/null; then # Check with sudo as docker group might not be set yet for current user
            log_remote_error "Docker Compose plugin not found or not working after install. Attempting to reinstall..."
            exec_cmd apt-get install --reinstall -y docker-compose-plugin
            if ! sudo docker compose version &> /dev/null; then
                log_remote_error "Failed to verify Docker Compose plugin. Manual intervention might be required."
                # exit 1 # Potentially exit if critical
            fi
        else
            log_remote_info "Docker Compose plugin is available."
        fi
        # Add current user to docker group to run docker commands without sudo (takes effect on new login)
        # For script execution, we will continue to use 'sudo docker' or 'sudo docker compose'
        # if [ "\$(whoami)" != "root" ]; then
        #    sudo usermod -aG docker "\$(whoami)"
        #    log_remote_info "Added \$(whoami) to docker group. You may need to re-login for this to take effect for interactive sessions."
        # fi


        # --- 3. Nginx Installation ---
        if ! command -v nginx &> /dev/null; then
            log_remote_info "Installing Nginx..."
            exec_cmd apt-get install -y nginx
            exec_cmd systemctl enable nginx
            exec_cmd systemctl start nginx
            log_remote_info "Nginx installed."
        else
            log_remote_info "Nginx is already installed."
            exec_cmd systemctl enable nginx # Ensure it's enabled
            exec_cmd systemctl start nginx  # Ensure it's running
        fi

        # --- 4. Supabase Setup ---
        log_remote_info "Setting up Supabase in \$TARGET_SUPABASE_PATH..."
        sudo mkdir -p "\$TARGET_SUPABASE_PATH"
        # Change ownership to current user to clone without sudo, then use sudo for docker commands
        sudo chown -R "\$(whoami)":"\$(id -g -n \$(whoami))" "\$TARGET_SUPABASE_PATH"
        
        cd "\$TARGET_SUPABASE_PATH"
        if [ ! -d "supabase/.git" ]; then # Check for .git dir for robustness
            log_remote_info "Cloning Supabase repository..."
            exec_cmd_nosudo git clone --depth 1 https://github.com/supabase/supabase .
        else
            log_remote_info "Supabase repository exists. Pulling latest changes..."
            # exec_cmd_nosudo git reset --hard # Optional: force clean
            exec_cmd_nosudo git pull
        fi
        
        cd "docker"
        if [ ! -f ".env" ]; then
            log_remote_info "Creating .env file from .env.example..."
            cp .env.example .env # No sudo, user owns dir
        else
            log_remote_info ".env file already exists."
        fi

        log_remote_info "Configuring Supabase .env variables..."
        # Define a function to update .env variables
        update_env_var() {
            local key="\$1"
            local value="\$2"
            local env_file=".env"
            # Escape special characters for sed
            local escaped_value=\$(echo "\$value" | sed -e 's/[\/&]/\\&/g')
            if grep -q "^\${key}=" "\$env_file"; then
                sed -i "s/^\${key}=.*/\${key}=\${escaped_value}/" "\$env_file"
            else
                echo "\${key}=\${escaped_value}" >> "\$env_file"
            fi
            log_remote_info "Set \${key} in .env"
        }

        # Generate and set secrets if they are placeholders or default
        # POSTGRES_PASSWORD
        if grep -q "YOUR_POSTGRES_PASSWORD" .env || ! grep -q "^POSTGRES_PASSWORD=.\+" .env; then
             update_env_var "POSTGRES_PASSWORD" "\$(openssl rand -base64 32)"
        fi
        # JWT_SECRET
        if grep -q "YOUR_JWT_SECRET_WHICH_IS_AT_LEAST_32_CHARACTERS_LONG" .env || \
           grep -q "super-secret-jwt-token-with-at-least-32-characters-long" .env || \
           ! grep -q "^JWT_SECRET=.\+" .env; then
             update_env_var "JWT_SECRET" "\$(openssl rand -base64 64)"
        fi
        # DASHBOARD_PASSWORD (for Supabase Studio)
        if grep -q "YOUR_DASHBOARD_PASSWORD" .env || ! grep -q "^DASHBOARD_PASSWORD=.\+" .env; then
            update_env_var "DASHBOARD_PASSWORD" "\$(openssl rand -base64 32)"
            # Optionally set DASHBOARD_USERNAME if needed, e.g., "admin"
            # update_env_var "DASHBOARD_USERNAME" "admin"
        fi
        
        # ANON_KEY and SERVICE_ROLE_KEY are often generated by Kong/GoTrue based on JWT_SECRET.
        # If they are the known insecure examples from very old .env.example, clear them or replace.
        # The current .env.example has placeholders like "YOUR_ANON_KEY".
        # Supabase should regenerate these if they are placeholders or invalid w.r.t. JWT_SECRET.
        # For now, we ensure JWT_SECRET is strong.
        # If specific placeholders exist, replace them to trigger regeneration.
        update_env_var "ANON_KEY" "YOUR_ANON_KEY" # If this is the value, Supabase will regenerate
        update_env_var "SERVICE_ROLE_KEY" "YOUR_SERVICE_KEY" # Same here

        # Configure URLs
        local site_protocol="http"
        if ! is_ip_address "\$TARGET_DOMAIN_OR_IP"; then
            site_protocol="https"
        fi
        update_env_var "SITE_URL" "\${site_protocol}://\$TARGET_DOMAIN_OR_IP"
        update_env_var "API_EXTERNAL_URL" "\${site_protocol}://\$TARGET_DOMAIN_OR_IP"
        update_env_var "SUPABASE_PUBLIC_URL" "\${site_protocol}://\$TARGET_DOMAIN_OR_IP" # For Studio

        # Ensure KONG ports are standard
        update_env_var "KONG_HTTP_PORT" "8000"
        update_env_var "KONG_HTTPS_PORT" "8443"


        log_remote_info "Pulling Supabase Docker images..."
        exec_cmd_visible docker compose pull

        log_remote_info "Starting Supabase services..."
        exec_cmd_visible docker compose up -d --remove-orphans
        log_remote_info "Supabase services started. It might take a few minutes for them to be fully operational."
        log_remote_info "You can check logs using: sudo docker compose -f \$TARGET_SUPABASE_PATH/docker/docker-compose.yml logs -f"

        # --- 5. Nginx Reverse Proxy Configuration ---
        local nginx_config_name="supabase_config" # Generic name
        local nginx_available_path="/etc/nginx/sites-available/\$nginx_config_name"
        local nginx_enabled_path="/etc/nginx/sites-enabled/\$nginx_config_name"
        local nginx_template_content=""

        # Remove default Nginx config if it exists to avoid conflicts
        if [ -f "/etc/nginx/sites-enabled/default" ]; then
            log_remote_info "Removing default Nginx site configuration..."
            exec_cmd rm -f /etc/nginx/sites-enabled/default
        fi
        # Remove previous config if script is re-run
        if [ -f "\$nginx_enabled_path" ]; then
            exec_cmd rm -f "\$nginx_enabled_path"
        fi
         if [ -f "\$nginx_available_path" ]; then
            exec_cmd rm -f "\$nginx_available_path"
        fi


        if is_ip_address "\$TARGET_DOMAIN_OR_IP"; then
            log_remote_info "Configuring Nginx for IP address (HTTP): \$TARGET_DOMAIN_OR_IP"
            nginx_template_content=\$(echo "\$NGINX_INSECURE_TEMPLATE_CONTENT_B64" | base64 -d)
            
            # Ensure snakeoil certs for HTTPS->HTTP redirect part
            if [ ! -f /etc/ssl/certs/ssl-cert-snakeoil.pem ] || [ ! -f /etc/ssl/private/ssl-cert-snakeoil.key ]; then
                log_remote_info "Generating self-signed snakeoil certificates..."
                exec_cmd apt-get install -y ssl-cert
                exec_cmd make-ssl-cert generate-default-snakeoil --force-overwrite
            fi
        else
            log_remote_info "Configuring Nginx for domain (HTTPS via Certbot): \$TARGET_DOMAIN_OR_IP"
            nginx_template_content=\$(echo "\$NGINX_SECURE_TEMPLATE_CONTENT_B64" | base64 -d)
            
            # Install Certbot if not present
            if ! command -v certbot &> /dev/null; then
                log_remote_info "Installing Certbot..."
                exec_cmd apt-get install -y certbot python3-certbot-nginx
                log_remote_info "Certbot installed."
            else
                log_remote_info "Certbot is already installed."
            fi
            # Create Certbot webroot dir
            sudo mkdir -p /var/www/certbot
            sudo chown www-data:www-data /var/www/certbot # Or nginx user
        fi

        echo "\$nginx_template_content" | sudo sed "s/{{SUBDOMAIN_ADDRESS}}/\$TARGET_DOMAIN_OR_IP/g" | sudo tee "\$nginx_available_path" > /dev/null
        log_remote_info "Nginx config written to \$nginx_available_path"
        
        exec_cmd ln -sf "\$nginx_available_path" "\$nginx_enabled_path"
        log_remote_info "Nginx config symlinked to \$nginx_enabled_path"

        log_remote_info "Testing Nginx configuration..."
        if ! sudo nginx -t; then
            log_remote_error "Nginx configuration test failed. Please check \$nginx_available_path"
            # Dump current config for debugging
            log_remote_error "Contents of \$nginx_available_path:"
            sudo cat "\$nginx_available_path" >&2 # Output to stderr for visibility
            exit 1
        fi
        log_remote_info "Nginx configuration test successful."
        exec_cmd systemctl reload nginx # Reload first before potential Certbot changes

        if ! is_ip_address "\$TARGET_DOMAIN_OR_IP"; then
            log_remote_info "Requesting SSL certificate from Let's Encrypt for \$TARGET_DOMAIN_OR_IP..."
            # The --nginx plugin will modify the Nginx config file for SSL.
            # It needs an email and agreement to ToS.
            exec_cmd_visible certbot --nginx -d "\$TARGET_DOMAIN_OR_IP" --non-interactive --agree-tos -m "\$TARGET_CERTBOT_EMAIL" --redirect
            log_remote_info "Certbot SSL setup complete. Auto-renewal should be configured."
        fi

        log_remote_info "Restarting Nginx to apply all changes..."
        exec_cmd_visible systemctl restart nginx

        # --- 6. Firewall Configuration (UFW) ---
        if [ "\$TARGET_ENABLE_UFW" == "true" ]; then
            if ! command -v ufw &> /dev/null; then
                log_remote_info "Installing UFW firewall..."
                exec_cmd apt-get install -y ufw
            fi
            log_remote_info "Configuring UFW firewall..."
            exec_cmd ufw default deny incoming
            exec_cmd ufw default allow outgoing
            exec_cmd ufw allow ssh
            exec_cmd ufw allow http  # Port 80
            exec_cmd ufw allow https # Port 443
            # Supabase Studio is accessed via Nginx (80/443), direct ports not needed externally.
            # If you have other services, open their ports here.
            yes | sudo ufw enable # auto-confirm enable
            exec_cmd_visible ufw status verbose
            log_remote_info "UFW firewall configured and enabled."
        else
            log_remote_info "UFW firewall setup skipped as per configuration."
        fi

        log_remote_info "Supabase deployment for \$TARGET_DOMAIN_OR_IP completed."
        log_remote_info "Access Supabase Studio at: \${site_protocol}://\$TARGET_DOMAIN_OR_IP"
        log_remote_info "Important: Check Supabase service logs for any errors or important messages (like generated API keys if they were placeholders):"
        log_remote_info "  sudo docker compose -f \$TARGET_SUPABASE_PATH/docker/docker-compose.yml logs supabase-kong"
        log_remote_info "  sudo docker compose -f \$TARGET_SUPABASE_PATH/docker/docker-compose.yml logs supabase-gotrue"

EOF
    ) # End of REMOTE_SCRIPT heredoc

    # Execute the remote script
    if run_ssh_command "$SERVER_HOST" "$SERVER_USER" "$SERVER_PASSWORD" "bash -s"; then
        log_info "--- Successfully deployed Supabase to $SERVER_NAME ($DOMAIN_OR_IP) ---"
    else
        echo "ERROR: Supabase deployment FAILED for $SERVER_NAME ($DOMAIN_OR_IP). Check output above." >&2
        # Consider whether to exit or continue with other servers
        # exit 1
    fi
    echo # Newline for readability between server deployments

done # End of server loop

log_info "All Supabase deployments processed."
exit 0
