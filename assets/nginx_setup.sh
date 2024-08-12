#!/bin/bash

# Function to display errors
display_error() {
    echo "Error: $1 (Line: $2)"
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

# Function to determine PHP version
get_php_version() {
    php_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
    if [[ -z $php_version ]]; then
        display_error "Unable to determine PHP version" $LINENO
    fi
    echo $php_version
}

clear
echo ""
echo -e "\e[1;34m******************************************\e[0m"
echo -e "\e[1;34m*          SNYT Add Domain-nginx        *\e[0m"
echo -e "\e[1;34m******************************************\e[0m"
echo -e "\e[1;34m*       Add New Domain to Your Server     *\e[0m"
echo -e "\e[1;34m*           with Let's Encrypt SSL        *\e[0m"
echo -e "\e[1;34m******************************************\e[0m"
echo ""

# Prompt user for domain
read -p 'Set Web Domain (Example: 127.0.0.1 [Not trailing slash!]): ' domain

# Validate domain format
if [[ ! $domain =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]; then
    display_error "Invalid domain format" $LINENO
fi

# Downloading Index File
wget -P /var/www/html/$domain https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/nginxIndex.php || display_error "Failed to download index.php" $LINENO
mv /var/www/html/$domain/nginxIndex.php /var/www/html/$domain/index.php
sed -i "s/example.com/$domain/g" /var/www/html/$domain/index.php || display_error "Failed to replace domain in index.php" $LINENO

# Downloading conf file
wget -P /etc/nginx/sites-available https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/nginxExample.conf || display_error "Failed to download Nginx configuration file" $LINENO
mv /etc/nginx/sites-available/nginxExample.conf /etc/nginx/sites-available/$domain.conf
sed -i "s/example.com/$domain/g" /etc/nginx/sites-available/$domain.conf
sed -i "s/phpversion/$php_version/g" /etc/nginx/sites-available/$domain.conf
ln -s /etc/nginx/sites-available/$domain.conf /etc/nginx/sites-enabled/

# Start Nginx
nginx -t && systemctl reload nginx || display_error "Failed to configure Nginx" $LINENO
systemctl restart nginx

# Let's Encrypt SSL
certbot --noninteractive --agree-tos --no-eff-email --cert-name $domain --nginx --redirect -d $domain -m $default_email || display_error "Failed to install Let's Encrypt SSL" $LINENO
systemctl restart nginx.service || display_error "Failed to restart Nginx after Let's Encrypt SSL renewal" $LINENO

chown -R www-data:www-data /var/www/html/$domain/
chmod -R 755 /var/www/html/$domain/

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
