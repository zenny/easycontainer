#!/bin/bash

# EasyContainer update script.
# This script is designed to install latest EasyContainer or
# to update current EasyContainer.

# Checking permissions
if [[ $EUID -ne 0 ]]; then
    ee_lib_echo_fail "Sudo privilege required..."
    ee_lib_echo_fail "Uses: wget -qO ec https://github.com/ingobaab/easycontainer/ec && sudo bash ec"
    exit 100
fi

# Define echo function
# Blue color
function ee_lib_echo()
{
    echo $(tput setaf 4)$@$(tput sgr0)
}
# White color
function ee_lib_echo_info()
{
    echo $(tput setaf 7)$@$(tput sgr0)
}
# Red color
function ee_lib_echo_fail()
{
    echo $(tput setaf 1)$@$(tput sgr0)
}

# Capture errors
function ee_lib_error()
{
    echo "[ `date` ] $(tput setaf 1)$@$(tput sgr0)"
    exit $2
}

# Execute: apt-get update
ee_lib_echo "Executing apt-get update, please wait..."
apt-get update &>> /dev/null

# Checking lsb_release package
if [ ! -x /usr/bin/lsb_release ]; then
    ee_lib_echo "Installing lsb-release, please wait..."
    apt-get -y install lsb-release &>> /dev/null
fi

# Define variables for later use
ee_branch=$1
readonly ec_version_old="-.-.-"
readonly ec_version_new="0.0.1"
readonly ec_log_dir=/var/log/ec/
readonly ec_install_log=/var/log/ec/install.log
readonly ec_linux_distro=$(lsb_release -i | awk '{print $3}')
readonly ec_distro_version=$(lsb_release -sc)

# Checking linux distro
if [ "$ee_linux_distro" != "Ubuntu" ] && [ "$ee_linux_distro" != "Debian" ]; then
    ee_lib_echo_fail "EasyContainer (ec) is made for Ubuntu and Debian only as of now"
    ee_lib_echo_fail "You are free to fork EasyContainer (ec): https://github.com/ingobaab/easycontqainer/fork"
    ee_lib_echo_fail "EasyContainer (ec) only support Ubuntu 16.04 and maybe (untested!) Debian 7.x/8.x"
    exit 100
fi

# EasyContainer (ec) only support all Ubuntu/Debian distro except the distro reached EOL
lsb_release -d | egrep -e "16.04|xenial" &>> /dev/null
if [ "$?" -ne "0" ]; then
    ee_lib_echo_fail "EasyContainer (ec) only support Ubuntu 16.04"
#   ee_lib_echo_fail "Try to install on $(lsb_release -d) anyhow.."
    exit 100
fi

# Pre checks to avoid later screw ups
# Checking EasyContainer (ec) log directory
if [ ! -d $ee_log_dir ]; then

    ee_lib_echo "Creating EasyContainer log directory, please wait..."
    mkdir -p $ee_log_dir || ee_lib_error "Unable to create log directory $ee_log_dir, exit status " $?

    # Create EasyContainer log files
    touch /var/log/ee/{ee.log,install.log}

    # Keep EasyContainer log folder accessible to root only
    chmod -R 700 /var/log/ee || ee_lib_error "Unable to change permissions for EasyContainer log folder, exit status " $?
fi

# Install Python3, Git, Tar and python-software-properties required packages
# Generate Locale
function ee_install_dep()
{
    ee_lib_echo "Installing required packages, please wait..."
    if [ "$ee_linux_distro" == "Ubuntu" ]; then
        apt-get -y install gcc curl gzip python3 python3-apt python3-setuptools python3-dev sqlite3 git tar python-software-properties software-properties-common || ee_lib_error "Unable to install pre depedencies, exit status " 1
    elif [ "$ee_linux_distro" == "Debian" ]; then
        apt-get -y install gcc curl gzip python3 python3-apt python3-setuptools python3-dev sqlite3 git tar python-software-properties || ee_lib_error "Unable to pre depedencies, exit status " 1
    fi

    # Generating Locale
    locale-gen en &>> /dev/null
}

# Sqlite query to create table `sites` into ee.db
# which will be used by EasyContainer 3.x
function ee_sync_db()
{
    if [ ! -f /var/lib/ee/ee.db ]; then
        mkdir -p /var/lib/ee

        echo "CREATE TABLE sites (
           id INTEGER PRIMARY KEY     AUTOINCREMENT,
           sitename UNIQUE,
           site_type CHAR,
           cache_type CHAR,
           site_path  CHAR,
           created_on TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
           is_enabled INT,
           is_ssl INT,
           storage_fs CHAR,
           storage_db CHAR,
           db_name VARCHAR,
           db_user VARCHAR,
           db_password VARCHAR,
           db_host VARCHAR,
           is_hhvm INT INT DEFAULT '0',
           is_pagespeed INT INT DEFAULT '0'
        );" | sqlite3 /var/lib/ee/ee.db

        # Check site is enable/live or disable
        for site in $(ls /etc/nginx/sites-available/ | grep -v default);
        do
        if [ -f /etc/nginx/sites-enabled/$site ]; then
            ee_site_status='1'
        else
            ee_site_status='0'
        fi

        # Find out information about current NGINX configuration
        ee_site_current_type=$(head -n1 /etc/nginx/sites-available/$site | grep "NGINX CONFIGURATION" | rev | cut -d' ' -f3,4,5,6,7 | rev | cut -d ' ' -f2,3,4,5)

        # Detect current website type and cache
        if [ "$ee_site_current_type" = "HTML" ]; then
            ee_site_current="html"
            ee_site_current_cache="basic"
        elif [ "$ee_site_current_type" = "PHP" ]; then
            ee_site_current="php"
            ee_site_current_cache="basic"
        elif [ "$ee_site_current_type" = "MYSQL" ]; then
            ee_site_current="mysql"
            ee_site_current_cache="basic"
        # Single WordPress
        elif [ "$ee_site_current_type" = "WPSINGLE BASIC" ]; then
            ee_site_current="wp"
            ee_site_current_cache="basic"

        elif [ "$ee_site_current_type" = "WPSINGLE WP SUPER CACHE" ]; then
            ee_site_current="wp"
            ee_site_current_cache="wpsc"

        elif [ "$ee_site_current_type" = "WPSINGLE W3 TOTAL CACHE" ]; then
            ee_site_current="wp"
            ee_site_current_cache="w3tc"

        elif [ "$ee_site_current_type" = "WPSINGLE FAST CGI" ] || [ "$ee_site_current_type" = "WPSINGLE FASTCGI" ]; then
            ee_site_current="wp"
            ee_site_current_cache="wpfc"

        # WordPress subdirectory
        elif [ "$ee_site_current_type" = "WPSUBDIR BASIC" ]; then
            ee_site_current="wpsubdir"
            ee_site_current_cache="basic"

        elif [ "$ee_site_current_type" = "WPSUBDIR WP SUPER CACHE" ]; then
            ee_site_current="wpsubdir"
            ee_site_current_cache="wpsc"

        elif [ "$ee_site_current_type" = "WPSUBDIR W3 TOTAL CACHE" ]; then
            ee_site_current="wpsubdir"
            ee_site_current_cache="w3tc"

        elif [ "$ee_site_current_type" = "WPSUBDIR FAST CGI" ] || [ "$ee_site_current_type" = "WPSUBDIR FASTCGI" ]; then
            ee_site_current="wpsubdir"
            ee_site_current_cache="wpfc"

        # WordPress subdomain
        elif [ "$ee_site_current_type" = "WPSUBDOMAIN BASIC" ]; then
            ee_site_current="wpsubdomain"
            ee_site_current_cache="basic"

        elif [ "$ee_site_current_type" = "WPSUBDOMAIN WP SUPER CACHE" ]; then
            ee_site_current="wpsubdomain"
            ee_site_current_cache="wpsc"

        elif [ "$ee_site_current_type" = "WPSUBDOMAIN W3 TOTAL CACHE" ]; then
            ee_site_current="wpsubdomain"
            ee_site_current_cache="w3tc"

        elif [ "$ee_site_current_type" = "WPSUBDOMAIN FAST CGI" ] || [ "$ee_site_current_type" = "WPSUBDOMAIN FASTCGI" ]; then
            ee_site_current="wpsubdomain"
            ee_site_current_cache="wpfc"
        fi

        ee_webroot="/var/www/$site"

        # Insert query to insert old site information into ee.db
        echo "INSERT INTO sites (sitename, site_type, cache_type, site_path, is_enabled, is_ssl, storage_fs, storage_db)
        VALUES (\"$site\", \"$ee_site_current\", \"$ee_site_current_cache\", \"$ee_webroot\", \"$ee_site_status\", 0, 'ext4', 'mysql');" | sqlite3 /var/lib/ee/ee.db

        done
    else
        ee_lib_echo "Updating EasyContainer Database"
        echo "ALTER TABLE sites ADD COLUMN db_name varchar;" | sqlite3 /var/lib/ee/ee.db
        echo "ALTER TABLE sites ADD COLUMN db_user varchar; " | sqlite3 /var/lib/ee/ee.db
        echo "ALTER TABLE sites ADD COLUMN db_password varchar;" | sqlite3 /var/lib/ee/ee.db
        echo "ALTER TABLE sites ADD COLUMN db_host varchar;" | sqlite3 /var/lib/ee/ee.db
        echo "ALTER TABLE sites ADD COLUMN is_hhvm INT DEFAULT '0';" | sqlite3 /var/lib/ee/ee.db
        echo "ALTER TABLE sites ADD COLUMN is_pagespeed INT DEFAULT '0';" | sqlite3 /var/lib/ee/ee.db
    fi
}


function secure_ee_db()
{
    chown -R root:root /var/lib/ee/
    chmod -R 600 /var/lib/ee/
}

function ee_update_wp_cli()
{
    ee_lib_echo "Updating WP-CLI version to resolve compatibility issue."
    PHP_PATH=$(which php)
    WP_CLI_PATH=$(which wp)
    if [ "${WP_CLI_PATH}" != "" ]; then
        # Get WP-CLI version
        WP_CLI_VERSION=$(${PHP_PATH} ${WP_CLI_PATH} --allow-root cli version | awk '{ print $2 }')
        dpkg --compare-versions ${WP_CLI_VERSION} lt 0.21.1
        # Update WP-CLI version
        if [ "$?" == "0" ]; then
           wget -qO ${WP_CLI_PATH} https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
           chmod +x ${WP_CLI_PATH}
        fi
    fi
}

# Install EasyContainer 3.x
function ee_install()
{
    # Remove old clone of EasyContainer (ec) if any
    rm -rf /tmp/easyengine &>> /dev/null

    # Clone EE 3.0 Python ee_branch
    ee_lib_echo "Cloning EasyContainer, please wait..."
    if [ "$ee_branch" = "" ]; then
        ee_branch=master
    fi

    git clone -b $ee_branch https://github.com/EasyContainer/easyengine.git /tmp/easyengine --quiet > /dev/null \
    || ee_lib_error "Unable to clone EasyContainer, exit status" $?

    cd /tmp/easyengine
    ee_lib_echo "Installing EasyContainer, please wait..."
    python3 setup.py install || ee_lib_error "Unable to install EasyContainer, exit status " $?
}

# Update EasyContainer configuration
# Remove EasyContainer 2.x
function ee_update()
{
    # Preserve old configuration
    ee_lib_echo "Updating EasyEngine configuration, please wait..."

    ee_grant_host=$(grep grant-host /etc/easyengine/ee.conf | awk '{ print $3 }' | head -1 )
    ee_db_name=$(grep db-name /etc/easyengine/ee.conf | awk '{ print $3 }')
    ee_db_user=$(grep db-name /etc/easyengine/ee.conf | awk '{ print $3 }')
    ee_wp_prefix=$(grep prefix /etc/easyengine/ee.conf | awk '{ print $3 }')
    ee_wp_user=$(grep 'user ' /etc/easyengine/ee.conf | grep -v db-user |awk '{ print $3 }')
    ee_wp_pass=$(grep password /etc/easyengine/ee.conf | awk '{ print $3 }')
    ee_wp_email=$(grep email /etc/easyengine/ee.conf | awk '{ print $3 }')
    ee_ip_addr=$(grep ip-address /etc/easyengine/ee.conf |awk -F'=' '{ print $2 }')

    sed -i "s/ip-address.*/ip-address = ${ee_ip_addr}/" /etc/ee/ee.conf && \
    sed -i "s/grant-host.*/grant-host = ${ee_grant_host}/" /etc/ee/ee.conf && \
    sed -i "s/db-name.*/db-name = ${db-name}/" /etc/ee/ee.conf && \
    sed -i "s/db-user.*/db-user = ${ee_db_user}/" /etc/ee/ee.conf && \
    sed -i "s/prefix.*/prefix = ${ee_wp_prefix}/" /etc/ee/ee.conf && \
    sed -i "s/^user.*/user = ${ee_wp_user}/" /etc/ee/ee.conf && \
    sed -i "s/password.*/password = ${ee_wp_password}/" /etc/ee/ee.conf && \
    sed -i "s/email.*/email = ${ee_wp_email}/" /etc/ee/ee.conf || ee_lib_error "Unable to update configuration, exit status " $?

    # Remove old EasyContainer
    ee_lib_echo "Removing EasyEngine 2.x"
    rm -rf /etc/bash_completion.d/ee /etc/easyengine/ /usr/share/easyengine/ /usr/local/lib/easyengine /usr/local/sbin/easyengine /usr/local/sbin/ee /var/log/easyengine

    # Softlink to fix command not found error
    ln -s /usr/local/bin/ee /usr/local/sbin/ee || ee_lib_error "Unable to create softlink to old EasyEngine, exit status " $?
}

function ee_update_latest()
{
    #Move ~/.my.cnf to /etc/mysql/conf.d/my.cnf
    if [ ! -f /etc/mysql/conf.d/my.cnf ]
    then
        #create conf.d folder if not exist
        if [ ! -d /etc/mysql/conf.d ]; then
            mkdir -p /etc/mysql/conf.d
            chmod 755 /etc/mysql/conf.d
        fi
        if [ -d /etc/mysql/conf.d ]
        then
            if [ -f ~/.my.cnf ]
            then
                cp ~/.my.cnf /etc/mysql/conf.d/my.cnf &>> /dev/null
                chmod 600 /etc/mysql/conf.d/my.cnf
            else
                if [ -f /root/.my.cnf ]
                then
                    cp /root/.my.cnf /etc/mysql/conf.d/my.cnf &>> /dev/null
                    chmod 600 /etc/mysql/conf.d/my.cnf
                else
                    ee_lib_echo_fail ".my.cnf cannot be located in your current user or root."
                fi
            fi
        fi
    fi

    if [ -f /etc/nginx/nginx.conf ]; then
        ee_lib_echo "Updating Nginx configuration, please wait..."
        # From version 3.1.10 we are using Suse builder for repository
        if [ "$ee_distro_version" == "precise" ]; then
            grep -Hr 'http://download.opensuse.org/repositories/home:/rtCamp:/EasyContainer/xUbuntu_12.04/ /' /etc/apt/sources.list.d/ &>> /dev/null
            if [[ $? -ne 0 ]]; then
                if [ -f /etc/apt/sources.list.d/rtcamp-nginx-precise.list ]; then
                    rm -rf /etc/apt/sources.list.d/rtcamp-nginx-precise.list
                fi
                echo -e "\ndeb http://download.opensuse.org/repositories/home:/rtCamp:/EasyContainer/xUbuntu_12.04/ /" >> /etc/apt/sources.list.d/ee-repo.list
                gpg --keyserver "hkp://pgp.mit.edu" --recv-keys '3050AC3CD2AE6F03'
                gpg -a --export --armor '3050AC3CD2AE6F03' | apt-key add -
                if [ -f /etc/nginx/conf.d/ee-nginx.conf ]; then
                    mv /etc/nginx/conf.d/ee-nginx.conf /etc/nginx/conf.d/ee-nginx.conf.old &>> /dev/null
                fi
                mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.old &>> /dev/null
                apt-get update
                apt-get -o Dpkg::Options::="--force-confmiss" -o Dpkg::Options::="--force-confold" -y install nginx-custom

            fi
        elif [ "$ee_distro_version" == "trusty" ]; then
            grep -Hr 'http://download.opensuse.org/repositories/home:/rtCamp:/EasyContainer/xUbuntu_14.04/ /' /etc/apt/sources.list.d/ &>> /dev/null
            if [[ $? -ne 0 ]]; then
                if [ -f /etc/apt/sources.list.d/rtcamp-nginx-trusty.list ]; then
                    rm -rf /etc/apt/sources.list.d/rtcamp-nginx-trusty.list
                fi
                echo -e "\ndeb http://download.opensuse.org/repositories/home:/rtCamp:/EasyContainer/xUbuntu_14.04/ /" >> /etc/apt/sources.list.d/ee-repo.list
                gpg --keyserver "hkp://pgp.mit.edu" --recv-keys '3050AC3CD2AE6F03'
                gpg -a --export --armor '3050AC3CD2AE6F03' | apt-key add -
                if [ -f /etc/nginx/conf.d/ee-nginx.conf ]; then
                    mv /etc/nginx/conf.d/ee-nginx.conf /etc/nginx/conf.d/ee-nginx.conf.old &>> /dev/null
                fi
                mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.old &>> /dev/null
                apt-get update
                apt-get -o Dpkg::Options::="--force-confmiss" -o Dpkg::Options::="--force-confold" -y install nginx-custom
            fi
        elif [ "$ee_distro_version" == "wheezy" ]; then
            grep -Hr 'http://download.opensuse.org/repositories/home:/rtCamp:/EasyContainer/Debian_7.0/ /' /etc/apt/sources.list.d/ &>> /dev/null
            #grep -Hr "deb http://packages.dotdeb.org wheezy all" /etc/apt/sources.list.d/ee-repo.list &>> /dev/null
            if [[ $? -ne 0 ]]; then
                # if [ -f /etc/apt/sources.list.d/dotdeb-wheezy.list ]; then
                #     rm -rf /etc/apt/sources.list.d/dotdeb-wheezy.list
                # else
                #     sed -i "/deb http:\/\/packages.dotdeb.org wheezy all/d" /etc/apt/sources.list.d/ee-repo.list &>> /dev/null
                # fi
                echo -e "deb http://download.opensuse.org/repositories/home:/rtCamp:/EasyContainer/Debian_7.0/ /" >> /etc/apt/sources.list.d/ee-repo.list
                gpg --keyserver "hkp://pgp.mit.edu" --recv-keys '3050AC3CD2AE6F03'
                gpg -a --export --armor '3050AC3CD2AE6F03' | apt-key add -
                if [ -f /etc/nginx/conf.d/ee-nginx.conf ]; then
                    mv /etc/nginx/conf.d/ee-nginx.conf /etc/nginx/conf.d/ee-nginx.conf.old &>> /dev/null
                fi
                mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.old &>> /dev/null
                mv /etc/nginx/fastcgi_params /etc/nginx/fastcgi_params.old &>> /dev/null
                apt-get update
                apt-get -o Dpkg::Options::="--force-confmiss" -o Dpkg::Options::="--force-confold" -y install nginx-custom
            fi
        elif [ "$ee_distro_version" == "jessie" ]; then

            grep -Hr 'http://download.opensuse.org/repositories/home:/rtCamp:/EasyContainer/Debian_8.0/ /' /etc/apt/sources.list.d/ &>> /dev/null
            #grep -Hr "deb http://packages.dotdeb.org jessie all" /etc/apt/sources.list.d/ee-repo.list &>> /dev/null
            if [[ $? -ne 0 ]]; then
                #sed -i "/deb http:\/\/packages.dotdeb.org jessie all/d" /etc/apt/sources.list.d/ee-repo.list &>> /dev/null
                echo -e "deb http://download.opensuse.org/repositories/home:/rtCamp:/EasyContainer/Debian_8.0/ /" >> /etc/apt/sources.list.d/ee-repo.list
                gpg --keyserver "hkp://pgp.mit.edu" --recv-keys '3050AC3CD2AE6F03'
                gpg -a --export --armor '3050AC3CD2AE6F03' | apt-key add -
                if [ -f /etc/nginx/conf.d/ee-nginx.conf ]; then
                    mv /etc/nginx/conf.d/ee-nginx.conf /etc/nginx/conf.d/ee-nginx.conf.old &>> /dev/null
                fi
                mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.old &>> /dev/null
                mv /etc/nginx/fastcgi_params /etc/nginx/fastcgi_params.old &>> /dev/null
                apt-get update
                apt-get -o Dpkg::Options::="--force-confmiss" -o Dpkg::Options::="--force-confold" -y install nginx-custom
            fi
        fi
    fi

    if [ -f /etc/nginx/nginx.conf ]; then
        sed -i "s/.*X-Powered-By.*/\tadd_header X-Powered-By \"EasyContainer $ec_version_new\";/" /etc/nginx/nginx.conf &>> /dev/null
    fi

    if [ -f /etc/nginx/conf.d/ee-plus.conf ]; then
        sed -i "s/.*X-Powered-By.*/\tadd_header X-Powered-By \"EasyContainer $ec_version_new\";/" /etc/nginx/conf.d/ee-plus.conf &>> /dev/null
    fi

    # Disable Xdebug on old systems if and only if ee debug is off
    if [ -f /etc/php5/mods-available/xdebug.ini ]; then
        ee_debug_value=$(grep -Hr 9001 /etc/nginx/conf.d/upstream.conf | wc -l )
        if [ $ee_debug_value -eq 1 ]; then
            grep -Hr ";zend_extension" /etc/php5/mods-available/xdebug.ini &>> /dev/null
            if [ $? -ne 0 ]; then
                sed -i "s/zend_extension/;zend_extension/" /etc/php5/mods-available/xdebug.ini
            fi
        fi
    fi

    # Fix HHVM autostart on reboot
    dpkg --get-selections | grep -v deinstall | grep hhvm &>> /dev/null
    if [ $? -eq 0 ]; then
        update-rc.d hhvm defaults &>> /dev/null
    fi

    # Fix WordPress example.html issue
    # Ref: http://wptavern.com/xss-vulnerability-in-jetpack-and-the-twenty-fifteen-default-theme-affects-millions-of-wordpress-users
    dpkg --get-selections | grep -v deinstall | grep nginx &>> /dev/null
    if [ $? -eq 0 ]; then
        cp /usr/lib/ee/templates/locations.mustache /etc/nginx/common/locations.conf &>> /dev/null
    fi

    # Fix HHVM upstream issue that was preventing from using EasyEngine for site operations
    if [ -f /etc/nginx/conf.d/upstream.conf ]; then
        grep -Hr hhvm /etc/nginx/conf.d/upstream.conf &>> /dev/null
        if [ $? -ne 0 ]; then
            echo -e "upstream hhvm {\n# HHVM Pool\nserver 127.0.0.1:8000;\nserver 127.0.0.1:9000 backup;\n}\n" >> /etc/nginx/conf.d/upstream.conf
        fi
    fi

    # Fix HHVM server IP
    if [ -f /etc/hhvm/server.ini ]; then
        grep -Hr "hhvm.server.ip" /etc/hhvm/server.ini &>> /dev/null
        if [ $? -ne 0 ]; then
            echo -e "hhvm.server.ip = 127.0.0.1\n" >> /etc/hhvm/server.ini
        fi
    fi


    # Rename Redis Header
    if [ -f /etc/nginx/common/redis-hhvm.conf ]; then
      sed -i "s/X-Cache /X-SRCache-Fetch-Status /g" /etc/nginx/common/redis-hhvm.conf &>> /dev/null
      sed -i "s/X-Cache-2 /X-SRCache-Store-Status /g" /etc/nginx/common/redis-hhvm.conf &>> /dev/null
    fi

    if [ -f /etc/nginx/common/redis.conf ]; then
      sed -i "s/X-Cache /X-SRCache-Fetch-Status /g" /etc/nginx/common/redis.conf &>> /dev/null
      sed -i "s/X-Cache-2 /X-SRCache-Store-Status /g" /etc/nginx/common/redis.conf &>> /dev/null
    fi


    if [ -f /etc/nginx/common/redis-hhvm.conf ]; then
    # Update Timeout redis-hhvm.conf
      grep -0 'redis2_query expire $key 6h' /etc/nginx/common/redis-hhvm.conf &>> /dev/null
      if [ $? -eq 0 ]; then
        sed -i 's/redis2_query expire $key 6h/redis2_query expire $key 14400/g' /etc/nginx/common/redis-hhvm.conf &>> /dev/null
      fi

    #Fix for 3.3.4 redis-hhvm issue
      grep -0 'HTTP_ACCEPT_ENCODING' /etc/nginx/common/redis-hhvm.conf &>> /dev/null
      if [ $? -ne 0 ]; then
        sed -i 's/fastcgi_params;/fastcgi_params;\n  fastcgi_param HTTP_ACCEPT_ENCODING "";/g' /etc/nginx/common/redis-hhvm.conf &>> /dev/null
      fi
    fi

    #Fix Security Issue. commit #c64f28e
    if [ -f /etc/nginx/common/locations.conf ]; then
       grep -0 '$request_uri ~\* \"^.+(readme|license|example)\\.(txt|html)$\"' /etc/nginx/common/locations.conf &>> /dev/null
       if [ $? -eq 0 ]; then
        sed -i 's/$request_uri ~\* \"^.+(readme|license|example)\\.(txt|html)$\"/$uri ~\* \"^.+(readme|license|example)\\.(txt|html)$\"/g' /etc/nginx/common/locations.conf &>> /dev/null
       fi
    fi

    #Fix Redis-server security issue
    #http://redis.io/topics/security
     if [ -f /etc/redis/redis.conf  ]; then
       grep -0 -v "#" /etc/redis/redis.conf | grep 'bind' &>> /dev/null
       if [ $? -ne 0 ]; then
            sed -i '$ a bind 127.0.0.1' /etc/redis/redis.conf &>> /dev/null
            service redis-server restart &>> /dev/null
       fi
     fi

    #Fix For --letsencrypt
    if [ -f /etc/nginx/common/locations.conf ]; then
       grep -0 'location ~ \/\\.well-known' /etc/nginx/common/locations.conf &>> /dev/null
       if [ $? -ne 0 ]; then
        sed -i 's/# Deny hidden files/# Deny hidden files\nlocation ~ \/\\.well-known {\n  allow all;\n}\n /g' /etc/nginx/common/locations.conf &>> /dev/null
       fi
    fi

    # Fix for 3.3.2 renamed nginx.conf
    nginx -V 2>&1 &>>/dev/null
    if [[ $? -eq 0 ]]; then
        nginx -t 2>&1 | grep 'open() "/etc/nginx/nginx.conf" failed' &>>/dev/null
        if [[ $? -eq 0 ]]; then
            if [ -f /etc/nginx/nginx.conf.old ]; then
                if [ ! -f /etc/nginx/nginx.conf ]; then
                    cp /etc/nginx/nginx.conf.old /etc/nginx/nginx.conf
                fi
            fi
        fi
        # Fix for 3.3.2 renamed fastcgi_param
        nginx -t 2>&1 | grep 'open() "/etc/nginx/fastcgi_params" failed' &>>/dev/null
        if [[ $? -eq 0 ]]; then
            if [ -f /etc/nginx/fastcgi_params.old ]; then
                if [ ! -f /etc/nginx/fastcgi_params ]; then
                    cp /etc/nginx/fastcgi_params.old /etc/nginx/fastcgi_params
                fi
            fi
        fi
    fi

    #Fix For ssl_ciphers
    if [ -f /etc/nginx/nginx.conf ]; then
       sed -i 's/HIGH:!aNULL:!MD5:!kEDH;/ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:ECDHE-RSA-DES-CBC3-SHA:ECDHE-ECDSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA;/' /etc/nginx/nginx.conf
    fi


}

# Do git intialisation
function ee_git_init()
{
    # Nginx under git version control
    if [ -d /etc/nginx ];then
        cd /etc/nginx
        if [ ! -d /etc/nginx/.git ]; then
            git init &>> /dev/null
        fi
        git add -A .
        git commit -am "Updated Nginx" > /dev/null
    fi
    # EasyEngine under git version control
    cd /etc/ee
    if [ ! -d /etc/ee/.git ]; then
        git init > /dev/null
    fi
    git add -A .
    git commit -am "Installed/Updated to EasyEngine 3.x" &>> /dev/null

}

# Update EasyEngine
if [ -f /usr/local/sbin/easyengine ]; then
    # Check old EasyEngine version
    ee version | grep ${ee_version_old} &>> /dev/null
    if [[ $? -ne 0 ]]; then
        ee_lib_echo "EasyEngine $ee_version_old not found on your system" | tee -ai $ee_install_log
        ee_lib_echo "Updating your EasyEngine to $ee_version_old for compability" | tee -ai $ee_install_log
        wget -q https://raw.githubusercontent.com/rtCamp/easyengine/old-stable/bin/update && bash update
        if [[ $? -ne 0 ]]; then
            ee_lib_echo_fail "Unable to update EasyEngine to $ee_version_old, exit status = " $?
            exit 100
        fi
    fi
    read -p "Update EasyEngine to $ee_version_new (y/n): " ee_ans
    if [ "$ee_ans" = "y" ] || [ "$ee_ans" = "Y" ]; then
        ee_install_dep | tee -ai $ee_install_log
        ee_sync_db 2&>>1 $EE_INSTALL_LOG
        secure_ee_db | tee -ai $EE_INSTALL_LOG
        ee_install | tee -ai $ee_install_log
        ee_update | tee -ai $ee_install_log
        ee_update_latest | tee -ai $ee_install_log
        ee_git_init | tee -ai $ee_install_log
    else
        ee_lib_error "Not updating EasyEngine to $ee_version_new, exit status = " 1
    fi
elif [ ! -f /usr/local/bin/ee ]; then
    ee_install_dep | tee -ai $ee_install_log
    ee_install | tee -ai $ee_install_log
    secure_ee_db | tee -ai $EE_INSTALL_LOG
    ee_git_init | tee -ai $ee_install_log

else
    ee -v 2>&1 | grep $ee_version_new &>> /dev/null
    if [[ $? -ne 0 ]];then
        read -p "Update EasyEngine to $ee_version_new (y/n): " ee_ans
        if [ "$ee_ans" = "y" ] || [ "$ee_ans" = "Y" ]; then
            ee_install_dep | tee -ai $ee_install_log
            ee_sync_db 2&>>1 $EE_INSTALL_LOG
            secure_ee_db | tee -ai $EE_INSTALL_LOG
            ee_install | tee -ai $ee_install_log
            ee_update_latest | tee -ai $ee_install_log
            ee_git_init | tee -ai $ee_install_log
            service nginx reload &>> /dev/null
            service php5-fpm restart &>> /dev/null
            ee_update_wp_cli | tee -ai $ee_install_log
        else
            ee_lib_error "Not updating EasyEngine to $ee_version_new, exit status = " 1
        fi
    else
        ee_lib_error "You already have EasyEngine $ee_version_new, exit status = " 1
    fi
fi
ee sync | tee -ai $EE_INSTALL_LOG

echo
ee_lib_echo "For EasyEngine (ec) auto completion, run the following command"
echo
ee_lib_echo_info "source /etc/bash_completion.d/ee_auto.rc"
echo
ee_lib_echo "EasyEngine (ec) installed/updated successfully"
ee_lib_echo "EasyEngine (ec) help: http://docs.rtcamp.com/easyengine/"
