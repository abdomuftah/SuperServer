#!/bin/bash

# Function to display error message and exit
display_error() {
    echo -e "\e[1;31mError: $1\e[0m"
    exit 1
}

# Function to prompt user for input and validate
get_user_input() {
    read -p "$1" input
    if [[ -z "$input" ]]; then
        display_error "Input cannot be empty"
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
echo -e "\e[1;34m******************************************\e[0m"
echo -e "\e[1;34m*      Ubuntu 22 LAMP Server Setup       *\e[0m"
echo -e "\e[1;34m******************************************\e[0m"
echo -e "\e[1;34m* This script will install a LAMP stack *\e[0m"
echo -e "\e[1;34m* with phpMyAdmin, Node.js, and secure  *\e[0m"
echo -e "\e[1;34m* your domain with Let's Encrypt SSL.   *\e[0m"
echo -e "\e[1;34m******************************************\e[0m"
echo ""

# Prompt user for domain, email, and MySQL root password
domain=$(get_user_input "Set Web Domain (Example: example.com): ")
email=$(get_user_input "Email for Let's Encrypt SSL: ")
mysql_root_password=$(get_user_input "Enter MySQL root password: ")

# Prompt user for PHP version using dialog
php_versions=("7.4" "" "8.0" "" "8.1" "" "8.2" "")
php_version=$(display_menu "LAMP Setup" "Choose PHP version" "${php_versions[@]}")
clear
# Prompt user to choose web server using dialog
web_servers=("apache" "" "nginx" "")
web_server=$(display_menu "LAMP Setup" "Choose web server" "${web_servers[@]}")
clear
# Update system packages
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mUpdating system packages...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3
apt update && apt upgrade -y || display_error "Failed to update system packages"
apt autoremove -y

# Install required packages and repositories
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling required packages and repositories...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3
apt-get install -y default-jdk software-properties-common dialog || display_error "Failed to install packages"
add-apt-repository -y ppa:ondrej/php || display_error "Failed to add PHP repository"
if [[ "$web_server" == "apache" ]]; then
    add-apt-repository -y ppa:ondrej/apache2 || display_error "Failed to add Apache2 repository"
else
    add-apt-repository ppa:ondrej/nginx-mainline -y || display_error "Failed to add Nginx repository"
fi
add-apt-repository -y ppa:phpmyadmin/ppa || display_error "Failed to add phpMyAdmin repository"
add-apt-repository -y ppa:deadsnakes/ppa || display_error "Failed to add deadsnakes repository"
add-apt-repository -y ppa:redislabs/redis || display_error "Failed to add Redis repository"
apt update && apt upgrade -y

# Install additional tools
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling additional tools...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3
apt install -y screen nano curl git zip unzip ufw certbot tar redis-server sed composer || display_error "Failed to install additional tools"
if [[ "$web_server" == "apache" ]]; then
    apt install -y python3-certbot-apache || display_error "Failed to install Certbot for Apache"
else
    apt install -y python3-certbot-nginx || display_error "Failed to install Certbot for Nginx"
fi
apt install -y python3.11 libmysqlclient-dev python3-dev python3-pip
ln -s /usr/bin/python3.11 /usr/bin/python
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py && python3 get-pip.py || display_error "Failed to install Python pip"
python3 -m pip install Django
rm get-pip.py

# Install the chosen web server
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling $web_server...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3
if [[ "$web_server" == "apache" ]]; then
    apt install -y apache2 || display_error "Failed to install Apache2"
    systemctl enable apache2
else
    apt install -y nginx || display_error "Failed to install Nginx"
    systemctl enable --now nginx
fi

# Ensure the web server is running
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mChecking $web_server service...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
if ! systemctl is-active --quiet $web_server; then
    display_error "$web_server service is not running"
fi

# Configure firewall
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mConfiguring firewall...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"

if [[ "$web_server" == "apache" ]]; then
    ufw allow in 80
    ufw allow in 443
else
    ufw allow 'Nginx Full'
    ufw allow 9000
fi
ufw allow in 61208
ufw allow OpenSSH

# Install MySQL
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling MySQL...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
apt -y install mariadb-server mariadb-client || display_error "Failed to install MySQL"

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
systemctl restart mariadb || display_error "Failed to restart MariaDB"
echo -e "\e[1;32mMariaDB has been successfully installed and secured.\e[0m"

# Install PHP and required modules
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling PHP $php_version + modules...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3
apt -y install php$php_version php$php_version-{curl,imagick,common,cli,mysql,sqlite3,intl,gd,mbstring,fpm,xml,redis,zip,bcmath,simplexml,tokenizer,dom,fileinfo,iconv,ctype,xmlrpc,soap,bz2,tidy} || display_error "Failed to install PHP"
systemctl enable --now php$php_version-fpm || display_error "Failed to enable PHP $php_version FPM service"

# Install phpMyAdmin
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling phpMyAdmin...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 2
mkdir -p /var/www/html/$domain
chown -R $USER:$USER /var/www/html/$domain
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/admin-pass password $mysql_root_password" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/app-pass password $mysql_root_password" | debconf-set-selections
echo "phpmyadmin phpmyadmin/app-password-confirm password $mysql_root_password" | debconf-set-selections
#
apt -y install phpmyadmin || display_error "Failed to install phpMyAdmin"
ln -s /usr/share/phpmyadmin /var/www/html/$domain/phpmyadmin || display_error "Failed to create symbolic link for phpMyAdmin"


# Configure PHP
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mConfiguring PHP...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
wget https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/php.ini || display_error "Failed to download PHP configuration file"

if [[ "$web_server" == "apache" ]]; then
    cp -f php.ini /etc/php/$php_version/apache2/ || display_error "Failed to copy PHP configuration file to CLI directory apache2"
    mv -f php.ini /etc/php/$php_version/fpm/ || display_error "Failed to move PHP configuration file to FPM directory apache2"
    systemctl restart apache2
else
    cp -f php.ini /etc/php/$php_version/cli/ || display_error "Failed to copy PHP configuration file to CLI directory Nginx"
    mv -f php.ini /etc/php/$php_version/fpm/ || display_error "Failed to move PHP configuration file to FPM directory Nginx"
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

# Configure virtual host based on web server choice
if [[ "$web_server" == "apache" ]]; then
    echo -e "\e[1;32m******************************************\e[0m"
    echo -e "\e[1;32mConfiguring Apache2 virtual host...\e[0m"
    echo -e "\e[1;32m******************************************\e[0m"
    sleep 3
    # Downloadig Index File
    wget -P /var/www/html/$domain https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/ApacheIndex.php || display_error "Failed to download index.php"
    mv /var/www/html/$domain/ApacheIndex.php /var/www/html/$domain/index.php
    sed -i "s/example.com/$domain/g" /var/www/html/$domain/index.php || display_error "Failed to replace domain in index.php"
    # Downloadning conf file
    wget -P /etc/apache2/sites-available https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/ApacheExample.conf || display_error "Failed to download Apache2 configuration file"
    mv /etc/apache2/sites-available/ApacheExample.conf /etc/apache2/sites-available/$domain.conf
    sed -i "s/example.com/$domain/g" /etc/apache2/sites-available/$domain.conf
    # enable and restart
    a2ensite $domain
    systemctl restart apache2
else
    echo -e "\e[1;32m******************************************\e[0m"
    echo -e "\e[1;32mConfiguring Nginx virtual host...\e[0m"
    echo -e "\e[1;32m******************************************\e[0m"
    sleep 3
    # Downloadig Index File
    wget -P /var/www/html/$domain https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/nginxIndex.php || display_error "Failed to download index.php"
    mv /var/www/html/$domain/nginxIndex.php /var/www/html/$domain/index.php
    sed -i "s/example.com/$domain/g" /var/www/html/$domain/index.php || display_error "Failed to replace domain in index.php"
    # Downloadning conf file
    wget -P /etc/nginx/sites-available https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/nginxExample.conf || display_error "Failed to download Nginx configuration file"
    mv /etc/nginx/sites-available/nginxExample.conf /etc/nginx/sites-available/$domain.conf
    sed -i "s/example.com/$domain/g" /etc/nginx/sites-available/$domain.conf
    sed -i "s/phpversion/$php_version/g" /etc/nginx/sites-available/$domain.conf
    ln -s /etc/nginx/sites-available/$domain.conf /etc/nginx/sites-enabled/
    # some configration for nginx
    mv /etc/nginx/snippets/fastcgi-php.conf /etc/nginx/snippets/back_fastcgi-php.conf
    wget -P /etc/nginx/snippets/ https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/fastcgi-php.conf || display_error "Failed to download FastCGI PHP configuration file"
    mv /etc/nginx/nginx.conf /etc/nginx/Back_nginx.conf
    wget -P /etc/nginx/ https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/nginx.conf
    # Start Nginx
    systemctl start nginx
    systemctl restart nginx
fi
    service php$php_version-fpm reload

# Install Node.js
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling Node.js...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3
apt-get install -y gcc g++ make nodejs npm || display_error "Failed to install Node.js"
apt update -y && apt upgrade -y
if [[ "$web_server" == "apache" ]]; then
    systemctl restart apache2
else
    systemctl restart nginx
fi
service php$php_version-fpm reload

# Install Let's Encrypt SSL
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling Let's Encrypt SSL...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3
if [[ "$web_server" == "apache" ]]; then
    certbot --noninteractive --agree-tos --no-eff-email --cert-name $domain --apache --redirect -d $domain -m $email || display_error "Failed to install Let's Encrypt SSL"
else
    certbot --noninteractive --agree-tos --no-eff-email --cert-name $domain --nginx --redirect -d $domain -m $email || display_error "Failed to install Let's Encrypt SSL"
fi
certbot renew --dry-run
if [[ "$web_server" == "apache" ]]; then
    systemctl restart apache2
else
    systemctl restart nginx
fi

# Install glances
echo -e "\e[1;32m******************************************\e[0m"
echo -e "\e[1;32mInstalling Glances...\e[0m"
echo -e "\e[1;32m******************************************\e[0m"
sleep 3
pip3 install glances[all] || display_error "Failed to install Glances"
wget -P /etc/systemd/system/ https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/glances.service || display_error "Failed to download Glances service file"
systemctl enable  --now glances.service
systemctl start glances.service
systemctl restart glances.service
echo -e "\e[1;32mglances has been successfully installed.\e[0m"
sleep 3

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

# Final messages
apt update && apt upgrade -y
clear
echo -e "\e[1;35m=========================================\e[0m"
DISTRO=$(cat /etc/*-release | grep "^ID=" | grep -E -o "[a-z]\w+")
echo -e "\e[1;35mYour operating system is\e[0m" "$DISTRO"
echo -e "\e[1;35m=========================================\e[0m"
CURRENT=$(php -v | head -n 1 | cut -d " " -f 2 | cut -f1-2 -d".")
echo -e "\e[1;35mCurrent PHP version of this system:\e[0m" "PHP-$CURRENT" 
#
echo -e "\e[1;35m##################################\e[0m"
echo -e "\e[1;35mYou can thank me on:\e[0m"
echo -e "\e[1;35mhttps://twitter.com/ScarNaruto\e[0m"
echo -e "\e[1;35mJoin my Discord Server:\e[0m"
echo -e "\e[1;35mhttps://discord.snyt.xyz\e[0m"
echo -e "\e[1;35m##################################\e[0m"
echo -e "\e[1;35mYou can add a new domain to your server\e[0m"
echo -e "\e[1;35mby typing: ./sdomain.sh in the terminal\e[0m"
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
