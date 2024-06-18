#!/bin/bash

# Function to display errors
display_error() {
    echo "Error: $1"
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
echo -e "\e[1;34m*        Scar Naruto Add Domain           *\e[0m"
echo -e "\e[1;34m******************************************\e[0m"
echo -e "\e[1;34m*       Add New Domain To Server        *\e[0m"
echo -e "\e[1;34m*           with Lets Encrypt           *\e[0m"
echo -e "\e[1;34m******************************************\e[0m"
echo ""

# Prompt user for domain and email
domain=$(get_user_input "Add Domain" "Set Web Domain (Example: example.com [Not trailing slash!]): ")
email=$(get_user_input "Add Domain" "Email for Let's Encrypt SSL: ")

# Generate random password for phpMyAdmin
phpmyadmin_password=$(openssl rand -base64 12)

# Validate domain format
if [[ ! $domain =~ ^[a-zA-Z0-9.-]+$ ]]; then
    display_error "Invalid domain format"
fi

# Validate email format
if [[ ! $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    display_error "Invalid email format"
fi

# Check if the server is running Apache or Nginx
if systemctl is-active --quiet apache2; then
    web_server="apache"
elif systemctl is-active --quiet nginx; then
    web_server="nginx"
else
    display_error "Neither Apache nor Nginx is running."
fi

mkdir -p /var/www/html/$domain || display_error "Failed to create directory for domain"

if [[ $web_server == "apache" ]]; then
    # Apache specific configuration

    # Download Apache virtual host configuration template
    wget -P /etc/apache2/sites-available https://raw.githubusercontent.com/abdomuftah/LAMP-Plus/main/assets/Example.conf || display_error "Failed to download virtual host configuration template"
    mv /etc/apache2/sites-available/Example.conf /etc/apache2/sites-available/$domain.conf || display_error "Failed to move virtual host configuration template"

    # Replace placeholder with domain in Apache virtual host configuration
    sed -i "s/example.com/$domain/g" /etc/apache2/sites-available/$domain.conf || display_error "Failed to replace domain in virtual host configuration template"

    a2ensite $domain || display_error "Failed to enable site configuration"
    systemctl restart apache2 || display_error "Failed to restart Apache"

elif [[ $web_server == "nginx" ]]; then
    # Nginx specific configuration

    # Download Nginx server block configuration template
    wget -P /etc/nginx/sites-available https://raw.githubusercontent.com/abdomuftah/LAMP-Plus/main/assets/Example_nginx.conf || display_error "Failed to download server block configuration template"
    mv /etc/nginx/sites-available/Example_nginx.conf /etc/nginx/sites-available/$domain.conf || display_error "Failed to move server block configuration template"

    # Replace placeholder with domain in Nginx server block configuration
    sed -i "s/example.com/$domain/g" /etc/nginx/sites-available/$domain.conf || display_error "Failed to replace domain in server block configuration template"

    ln -s /etc/nginx/sites-available/$domain.conf /etc/nginx/sites-enabled/ || display_error "Failed to enable site configuration"
    systemctl restart nginx || display_error "Failed to restart Nginx"

fi

# Download index.php template
wget -P /var/www/html/$domain https://raw.githubusercontent.com/abdomuftah/LAMP-Plus/main/assets/index.php || display_error "Failed to download index.php template"
sed -i "s/example.com/$domain/g" /var/www/html/$domain/index.php || display_error "Failed to replace domain in index.php template"

chown -R www-data:www-data /var/www/html/$domain/
chmod -R 755 /var/www/html/$domain/

if [[ $web_server == "apache" ]]; then
    certbot --noninteractive --agree-tos --no-eff-email --cert-name $domain --apache --redirect -d $domain -m $email || display_error "Failed to install Let's Encrypt SSL"
    systemctl restart apache2.service || display_error "Failed to restart Apache after Let's Encrypt SSL renewal"
elif [[ $web_server == "nginx" ]]; then
    certbot --noninteractive --agree-tos --no-eff-email --cert-name $domain --nginx --redirect -d $domain -m $email || display_error "Failed to install Let's Encrypt SSL"
    systemctl restart nginx.service || display_error "Failed to restart Nginx after Let's Encrypt SSL renewal"
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
