#!/bin/bash

set -e

echo "Updating system..."
sudo apt update -y

echo "Installing dependencies..."
sudo apt install -y openjdk-17-jdk wget unzip curl apache2 postgresql postgresql-contrib ufw

echo "Configuring system limits for SonarQube..."
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

echo "Creating SonarQube database..."

sudo -u postgres psql <<EOF
CREATE USER sonar WITH ENCRYPTED PASSWORD 'StrongPassword123';
CREATE DATABASE sonarqube OWNER sonar;
GRANT ALL PRIVILEGES ON DATABASE sonarqube TO sonar;
EOF

echo "Creating sonar user..."
sudo useradd -m -d /opt/sonarqube -r -s /bin/bash sonar || true

echo "Downloading SonarQube..."

cd /opt
sudo wget https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-9.9.4.87374.zip

echo "Extracting SonarQube..."

sudo unzip sonarqube-*.zip
sudo mv sonarqube-* sonarqube

sudo chown -R sonar:sonar /opt/sonarqube

echo "Configuring SonarQube database..."

sudo sed -i "s/#sonar.jdbc.username=/sonar.jdbc.username=sonar/" /opt/sonarqube/conf/sonar.properties
sudo sed -i "s/#sonar.jdbc.password=/sonar.jdbc.password=StrongPassword123/" /opt/sonarqube/conf/sonar.properties
sudo sed -i "s|#sonar.jdbc.url=jdbc:postgresql://localhost/sonarqube|sonar.jdbc.url=jdbc:postgresql://localhost:5432/sonarqube|" /opt/sonarqube/conf/sonar.properties

echo "Creating SonarQube systemd service..."

sudo tee /etc/systemd/system/sonarqube.service > /dev/null <<EOF
[Unit]
Description=SonarQube service
After=syslog.target network.target

[Service]
Type=forking
User=sonar
Group=sonar
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
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

echo "Configuring Apache Reverse Proxy..."

sudo a2enmod proxy
sudo a2enmod proxy_http

sudo tee /etc/apache2/sites-available/sonarqube.conf > /dev/null <<EOF
<VirtualHost *:80>

ServerAdmin admin@localhost
ServerName sonarqube.local

ProxyPreserveHost On
ProxyPass / http://127.0.0.1:9000/
ProxyPassReverse / http://127.0.0.1:9000/

ErrorLog \${APACHE_LOG_DIR}/sonarqube_error.log
CustomLog \${APACHE_LOG_DIR}/sonarqube_access.log combined

</VirtualHost>
EOF

sudo a2ensite sonarqube.conf
sudo systemctl restart apache2

echo "Configuring Firewall..."

sudo ufw allow OpenSSH
sudo ufw allow 80
sudo ufw --force enable

echo "Installation completed!"

IP=$(hostname -I | awk '{print $1}')

echo "----------------------------------"
echo "Access SonarQube:"
echo "http://$IP"
echo ""
echo "Default Login:"
echo "username: admin"
echo "password: admin"
echo "----------------------------------"