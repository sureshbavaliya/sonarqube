#!/bin/bash

set -e

SONAR_VERSION="26.2.0.119303"
SONAR_DIR="/opt/sonarqube"
SONAR_USER="sonar"
DB_NAME="sonarqube"
DB_USER="sonar"
DB_PASS="StrongPassword123"

echo "Updating system..."
sudo apt update -y

echo "Installing dependencies..."
sudo apt install -y openjdk-21-jdk wget unzip apache2 postgresql postgresql-contrib

echo "Setting kernel parameters..."
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

echo "Creating database..."

sudo -u postgres psql <<EOF
CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASS';
CREATE DATABASE $DB_NAME OWNER $DB_USER;
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF

echo "Creating sonar user..."
sudo useradd -m -d $SONAR_DIR -r -s /bin/bash $SONAR_USER || true

echo "Downloading SonarQube..."

cd /opt
sudo wget https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SONAR_VERSION}.zip

echo "Extracting SonarQube..."
sudo unzip sonarqube-${SONAR_VERSION}.zip

sudo mv sonarqube-${SONAR_VERSION} sonarqube
sudo chown -R $SONAR_USER:$SONAR_USER $SONAR_DIR

echo "Configuring database connection..."

sudo sed -i "s/#sonar.jdbc.username=/sonar.jdbc.username=$DB_USER/" $SONAR_DIR/conf/sonar.properties
sudo sed -i "s/#sonar.jdbc.password=/sonar.jdbc.password=$DB_PASS/" $SONAR_DIR/conf/sonar.properties
sudo sed -i "s|#sonar.jdbc.url=jdbc:postgresql://localhost/sonarqube|sonar.jdbc.url=jdbc:postgresql://localhost:5432/$DB_NAME|" $SONAR_DIR/conf/sonar.properties

echo "Creating systemd service..."

sudo tee /etc/systemd/system/sonarqube.service > /dev/null <<EOF
[Unit]
Description=SonarQube Service
After=network.target

[Service]
Type=forking
User=$SONAR_USER
Group=$SONAR_USER
ExecStart=$SONAR_DIR/bin/linux-x86-64/sonar.sh start
ExecStop=$SONAR_DIR/bin/linux-x86-64/sonar.sh stop
Restart=always
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

echo "Starting SonarQube..."

sudo systemctl daemon-reload
sudo systemctl enable sonarqube
sudo systemctl start sonarqube

echo "Configuring Apache reverse proxy..."

sudo a2enmod proxy
sudo a2enmod proxy_http

sudo tee /etc/apache2/sites-available/sonarqube.conf > /dev/null <<EOF
<VirtualHost *:80>

ProxyPreserveHost On
ProxyPass / http://127.0.0.1:9000/
ProxyPassReverse / http://127.0.0.1:9000/

ErrorLog \${APACHE_LOG_DIR}/sonarqube_error.log
CustomLog \${APACHE_LOG_DIR}/sonarqube_access.log combined

</VirtualHost>
EOF

sudo a2ensite sonarqube
sudo systemctl restart apache2

IP=$(hostname -I | awk '{print $1}')

echo "--------------------------------------"
echo "SonarQube Installation Completed"
echo "URL: http://$IP"
echo "Login: admin / admin"
echo "--------------------------------------"