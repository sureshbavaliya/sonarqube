#!/bin/bash

set -e

SONAR_DIR=/opt/sonarqube
SONAR_USER=sonar
SONAR_DB=sonarqube
SONAR_DB_USER=sonar
SONAR_DB_PASS=StrongPassword123

echo "Updating system..."
sudo apt update -y

echo "Installing dependencies..."
sudo apt install -y openjdk-17-jdk wget unzip curl apache2 postgresql postgresql-contrib ufw jq

echo "Configuring kernel settings for SonarQube..."
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

echo "Creating SonarQube database..."

sudo -u postgres psql <<EOF
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$SONAR_DB_USER') THEN
      CREATE ROLE $SONAR_DB_USER LOGIN PASSWORD '$SONAR_DB_PASS';
   END IF;
END
\$\$;

CREATE DATABASE $SONAR_DB OWNER $SONAR_DB_USER;
GRANT ALL PRIVILEGES ON DATABASE $SONAR_DB TO $SONAR_DB_USER;
EOF

echo "Creating sonar user..."
sudo useradd -m -d $SONAR_DIR -r -s /bin/bash $SONAR_USER || true

echo "Fetching latest SonarQube Community version..."

SONAR_URL=$(curl -s https://binaries.sonarsource.com/Distribution/sonarqube/ | grep -oP 'sonarqube-[0-9.]+\.zip' | sort -V | tail -n 1)

echo "Latest package: $SONAR_URL"

cd /opt
sudo wget https://binaries.sonarsource.com/Distribution/sonarqube/$SONAR_URL

echo "Extracting SonarQube..."
sudo unzip $SONAR_URL

EXTRACTED=$(echo $SONAR_URL | sed 's/.zip//')

sudo mv $EXTRACTED $SONAR_DIR
sudo chown -R $SONAR_USER:$SONAR_USER $SONAR_DIR

echo "Configuring database..."

sudo sed -i "s/#sonar.jdbc.username=/sonar.jdbc.username=$SONAR_DB_USER/" $SONAR_DIR/conf/sonar.properties
sudo sed -i "s/#sonar.jdbc.password=/sonar.jdbc.password=$SONAR_DB_PASS/" $SONAR_DIR/conf/sonar.properties
sudo sed -i "s|#sonar.jdbc.url=jdbc:postgresql://localhost/sonarqube|sonar.jdbc.url=jdbc:postgresql://localhost:5432/$SONAR_DB|" $SONAR_DIR/conf/sonar.properties

echo "Creating systemd service..."

sudo tee /etc/systemd/system/sonarqube.service > /dev/null <<EOF
[Unit]
Description=SonarQube Service
After=syslog.target network.target

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

echo "Configuring firewall..."

sudo ufw allow OpenSSH
sudo ufw allow 80
sudo ufw --force enable

IP=$(hostname -I | awk '{print $1}')

echo "--------------------------------"
echo "SonarQube Installation Completed"
echo "Access URL: http://$IP"
echo ""
echo "Default Login:"
echo "username: admin"
echo "password: admin"
echo "--------------------------------"