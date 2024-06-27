#!/bin/bash

# Function to display errors
display_error() {
    echo "Error on line $2: $1"
    exit 1
}

# Function to prompt user for input using dialog
get_user_input() {
    local title="$1"
    local prompt="$2"
    local input
    input=$(dialog --clear --backtitle "$title" --inputbox "$prompt" 8 60 2>&1 >/dev/tty)
    clear
    echo "$input"
}

clear
echo ""
echo -e "\e[1;34m******************************************\e[0m"
echo -e "\e[1;34m*            SNYT Add Domain               *\e[0m"
echo -e "\e[1;34m******************************************\e[0m"
echo -e "\e[1;34m*       Add New Domain To Server        *\e[0m"
echo -e "\e[1;34m*           with Lets Encrypt           *\e[0m"
echo -e "\e[1;34m******************************************\e[0m"
echo ""

# Prompt user for domain and email
domain=$(get_user_input "Add Domain" "Set Web Domain (Example: example.com [Not trailing slash!]): ")
email=$(get_user_input "Add Domain" "Email for Let's Encrypt SSL: ")

# Validate domain format
if [[ ! $domain =~ ^[a-zA-Z0-9.-]+$ ]]; then
    display_error "Invalid domain format" $LINENO
fi

# Validate email format
if [[ ! $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    display_error "Invalid email format" $LINENO
fi

# Check if the server is running Apache or Nginx
if systemctl is-active --quiet apache2; then
    web_server="apache"
elif systemctl is-active --quiet nginx; then
    web_server="nginx"
else
    display_error "Neither Apache nor Nginx is running." $LINENO
fi

mkdir -p /var/www/html/$domain || display_error "Failed to create directory for domain" $LINENO

if [[ $web_server == "apache" ]]; then
    # Apache specific configuration
    echo -e "\e[1;32m******************************************\e[0m"
    echo -e "\e[1;32mConfiguring apache2 virtual host...\e[0m"
    echo -e "\e[1;32m******************************************\e[0m"
    sleep 3
    # Downloading Index File
    wget -P /var/www/html/$domain https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/ApacheIndex.php || display_error "Failed to download index.php" $LINENO
    mv /var/www/html/$domain/ApacheIndex.php /var/www/html/$domain/index.php
    sed -i "s/example.com/$domain/g" /var/www/html/$domain/index.php || display_error "Failed to replace domain in index.php" $LINENO
    # Downloading conf file
    wget -P /etc/apache2/sites-available https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/ApacheExample.conf || display_error "Failed to download Apache2 configuration file" $LINENO
    mv /etc/apache2/sites-available/ApacheExample.conf /etc/apache2/sites-available/$domain.conf
    sed -i "s/example.com/$domain/g" /etc/apache2/sites-available/$domain.conf || display_error "Failed to replace domain in Apache configuration" $LINENO
    # Enable and restart
    a2ensite $domain.conf || display_error "Failed to enable site configuration" $LINENO
    systemctl restart apache2 || display_error "Failed to restart Apache" $LINENO
elif [[ $web_server == "nginx" ]]; then
    echo -e "\e[1;32m******************************************\e[0m"
    echo -e "\e[1;32mConfiguring Nginx virtual host...\e[0m"
    echo -e "\e[1;32m******************************************\e[0m"
    sleep 3
    # Downloading Index File
    wget -P /var/www/html/$domain https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/nginxIndex.php || display_error "Failed to download index.php" $LINENO
    mv /var/www/html/$domain/nginxIndex.php /var/www/html/$domain/index.php
    sed -i "s/example.com/$domain/g" /var/www/html/$domain/index.php || display_error "Failed to replace domain in index.php" $LINENO
    # Downloading conf file
    wget -P /etc/nginx/sites-available https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/nginxExample.conf || display_error "Failed to download Nginx configuration file" $LINENO
    mv /etc/nginx/sites-available/nginxExample.conf /etc/nginx/sites-available/$domain.conf
    sed -i "s/example.com/$domain/g" /etc/nginx/sites-available/$domain.conf || display_error "Failed to replace domain in Nginx configuration" $LINENO
    # Add PHP version placeholder
    php_version=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
    sed -i "s/phpversion/$php_version/g" /etc/nginx/sites-available/$domain.conf || display_error "Failed to replace PHP version in Nginx configuration" $LINENO
    ln -s /etc/nginx/sites-available/$domain.conf /etc/nginx/sites-enabled/ || display_error "Failed to create symbolic link for Nginx configuration" $LINENO
    # Start Nginx
    nginx -t && systemctl reload nginx || display_error "Failed to configure Nginx" $LINENO
    systemctl restart nginx || display_error "Failed to restart Nginx" $LINENO
fi

chown -R www-data:www-data /var/www/html/$domain/ || display_error "Failed to change ownership of domain directory" $LINENO
chmod -R 755 /var/www/html/$domain/ || display_error "Failed to change permissions of domain directory" $LINENO

if [[ $web_server == "apache" ]]; then
    certbot --noninteractive --agree-tos --no-eff-email --cert-name $domain --apache --redirect -d $domain -m $email || display_error "Failed to install Let's Encrypt SSL" $LINENO
    systemctl restart apache2.service || display_error "Failed to restart Apache after Let's Encrypt SSL renewal" $LINENO
elif [[ $web_server == "nginx" ]]; then
    certbot --noninteractive --agree-tos --no-eff-email --cert-name $domain --nginx --redirect -d $domain -m $email || display_error "Failed to install Let's Encrypt SSL" $LINENO
    systemctl restart nginx.service || display_error "Failed to restart Nginx after Let's Encrypt SSL renewal" $LINENO
fi

# Display success message
clear
echo -e "\e[1;35m##################################\e[0m"
echo -e "\e[1;35mYou can thank me on:\e[0m"
echo -e "\e[1;35mhttps://twitter.com/ScarNaruto\e[0m"
echo -e "\e[1;35mJoin my Discord Server:\e[0m"
echo -e "\e[1;35mhttps://discord.snyt.xyz\e[0m"
echo -e "\e[1;35m##################################\e[0m"
echo -e "\e[1;35m----------------------------------\e[0m"
echo -e "\e[1;35mCheck your web server by going to this link:\e[0m"
echo -e "\e[1;35mhttps://$domain\e[0m"
echo -e "\e[1;35m----------------------------------\e[0m"
exit
