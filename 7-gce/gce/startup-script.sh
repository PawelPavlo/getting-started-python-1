#! /bin/bash
# Copyright 2015 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# [START startup]
set -v

# Talk to the metadata server to get the project id
PROJECTID=$(curl -s "http://metadata.google.internal/computeMetadata/v1/project/project-id" -H "Metadata-Flavor: Google")

# Install logging monitor. The monitor will automatically pickup logs sent to
# syslog.
# [START logging]
curl -s "https://storage.googleapis.com/signals-agents/logging/google-fluentd-install.sh" | bash
service google-fluentd restart &
# [END logging]

# Install dependencies from apt
apt-get update
apt-get install -yq \
    git build-essential supervisor python python-dev python-pip libffi-dev \
    libssl-dev mysql-client

# Create a pythonapp user. The application will run as this user.
useradd -m -d /home/pythonapp pythonapp

# pip from apt is out of date, so make it update itself and install virtualenv.
pip install --upgrade pip virtualenv

#Start get cloud sql-proxy-------PAVLO
wget https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O cloud_sql_proxy
chmod +x cloud_sql_proxy
cp cloud_sql_proxy /usr/local/bin/cloud_sql_proxy

#Create Cloudsql service
cat >/etc/systemd/system/cloud-sql-proxy.service << EOF
[Unit]
Description=Connecting MySQL Client from Compute Engine using the Cloud SQL Proxy
Documentation=https://cloud.google.com/sql/docs/mysql/connect-compute-engine
Requires=networking.service
After=networking.service

[Service]
WorkingDirectory=/usr/local/bin
ExecStart=/usr/local/bin/cloud_sql_proxy -instances=bookshelf-project-319721:us-central1-a:bookshelf=tcp:3306
Restart=always
StandardOutput=journal
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl enable cloud-sql-proxy.service
systemctl start cloud-sql-proxy.service


# Get the source code from the Google Cloud Repository
# git requires $HOME and it's not set during the startup script.
export HOME=/root
git config --global credential.helper gcloud.sh
#git clone https://source.developers.google.com/p/$PROJECTID/r/[YOUR_REPO_NAME] /opt/app
git clone -b steps https://github.com/PawelPavlo/getting-started-python-1.git /opt/app
# Install app dependencies
virtualenv -p python3 /opt/app/7-gce/env
# virtualenv -p python3 /
source /opt/app/7-gce/env/bin/activate
#create database infrastructure
/opt/app/7-gce/env/bin/python /opt/app/7-gce/bookshelf/model_cloudsql.py

/opt/app/7-gce/env/bin/pip install -r /opt/app/7-gce/requirements.txt

# Make sure the pythonapp user owns the application code
chown -R pythonapp:pythonapp /opt/app

# Configure supervisor to start gunicorn inside of our virtualenv and run the
# application.
cat >/etc/supervisor/conf.d/python-app.conf << EOF
[program:pythonapp]
directory=/opt/app/7-gce
command=/opt/app/7-gce/env/bin/honcho start -f ./procfile worker bookshelf
autostart=true
autorestart=true
user=pythonapp
# Environment variables ensure that the application runs inside of the
# configured virtualenv.
environment=VIRTUAL_ENV="/opt/app/7-gce/env",PATH="/opt/app/7-gce/env/bin",\
    HOME="/home/pythonapp",USER="pythonapp"
stdout_logfile=syslog
stderr_logfile=syslog
EOF

supervisorctl reread
supervisorctl update

# Application should now be running under supervisor
# [END startup]
