#!/bin/bash

# Variables (customize these)
PROJECT_NAME="myproject"  # Custom project name
DB_NAME="custom_db_name"   # Custom database name
DB_USER="custom_db_user"   # Custom database user
DB_PASSWORD="custom_password"  # Custom database password
REPO_URL="https://github.com/username/repo.git"  # GitHub repo link
DOMAIN_NAME="www.domain.com domain.com"  # Custom domains
USER_NAME="www-data"  # User for Gunicorn service
PROJECT_DIR="/var/www/$PROJECT_NAME"  # Path to project directory
SOCKET_PATH="/run/$PROJECT_NAME.sock"

# Function to log messages
log() {
    echo -e "\033[0;32m$(date '+%Y-%m-%d %H:%M:%S') - $1\033[0m"
}

log "Starting deployment for $PROJECT_NAME..."

# Step 1: Install necessary packages
log "Updating package list and installing necessary packages..."
sudo apt update
sudo apt install -y python3-venv python3-dev libpq-dev postgresql postgresql-contrib nginx curl

# Step 2: Set up PostgreSQL database and user
log "Setting up PostgreSQL database and user..."
sudo -u postgres psql <<EOF
CREATE DATABASE $DB_NAME;
CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
ALTER ROLE $DB_USER SET client_encoding TO 'utf8';
ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';
ALTER ROLE $DB_USER SET timezone TO 'UTC';
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
\q
EOF

# Step 3: Clone the project from GitHub
log "Cloning the project from GitHub..."
git clone $REPO_URL $PROJECT_DIR
cd $PROJECT_DIR || { log "Failed to navigate to project directory"; exit 1; }

# Step 4: Create and activate the virtual environment
log "Creating and activating the virtual environment..."
python3 -m venv .venv
source .venv/bin/activate

# Step 5: Install dependencies
log "Installing dependencies from requirements.txt..."
pip install -r requirements.txt
pip install gunicorn

# Step 6: Deactivate the virtual environment
log "Deactivating the virtual environment..."
deactivate

# Step 7: Allow traffic on port 8000
log "Allowing traffic on port 8000..."
sudo ufw allow 8000

# Step 8: Create Gunicorn socket
log "Creating Gunicorn socket..."
sudo bash -c "cat > /etc/systemd/system/$PROJECT_NAME.socket" <<EOL
[Unit]
Description=$PROJECT_NAME socket

[Socket]
ListenStream=$SOCKET_PATH

[Install]
WantedBy=sockets.target
EOL

# Step 9: Create Gunicorn service
log "Creating Gunicorn service..."
sudo bash -c "cat > /etc/systemd/system/$PROJECT_NAME.service" <<EOL
[Unit]
Description=gunicorn daemon
Requires=$PROJECT_NAME.socket
After=network.target

[Service]
User=$USER_NAME
Group=www-data
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/.venv/bin/gunicorn \\
          --access-logfile - \\
          --workers 3 \\
          --bind unix:$SOCKET_PATH \\
          $PROJECT_NAME.wsgi:application

[Install]
WantedBy=multi-user.target
EOL

# Step 10: Change ownership and permissions for the project directory
log "Setting permissions for $USER_NAME on the project directory..."
sudo chown -R www-data:www-data $PROJECT_DIR
sudo find $PROJECT_DIR -type d -exec chmod 755 {} \;  # Directories: rwxr-xr-x
sudo find $PROJECT_DIR -type f -exec chmod 644 {} \;  # Files: rw-r--r--

# Step 11: Start and enable the Gunicorn socket
log "Starting and enabling Gunicorn socket..."
sudo systemctl start $PROJECT_NAME.socket
sudo systemctl enable $PROJECT_NAME.socket

# Step 12: Reload systemd and restart the Gunicorn service
log "Reloading systemd and restarting the Gunicorn service..."
sudo systemctl daemon-reload
sudo systemctl restart $PROJECT_NAME

# Step 13: Create Nginx configuration
log "Creating Nginx configuration..."
sudo bash -c "cat > /etc/nginx/sites-available/$PROJECT_NAME" <<EOL
server {
    listen 80;
    server_name $DOMAIN_NAME;

    location = /favicon.ico { access_log off; log_not_found off; }
    location /static/ {
        root $PROJECT_DIR; 
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:$SOCKET_PATH; 
    }
}
EOL

# Step 14: Create a symbolic link for Nginx configuration
log "Creating symbolic link for Nginx configuration..."
sudo ln -s /etc/nginx/sites-available/$PROJECT_NAME /etc/nginx/sites-enabled

# Step 15: Restart Nginx and update UFW
log "Restarting Nginx and updating UFW..."
sudo systemctl restart nginx
sudo ufw delete allow 8000
sudo ufw allow 'Nginx Full'

log "Deployment for $PROJECT_NAME completed successfully!"
