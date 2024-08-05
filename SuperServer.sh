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

# Clear the screen
clear

# Display header
echo ""
echo -e "\e[1;34m**********************************************\e[0m"
echo -e "\e[1;34m*         SNYT Super Server Setup          *\e[0m"
echo -e "\e[1;34m**********************************************\e[0m"
echo -e "\e[1;34m* This script will install a Webservice stack *\e[0m"
echo -e "\e[1;34m*               apache2 Or Nginx              *\e[0m"
echo -e "\e[1;34m*    with phpMyAdmin, Node.js, and secure     *\e[0m"
echo -e "\e[1;34m*    your domain with Let's Encrypt SSL.      *\e[0m"
echo -e "\e[1;34m**********************************************\e[0m"
echo ""

# Prompt user for domain, email, and MySQL root password
domain=$(get_user_input "Set Web Domain (Example: example.com): ")
email=$(get_user_input "Email for Let's Encrypt SSL: ")
mysql_root_password=$(get_user_input "Enter MySQL root password: ")

# Prompt user to choose web server
echo "Choose web server:"
options=("apache" "nginx")
select opt in "${options[@]}"
do
    case $opt in
        "apache")
            web_server="apache"
            break
            ;;
        "nginx")
            web_server="nginx"
            break
            ;;
        *) echo "Invalid option";;
    esac
done

# Prompt user for PHP version
echo "Choose PHP version:"
php_versions=("7.4" "8.0" "8.1" "8.2")
select version in "${php_versions[@]}"
do
    case $version in
        "7.4"|"8.0"|"8.1"|"8.2")
            php_version=$version
            break
            ;;
        *) echo "Invalid option";;
    esac
done

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
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py && python3 get-pip.py --break-system-packages || display_error "Failed to install Python pip" $LINENO
python3 -m pip install Django --break-system-packages || display_error "Failed to install Django" $LINENO
rm get-pip.py || display_error "Failed to remove get-pip.py" $LINENO

# Install the chosen web server
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling $web_server...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3

if [[ "$web_server" == "apache" ]]; then
    add-apt-repository -y ppa:ondrej/apache2 || display_error "Failed to add apache2 repository" $LINENO    
    apt update && apt upgrade -y 
    apt install -y apache2 || display_error "Failed to install apache2" $LINENO
    systemctl enable apache2 || display_error "Failed to enable apache2" $LINENO
    apt install -y python3-certbot-apache certbot || display_error "Failed to install Certbot for apache" $LINENO
    
    # Start apache
    systemctl start apache2 || display_error "Failed to start apache2" $LINENO
    
elif [[ "$web_server" == "nginx" ]]; then
    add-apt-repository -y ppa:ondrej/nginx-mainline || display_error "Failed to add Nginx repository" $LINENO
    apt update && apt upgrade -y 
    apt install -y nginx || display_error "Failed to install Nginx" $LINENO
    systemctl enable --now nginx || display_error "Failed to enable Nginx" $LINENO
    apt install -y python3-certbot-nginx certbot || display_error "Failed to install Certbot for Nginx" $LINENO
    
    # Start Nginx 
    systemctl start nginx || display_error "Failed to start Nginx" $LINENO
else
    display_error "Invalid web server choice" $LINENO
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
apt install -y php$php_version php$php_version-common php$php_version-cli php$php_version-sqlite3 php$php_version-fpm php$php_version-redis php$php_version-mysql php$php_version-simplexml php$php_version-xml php$php_version-curl php$php_version-zip php$php_version-mbstring php$php_version-bcmath php$php_version-soap php$php_version-intl php$php_version-readline php$php_version-gd php$php_version-tokenizer php$php_version-dom php$php_version-fileinfo php$php_version-iconv php$php_version-ctype php$php_version-xmlrpc php$php_version-soap php$php_version-bz2 php$php_version-tidy php$php_version-imagick || display_error "Failed to install PHP and extensions" $LINENO
update-alternatives --set php /usr/bin/php$php_version || display_error "Failed to set PHP version" $LINENO
update-alternatives --set phar /usr/bin/phar$php_version || display_error "Failed to set phar version" $LINENO
update-alternatives --set phar.phar /usr/bin/phar.phar$php_version || display_error "Failed to set phar.phar version" $LINENO
systemctl enable --now php$php_version-fpm || display_error "Failed to enable PHP $php_version FPM service"

# Configure PHP-FPM for apache
if [[ "$web_server" == "apache" ]]; then
    echo -e "\e[1;32m******************************************\e[0m"
    echo -e "\e[1;32mConfiguring PHP-FPM for apache...\e[0m"
    echo -e "\e[1;32m******************************************\e[0m"
    a2enconf php$php_version-fpm || display_error "Failed to enable PHP-FPM configuration" $LINENO
    a2enmod proxy_fcgi setenvif || display_error "Failed to enable apache modules" $LINENO
    systemctl restart apache2 || display_error "Failed to restart apache2" $LINENO

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
# installing phpMyAdmin
apt install -y phpmyadmin  || display_error "Failed to install phpMyAdmin" $LINENO
ln -s /usr/share/phpmyadmin /var/www/html/$domain/phpmyadmin || display_error "Failed to create symbolic link for phpMyAdmin" $LINENO

# Configure PHP
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mConfiguring PHP...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
wget https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/php.ini || display_error "Failed to download PHP configuration file" $LINENO
#
cp -f php.ini /etc/php/$php_version/cli/ || display_error "Failed to copy PHP configuration file to CLI directory Nginx" $LINENO
mv -f php.ini /etc/php/$php_version/fpm/ || display_error "Failed to move PHP configuration file to FPM directory Nginx" $LINENO
if [[ "$web_server" == "apache" ]]; then
    systemctl restart apache2
else
    systemctl restart nginx
fi
service php$php_version-fpm reload

# Reset MySQL root password if needed
mysql -u root <<MYSQL_SCRIPT
ALTER USER 'root'@'localhost' IDENTIFIED BY '$mysql_root_password';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# Restart MariaDB service
systemctl restart mariadb || display_error "Failed to restart MariaDB"
echo -e "\e[1;32mMariaDB has been successfully installed and secured.\e[0m"

# Configure apache or Nginx 
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mConfiguring $web_server ...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 2
if [[ "$web_server" == "apache" ]]; then
    echo -e "\e[1;32m******************************************\e[0m"
    echo -e "\e[1;32mConfiguring apache2 virtual host...\e[0m"
    echo -e "\e[1;32m******************************************\e[0m"
    sleep 3
    # Downloadig Index File
    wget -P /var/www/html/$domain https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/ApacheIndex.php || display_error "Failed to download index.php" $LINENO
    mv /var/www/html/$domain/ApacheIndex.php /var/www/html/$domain/index.php
    sed -i "s/example.com/$domain/g" /var/www/html/$domain/index.php || display_error "Failed to replace domain in index.php" $LINENO
    # Downloadning conf file
    wget -P /etc/apache2/sites-available https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/ApacheExample.conf || display_error "Failed to download Apache2 configuration file"
    mv /etc/apache2/sites-available/ApacheExample.conf /etc/apache2/sites-available/$domain.conf
    sed -i "s/example.com/$domain/g" /etc/apache2/sites-available/$domain.conf
    # enable and restart
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
    # Downloadning conf file
    wget -P /etc/nginx/sites-available https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/nginxExample.conf || display_error "Failed to download Nginx configuration file"
    mv /etc/nginx/sites-available/nginxExample.conf /etc/nginx/sites-available/$domain.conf
    sed -i "s/example.com/$domain/g" /etc/nginx/sites-available/$domain.conf
    sed -i "s/phpversion/$php_version/g" /etc/nginx/sites-available/$domain.conf
    ln -s /etc/nginx/sites-available/$domain.conf /etc/nginx/sites-enabled/
    # some configration for nginx
    mv /etc/nginx/snippets/fastcgi-php.conf /etc/nginx/snippets/back_fastcgi-php.conf
    wget -P /etc/nginx/snippets/ https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/fastcgi-php.conf || display_error "Failed to download FastCGI PHP configuration file" $LINENO
    mv /etc/nginx/nginx.conf /etc/nginx/Back_nginx.conf
    wget -P /etc/nginx/ https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/nginx.conf
    # Start Nginx
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
apt-get install -y gcc g++ make composer || display_error "Failed to configure gcc" $LINENO
# 
apt update -y && apt upgrade -y
if [[ "$web_server" == "apache" ]]; then
    systemctl restart apache2
else
    systemctl restart nginx
fi
service php$php_version-fpm reload
# Install Redis
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling Redis...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3
apt install -y redis-server || display_error "Failed to install Redis" $LINENO
systemctl enable --now redis-server || display_error "Failed to enable Redis" $LINENO
systemctl start redis-server || display_error "Failed to start Redis" $LINENO
systemctl status redis-server || display_error "Redis service is not running at line $LINENO" $LINENO
#
# Enable UFW
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mEnabling UFW...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3
ufw enable || display_error "Failed to enable UFW" $LINENO
ufw reload || display_error "Failed to reload UFW" $LINENO
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
wget -O /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh && sh /tmp/netdata-kickstart.sh --non-interactive || display_error "Failed to install Netdata" $LINENO
systemctl enable --now netdata || display_error "Failed to enable netdata" $LINENO
systemctl restart netdata || display_error "Failed to restart netdata" $LINENO
#
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling Glances...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3
pip3 install glances[all] --break-system-packages || display_error "Failed to install Glances plugins" $LINENO
wget -P /etc/systemd/system/ https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/glances.service || display_error "Failed to download Glances service file" $LINENO
# Enable / start / restart Glances
systemctl enable --now glances.service || display_error "Failed to enable glances" $LINENO
systemctl start glances.service || display_error "Failed to start glances" $LINENO
systemctl restart glances.service || display_error "Failed to restart glances" $LINENO

# Configure SSL with Let's Encrypt
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mConfiguring SSL with Let's Encrypt...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
if [[ "$web_server" == "apache" ]]; then
    certbot --apache --non-interactive --agree-tos --redirect --hsts --staple-ocsp --email $email -d $domain  || display_error "Failed to configure SSL with Let's Encrypt for apache" $LINENO
else
    certbot --nginx --non-interactive --agree-tos --redirect --hsts --staple-ocsp --email $email -d $domain || display_error "Failed to configure SSL with Let's Encrypt for Nginx" $LINENO
fi

# Start UFW
ufw status || display_error "Failed to check UFW status" $LINENO

# Set PHP version
if [[ "$web_server" == "apache" ]]; then
    a2enmod php$php_version
fi
update-alternatives --set php /usr/bin/php$php_version
if [[ "$web_server" == "apache" ]]; then
    systemctl restart apache2 || display_error "Failed to restart $web_server service" $LINENO
else
    # Install nginx-ui
    echo -e "\e[1;32m******************************************\e[0m"
    echo -e "\e[1;32mInstalling nginx-ui...\e[0m"
    echo -e "\e[1;32m******************************************\e[0m"
    sleep 3
    
    bash <(curl -L -s https://raw.githubusercontent.com/0xJacky/nginx-ui/master/install.sh) install
    # Restart nginx
    systemctl restart nginx || display_error "Failed to restart $web_server service" $LINENO
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
rm SuperServer.sh
#
exit
