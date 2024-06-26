#!/bin/bash

# Function to display error message and exit
display_error() {
    echo -e "\e[1;31mError: $1 at line $2\e[0m"
    exit 1
}

# Function to prompt user for input and validate
get_user_input() {
    read -p "$1" input
    if [[ -z "$input" ]]; then
        display_error "Input cannot be empty" $LINENO
    fi
    echo "$input"
}

# Function to display a menu for selection
display_menu() {
    local title=$1
    local prompt=$2
    shift 2
    local options=("$@")
    local choices
    choices=$(dialog --clear --backtitle "$title" --title "$prompt" --menu "$prompt" 15 50 4 "${options[@]}" 2>&1 >/dev/tty)
    clear
    echo "$choices"
}

# Clear the screen
clear

# Display header
echo ""
echo -e "\e[1;34m**********************************************\e[0m"
echo -e "\e[1;34m*         Ubuntu Super Server Setup          *\e[0m"
echo -e "\e[1;34m**********************************************\e[0m"
echo -e "\e[1;34m* This script will install a Webservice stack *\e[0m"
echo -e "\e[1;34m*               Apache2 Or Nginx              *\e[0m"
echo -e "\e[1;34m*    with phpMyAdmin, Node.js, and secure     *\e[0m"
echo -e "\e[1;34m*    your domain with Let's Encrypt SSL.      *\e[0m"
echo -e "\e[1;34m**********************************************\e[0m"
echo ""
apt-get install dialog -y
# Prompt user for domain, email, and MySQL root password
domain=$(get_user_input "Set Web Domain (Example: example.com): ")
email=$(get_user_input "Email for Let's Encrypt SSL: ")
mysql_root_password=$(get_user_input "Enter MySQL root password: ")

# Prompt user for PHP version using dialog
php_versions=("7.4" "" "8.0" "" "8.1" "" "8.2" "")
php_version=$(display_menu "Super Server Setup" "Choose PHP version" "${php_versions[@]}")
clear
# Prompt user to choose web server using dialog
echo "Choose your web server (apache/nginx): "
read web_server
web_server=$(echo $web_server | tr '[:upper:]' '[:lower:]')  # Convert to lowercase
clear
# Update system packages
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mUpdating system packages...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3
apt update && apt upgrade -y || display_error "Failed to update system packages" $LINENO
apt autoremove -y || display_error "Failed to autoremove packages" $LINENO

# Install required packages and repositories
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling required packages and repositories...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3
apt-get install -y default-jdk software-properties-common dialog || display_error "Failed to install packages" $LINENO
add-apt-repository -y ppa:ondrej/php || display_error "Failed to add PHP repository" $LINENO
add-apt-repository -y ppa:deadsnakes/ppa || display_error "Failed to add deadsnakes repository" $LINENO
add-apt-repository -y ppa:redislabs/redis || display_error "Failed to add Redis repository" $LINENO
apt update && apt upgrade -y || display_error "Failed to update system packages after adding repositories" $LINENO

# Install additional tools
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling additional tools...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3
apt install -y screen nano curl git zip unzip ufw || display_error "Failed to install additional tools" $LINENO
apt install -y python3.11 libmysqlclient-dev python3-dev python3-pip || display_error "Failed to install Python tools" $LINENO
ln -s /usr/bin/python3.11 /usr/bin/python || display_error "Failed to create symlink for Python" $LINENO
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py && python3 get-pip.py || display_error "Failed to install Python pip" $LINENO
python3 -m pip install Django || display_error "Failed to install Django" $LINENO
rm get-pip.py || display_error "Failed to remove get-pip.py" $LINENO

# Install the chosen web server
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling $web_server...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3

if [[ "$web_server" == "apache" ]]; then
    add-apt-repository -y ppa:ondrej/apache2 || display_error "Failed to add Apache2 repository" $LINENO    
    apt update && apt upgrade -y 
    apt install -y apache2 || display_error "Failed to install Apache2" $LINENO
    systemctl enable apache2 || display_error "Failed to enable Apache2" $LINENO
    apt install -y python3-certbot-apache certbot || display_error "Failed to install Certbot for Apache" $LINENO
    
    # Start Apache and check status
    systemctl start apache2 || display_error "Failed to start Apache2" $LINENO
    systemctl status apache2 || display_error "Apache service is not running at line $LINENO" $LINENO
    
elif [[ "$web_server" == "nginx" ]]; then
    add-apt-repository -y ppa:ondrej/nginx-mainline || display_error "Failed to add Nginx repository" $LINENO
    apt update && apt upgrade -y 
    apt install -y nginx || display_error "Failed to install Nginx" $LINENO
    systemctl enable --now nginx || display_error "Failed to enable Nginx" $LINENO
    apt install -y python3-certbot-nginx certbot || display_error "Failed to install Certbot for Nginx" $LINENO
    
    # Start Nginx and check status
    systemctl start nginx || display_error "Failed to start Nginx" $LINENO
    systemctl status nginx || display_error "Nginx service is not running at line $LINENO" $LINENO
else
    display_error "Invalid web server choice" $LINENO
fi

# Ensure the web server is running
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mChecking $web_server service...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
if ! systemctl is-active --quiet $web_server; then
    display_error "$web_server service is not running" $LINENO
fi

# Configure firewall
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mConfiguring firewall...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"

if [[ "$web_server" == "apache" ]]; then
    ufw allow in 80 || display_error "Failed to allow port 80" $LINENO
    ufw allow in 443 || display_error "Failed to allow port 443" $LINENO
else
    ufw allow 'Nginx Full' || display_error "Failed to allow Nginx Full profile" $LINENO
    ufw allow 9000 || display_error "Failed to allow port 9000" $LINENO
fi
ufw allow in 61208 || display_error "Failed to allow port 61208" $LINENO
ufw allow OpenSSH || display_error "Failed to allow OpenSSH" $LINENO
ufw allow 9001 || display_error "Failed to allow Supervisor" $LINENO
ufw allow 19999 || display_error "Failed to allow Netdata" $LINENO

# Install MySQL
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling MySQL...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
apt -y install mariadb-server mariadb-client || display_error "Failed to install MySQL" $LINENO

# Secure MariaDB installation
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mSecuring MariaDB installation...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
mysql_secure_installation <<EOF
Y
$mysql_root_password
$mysql_root_password
Y
Y
Y
Y
EOF

# Restart MariaDB service
systemctl restart mariadb || display_error "Failed to restart MariaDB" $LINENO
echo -e "\e[1;32mMariaDB has been successfully installed and secured.\e[0m"

# Install PHP and required modules
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling PHP $php_version + modules...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3
apt install -y php$php_version php$php_version-cli php$php_version-fpm php$php_version-mysql php$php_version-zip php$php_version-xml php$php_version-mbstring php$php_version-curl php$php_version-gd php$php_version-json php$php_version-common php$php_version-readline php$php_version-bcmath libapache2-mod-php$php_version || display_error "Failed to install PHP and modules" $LINENO
apt -y install php$php_version-{imagick,sqlite3,intl,redis,simplexml,tokenizer,dom,fileinfo,iconv,ctype,xmlrpc,soap,bz2,tidy} composer || display_error "Failed to install PHP  modules" $LINENO
update-alternatives --set php /usr/bin/php$php_version || display_error "Failed to set PHP version" $LINENO
update-alternatives --set phar /usr/bin/phar$php_version || display_error "Failed to set phar version" $LINENO
update-alternatives --set phar.phar /usr/bin/phar.phar$php_version || display_error "Failed to set phar.phar version" $LINENO

# Configure PHP-FPM for Apache
if [[ "$web_server" == "apache" ]]; then
    echo -e "\e[1;32m******************************************\e[0m"
    echo -e "\e[1;32mConfiguring PHP-FPM for Apache...\e[0m"
    echo -e "\e[1;32m******************************************\e[0m"
    a2enconf php$php_version-fpm || display_error "Failed to enable PHP-FPM configuration" $LINENO
    a2enmod proxy_fcgi setenvif || display_error "Failed to enable Apache modules" $LINENO
    systemctl restart apache2 || display_error "Failed to restart Apache2" $LINENO

fi

# Install and configure phpMyAdmin
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling phpMyAdmin...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 2
mkdir -p /var/www/html/$domain
chown -R $USER:$USER /var/www/html/$domain
chmod -R 755 /var/www
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/admin-pass password $mysql_root_password" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/app-pass password $mysql_root_password" | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect none" | debconf-set-selections
apt install -y phpmyadmin  || display_error "Failed to install phpMyAdmin" $LINENO
ln -s /usr/share/phpmyadmin /var/www/html/$domain/phpmyadmin || display_error "Failed to create symbolic link for phpMyAdmin" $LINENO

# Configure Apache or Nginx 
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mConfiguring $web_server ...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 2
if [[ "$web_server" == "apache" ]]; then
    echo -e "\e[1;32m******************************************\e[0m"
    echo -e "\e[1;32mConfiguring Apache2 virtual host...\e[0m"
    echo -e "\e[1;32m******************************************\e[0m"
    sleep 3
    # Downloadig Index File
    wget -P /var/www/html/$domain https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/ApacheIndex.php || display_error "Failed to download index.php" $LINENO
    mv /var/www/html/$domain/ApacheIndex.php /var/www/html/$domain/index.php
    sed -i "s/example.com/$domain/g" /var/www/html/$domain/index.php || display_error "Failed to replace domain in index.php" $LINENO
    systemctl restart apache2
    #
   cat <<EOF > /etc/apache2/sites-available/$domain.conf
<VirtualHost *:80>
    ServerAdmin webmaster@example.com
    DocumentRoot /var/www/html/$domain
    ServerName $domain
    ServerAlias www.$domain

    <Directory "/var/www/html/$domain">
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF
    a2enmod rewrite
    a2ensite $domain.conf
    systemctl restart apache2
else
    echo -e "\e[1;32m******************************************\e[0m"
    echo -e "\e[1;32mConfiguring Nginx virtual host...\e[0m"
    echo -e "\e[1;32m******************************************\e[0m"
    sleep 3
    # Downloadig Index File
    wget -P /var/www/html/$domain https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/nginxIndex.php || display_error "Failed to download index.php" $LINENO
    mv /var/www/html/$domain/nginxIndex.php /var/www/html/$domain/index.php
    sed -i "s/example.com/$domain/g" /var/www/html/$domain/index.php || display_error "Failed to replace domain in index.php" $LINENO
    # some configration for nginx
    mv /etc/nginx/snippets/fastcgi-php.conf /etc/nginx/snippets/back_fastcgi-php.conf
    wget -P /etc/nginx/snippets/ https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/fastcgi-php.conf || display_error "Failed to download FastCGI PHP configuration file" $LINENO
    mv /etc/nginx/nginx.conf /etc/nginx/Back_nginx.conf
    wget -P /etc/nginx/ https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/nginx.conf
    #
    cat <<EOF > /etc/nginx/sites-available/$domain
server {
    listen 80;

    server_name $domain;
    root /var/www/html/$domain;

    index index.html index.htm index.php;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
	
	# PHP-FPM Configuration Nginx
    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php/php$php_version-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME 
		$document_root$fastcgi_script_name;
        include snippets/fastcgi-php.conf;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
EOF
    ln -s /etc/nginx/sites-available/$domain /etc/nginx/sites-enabled/
    systemctl start nginx
    nginx -t && systemctl reload nginx || display_error "Failed to configure Nginx" $LINENO
    systemctl restart nginx
fi

service php$php_version-fpm reload

# Install Node.js
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling Node.js...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -  || display_error "Failed to setup Node.js repository" $LINENO
apt install -y nodejs || display_error "Failed to install Node.js" $LINENO
npm install pm2@latest -g || display_error "Failed to install PM2" $LINENO
pm2 startup systemd || display_error "Failed to configure PM2 startup" $LINENO
apt-get install -y gcc g++ make  || display_error "Failed to configure gcc" $LINENO

# Install Redis
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling Redis...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3
apt install -y redis-server || display_error "Failed to install Redis" $LINENO
#
apt update -y && apt upgrade -y
if [[ "$web_server" == "apache" ]]; then
    systemctl restart apache2
else
    systemctl restart nginx
fi
service php$php_version-fpm reload
# Install Netdata monitoring tool
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling Netdata monitoring tool...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3
bash <(curl -Ss https://my-netdata.io/kickstart.sh) --non-interactive || display_error "Failed to install Netdata" $LINENO
#
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling Supervisor and Glances...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3
apt install -y supervisor || display_error "Failed to install Supervisor" $LINENO
pip install glances[all] || display_error "Failed to install Glances plugins" $LINENO
wget -P /etc/systemd/system/ https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/glances.service || display_error "Failed to download Glances service file" $LINENO
systemctl enable  --now glances.service
systemctl start glances.service
systemctl restart glances.service
systemctl restart supervisor || display_error "Failed to restart Supervisor" $LINENO
systemctl enable supervisor || display_error "Failed to enable Supervisor" $LINENO
supervisorctl reload || display_error "Failed to reload Supervisor" $LINENO
supervisorctl restart all || display_error "Failed to restart all Supervisor programs" $LINENO

# Configure SSL with Let's Encrypt
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mConfiguring SSL with Let's Encrypt...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
if [[ "$web_server" == "apache" ]]; then
    certbot --apache --non-interactive --agree-tos --redirect --hsts --staple-ocsp --email $email -d $domain  || display_error "Failed to configure SSL with Let's Encrypt for Apache" $LINENO
else
    certbot --nginx --non-interactive --agree-tos --redirect --hsts --staple-ocsp --email $email -d $domain || display_error "Failed to configure SSL with Let's Encrypt for Nginx" $LINENO
fi
# Start UFW
ufw enable || display_error "Failed to enable UFW" $LINENO
ufw status || display_error "Failed to check UFW status" $LINENO

# Restart web server and PHP-FPM service
systemctl restart $web_server || display_error "Failed to restart $web_server service" $LINENO
systemctl restart php$php_version-fpm || display_error "Failed to restart PHP $php_version FPM service" $LINENO

# Set PHP version
if [[ "$web_server" == "apache" ]]; then
    a2enmod php$php_version
fi
update-alternatives --set php /usr/bin/php$php_version
if [[ "$web_server" == "apache" ]]; then
    systemctl restart apache2
else
    systemctl restart nginx
fi
service php$php_version-fpm reload

# Additional configuration scripts
wget https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/super-sdomain.sh
chmod +x super-sdomain.sh
#
apt update && apt upgrade -y
clear
echo -e "\e[1;35m=========================================\e[0m"
DISTRO=$(cat /etc/*-release | grep "^ID=" | grep -E -o "[a-z]\w+")
echo -e "\e[1;35mYour operating system is\e[0m" "$DISTRO"
echo -e "\e[1;35m=========================================\e[0m"
echo -e "\e[1;35mCurrent PHP version of this system:\e[0m" "$php_version" 
#
echo -e "\e[1;35m##################################\e[0m"
echo -e "\e[1;35mYou can thank me on:\e[0m"
echo -e "\e[1;35mhttps://twitter.com/ScarNaruto\e[0m"
echo -e "\e[1;35mJoin my Discord Server:\e[0m"
echo -e "\e[1;35mhttps://discord.snyt.xyz\e[0m"
echo -e "\e[1;35m##################################\e[0m"
echo -e "\e[1;35mYou can add a new domain to your server\e[0m"
echo -e "\e[1;35mby typing: ./super-sdomain.sh in the terminal\e[0m"
echo -e "\e[1;35m----------------------------------\e[0m"
echo -e "\e[1;35mphpMyAdmin Credentials:\e[0m"
echo -e "\e[1;35mUsername: root\e[0m"
echo -e "\e[1;35mPassword: $mysql_root_password\e[0m"
echo -e "\e[1;35m----------------------------------\e[0m"
echo -e "\e[1;35mCheck your web server by going to this link:\e[0m"
echo -e "\e[1;35mhttps://$domain\e[0m"
#
#rm SuperServer.sh
#
exit