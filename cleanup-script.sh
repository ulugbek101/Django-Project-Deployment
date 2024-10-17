#!/bin/bash

# Variables
PROJECT_NAME="simple_django_project"  # Name of the project
DB_NAME="${PROJECT_NAME}"                # Database name
DB_USER="${PROJECT_NAME}_user"           # Database user

# Function to log messages
log() {
    echo -e "\033[0;31m$(date '+%Y-%m-%d %H:%M:%S') - $1\033[0m"
}

log "Starting cleanup for $PROJECT_NAME..."

# Step 1: Stop the Gunicorn service
log "Stopping the Gunicorn service..."
sudo systemctl stop $PROJECT_NAME.service

# Step 2: Disable the Gunicorn service and socket
log "Disabling the Gunicorn service and socket..."
sudo systemctl disable $PROJECT_NAME.service
sudo systemctl disable $PROJECT_NAME.socket

# Step 3: Remove the Gunicorn service and socket files
log "Removing Gunicorn service and socket files..."
sudo rm /etc/systemd/system/$PROJECT_NAME.service
sudo rm /etc/systemd/system/$PROJECT_NAME.socket

# Step 4: Remove the Nginx configuration
log "Removing Nginx configuration..."
sudo rm /etc/nginx/sites-available/$PROJECT_NAME
sudo rm /etc/nginx/sites-enabled/$PROJECT_NAME

# Step 5: Reload Nginx to apply changes
log "Reloading Nginx..."
sudo systemctl reload nginx

# Step 6: Remove the PostgreSQL database and user
log "Removing PostgreSQL database and user..."
sudo -u postgres psql <<EOF
DROP DATABASE IF EXISTS $DB_NAME;
DROP USER IF EXISTS $DB_USER;
\q
EOF

# Step 7: Print completion message
log "Cleanup for $PROJECT_NAME completed successfully!"
