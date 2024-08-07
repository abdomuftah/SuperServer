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
echo -e "\e[1;34m*              SNYT Add Domain            *\e[0m"
echo -e "\e[1;34m******************************************\e[0m"
echo -e "\e[1;34m*       Add New Domain to Your Server     *\e[0m"
echo -e "\e[1;34m*           with Let's Encrypt SSL        *\e[0m"
echo -e "\e[1;34m******************************************\e[0m"
echo ""

# Prompt user for domain
domain=$(get_user_input "Add Domain" "Set Web Domain (Example: example.com [No trailing slash!]): ")

# Validate domain format
if [[ ! $domain =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]; then
    display_error "Invalid domain format" $LINENO
fi

mkdir -p /var/www/html/$domain || display_error "Failed to create directory for domain" $LINENO

# Get PHP version
php_version=$(get_php_version)

# Call the appropriate script based on the web server
if [[ $web_server == "apache" ]]; then
    wget https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/apache_setup.sh || display_error "Failed to download Apache setup script" $LINENO
    ./apache_setup.sh "$domain" "$php_version" "$default_email"
elif [[ $web_server == "nginx" ]]; then
    wget https://raw.githubusercontent.com/abdomuftah/SuperServer/main/assets/nginx_setup.sh || display_error "Failed to download Nginx setup script" $LINENO
    ./nginx_setup.sh "$domain" "$php_version" "$default_email"
fi

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
