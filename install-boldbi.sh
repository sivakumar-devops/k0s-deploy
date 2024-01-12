#!/usr/bin/env bash
# Copyright (c) Syncfusion Inc. All rights reserved.
#

# Stop script on NZEC
set -e
# Stop script if unbound variable found (use ${var:-} if intentional)
set -u
# By default cmd1 | cmd2 returns exit code of cmd2 regardless of cmd1 success
# This is causing it to fail
set -o pipefail

# Use in the the functions: eval $invocation
invocation='say_verbose "Calling: ${yellow:-}${FUNCNAME[0]} ${green:-}$*${normal:-}"'

# standard output may be used as a return value in the functions
# we need a way to write text on the screen in the functions so that
# it won't interfere with the return value.
# Exposing stream 3 as a pipe to standard output of the script itself
exec 3>&1

verbose=true
args=("$@")
old_install_dir="/var/www/boldbi-embedded"
install_dir="/var/www/bold-services"
backup_folder="/var/www"
dotnet_dir="$install_dir/dotnet"
services_dir="$install_dir/services"
system_dir="/etc/systemd/system"
boldbi_product_json_location="$install_dir/application/app_data/configuration/product.json"
boldbi_config_xml_location="$install_dir/application/app_data/configuration/config.xml"
user=""
host_url=""
server=""
distribution=""
VER=""
move_idp=false
common_idp_fresh=false
common_idp_upgrade=false
services_array=("bold-id-web" "bold-id-api" "bold-ums-web" "bold-bi-web" "bold-bi-api" "bold-bi-jobs" "bold-bi-designer" "bold-etl")
installation_type=""
is_bing_map_enabled=false
bing_map_api_key=""
app_data_location="$install_dir/application/app_data"
puppeteer_location="$app_data_location/bi/dataservice/puppeteer"
lic_key=""
db_type=""
db_host=""
db_user=""
db_pwd=""
db_name=""
db_port=""
maintain_db=""
email=""
epwd=""
add_parameters=""
main_logo=""
login_logo=""
email_logo=""
favicon=""
footer_logo=""
site_name=""
site_identifier=""
optional_libs=""
use_siteidentifier=""
current_dir=$(pwd)
azure_insight=""

# Setup some colors to use. These need to work in fairly limited shells, like the Ubuntu Docker container where there are only 8 colors.
# See if stdout is a terminal
if [ -t 1 ] && command -v tput > /dev/null; then
    # see if it supports colors
    ncolors=$(tput colors)
    if [ -n "$ncolors" ] && [ $ncolors -ge 8 ]; then
        bold="$(tput bold       || echo)"
        normal="$(tput sgr0     || echo)"
        black="$(tput setaf 0   || echo)"
        red="$(tput setaf 1     || echo)"
        green="$(tput setaf 2   || echo)"
        yellow="$(tput setaf 3  || echo)"
        blue="$(tput setaf 4    || echo)"
        magenta="$(tput setaf 5 || echo)"
        cyan="$(tput setaf 6    || echo)"
        white="$(tput setaf 7   || echo)"
    fi
fi

say_err() {
    printf "%b\n" "${red:-}boldbi_install: Error: $1${normal:-}" >&2
}

while [ $# -ne 0 ]
do
    name="$1"
    case "$name" in
        -d|--install-dir|-[Ii]nstall[Dd]ir)
            shift
            install_dir="$1"
            ;;
			
		-i|--install|-[Ii]nstall)
            shift
            installation_type="$1"
            ;;
			
		-u|--user|-User)
            shift
            user="$1"
            ;;
			
		-[Ll]icense)
		  shift
		  lic_key="$1"
		  ;;

		-[Dd]atabasetype)
		  shift
		  db_type="$1"
		  ;;

		-[Dd]atabasehost)
		  shift
		  db_host="$1"
		  ;;

		-[Dd]atabaseport)
		  shift
		  db_port="$1"
		  ;;		  

		-[Dd]atabasename)
		  shift
		  db_name="$1"
		  ;;

		-[Mm]aintaindb)
		  shift
		  maintain_db="$1"
		  ;;

		-[Dd]atabaseuser)
		  shift
		  db_user="$1"
		  ;;

		-[Dd]atabasepwd)
		  shift
		  db_pwd="$1"
		  ;;

		-[Aa]dditionalparameters)
		  shift
		  add_parameters="$1"
		  ;;

    		-[Uu]sesiteidentifier)
      		  shift
	          use_siteidentifier="$1"
	          ;;

		-[Ee]mail)
		  shift
		  email="$1"
		  ;;

		-[Ee]mailpwd)
		  shift
		  epwd="$1"
		  ;;
		  
		-[Mm]ainlogo)
		  shift
		  main_logo="$1"
		  ;;
		  
		-[Ll]oginlogo)
		  shift
		  login_logo="$1"
		  ;;
		  
		-[Ee]maillogo)
		  shift
		  email_logo="$1"
		  ;;
		  
		-[Ff]avicon)
		  shift
		  favicon="$1"
		  ;;
		  
		-[Ff]ooterlogo)
		  shift
		  footer_logo="$1"
		  ;;
		  
		-[Ss]itename)
		  shift
		  site_name="$1"
		  ;;
		  
		-[Ss]iteidentifier)
		  shift
		  site_identifier="$1"
		  ;;
    
    		-[Oo]ptionallibs)
      		  shift
	  	  optional_libs="$1"
      		  ;;
	  
   		-[Aa]zureinsight)
    		  shift
		  azure_insight="$1"
		  ;;
    
		-h|--host|-[Hh]ost)
            shift
            host_url="$1"
            ;;
			
		-n|--nginx|-[Nn]ginx)
            shift
			if $1; then
				server="nginx"
			fi
            ;;
			
		-s|--server|-[Ss]erver)
            shift
			server="$1"	
            ;;

		-distro|--distribution|-[Dd]istro)
            shift
			distribution="$1"	
            ;;
        
        -?|--?|--help|-[Hh]elp)
            script_name="$(basename "$0")"
            echo "Bold BI Installer"
            echo "Usage: $script_name [-u|--user <USER>]"
            echo "       $script_name |-?|--help"
            echo ""
            exit 0
            ;;
        *)
            say_err "Unknown argument \`$name\`"
            exit 1
            ;;
    esac

    shift
done

say_warning() {
    printf "%b\n" "${yellow:-}boldbi_install: Warning: $1${normal:-}" >&3
}

say() {
    # using stream 3 (defined in the beginning) to not interfere with stdout of functions
    # which may be used as return value
    printf "%b\n" "${cyan:-}boldbi-install:${normal:-} $1" >&3
}

say_verbose() {
    if [ "$verbose" = true ]; then
        say "$1"
    fi
}

machine_has() {
    eval $invocation

    hash "$1" > /dev/null 2>&1
    return $?
}

check_distribution() {
	eval $invocation

	if [ -f /etc/os-release ]; then
		. /etc/os-release
		OS=$ID
		VER=$VERSION_ID
	elif type lsb_release >/dev/null 2>&1; then
		OS=$(lsb_release -si)
		VER=$(lsb_release -sr)
	elif [ -f /etc/lsb-release ]; then
		. /etc/lsb-release
		OS=$DISTRIB_ID
		VER=$DISTRIB_RELEASE
	elif [ -f /etc/debian_version ]; then
		OS="debian"
		VER=$(cat /etc/debian_version)
	elif [ -f /etc/redhat-release ]; then
		# Older Red Hat, CentOS, etc.
		OS="centos"
	else
		OS=$(uname -s)
		VER=$(uname -r)
	fi
	
	OS=$(to_lowercase $OS)
	
	if [[ $OS = "centos" || $OS = "rhel" || $OS = "ol" ]]; then
		distribution="centos"
	else
		distribution="ubuntu"
	fi	
	
	say "Distribution: $distribution"
	say "Distribution Version: $VER"
}
install-chromium-dependencies() {
    eval $invocation
	
    if [ $distribution == "centos" ]; then
            yum update && yum -y install pango.x86_64 libXcomposite.x86_64 libXcursor.x86_64 libXdamage.x86_64 libXext.x86_64 libXi.x86_64 libXtst.x86_64 cups-libs.x86_64 libXScrnSaver.x86_64 libXrandr.x86_64 alsa-lib.x86_64 atk.x86_64 gtk3.x86_64 xorg-x11-fonts-100dpi xorg-x11-fonts-75dpi xorg-x11-utils xorg-x11-fonts-cyrillic xorg-x11-fonts-Type1 xorg-x11-fonts-misc
    else
            apt-get update && apt-get -y install xvfb gconf-service libasound2 libatk1.0-0 libc6 libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 libgbm1 libgcc1 libgconf-2-4 libgdk-pixbuf2.0-0 libglib2.0-0 libgtk-3-0 libnspr4 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6 ca-certificates fonts-liberation libappindicator1 libnss3 lsb-release xdg-utils wget && rm -rf /var/lib/apt/lists/*
    fi
}

check_min_reqs() {
    # local hasMinimum=false
    # if machine_has "curl"; then
        # hasMinimum=true
    # elif machine_has "wget"; then
        # hasMinimum=true
    # fi

    # if [ "$hasMinimum" = "false" ]; then
        # say_err "curl or wget are required to download Bold BI. Install missing prerequisite to proceed."
        # return 1
    # fi	
	
	if [ "$installation_type" = "upgrade" ]; then
		if ! hash "pv" > /dev/null 2>&1; then
		    say_err "pv (Pipe Viewer) package is required for installing Bold BI. Install the missing prerequisite to proceed."
		    return 1
		fi

		if ! hash "python3" > /dev/null 2>&1; then
		    say_err "python3 is required for installing Bold BI. Install the missing prerequisite to proceed."
		    return 1
		fi

	fi
	
	if ! hash "zip" > /dev/null 2>&1; then
	    say_err "Zip is required to extract the Bold BI Linux package. Install the missing prerequisite to proceed."
	    return 1
	fi


	if ! hash "python3" > /dev/null 2>&1; then
	    say_err "python3 is required for installing Bold BI. Install the missing prerequisite to proceed."
	    return 1
	fi
	
	if [ "$server" = "nginx" ]; then
		if ! hash "nginx" > /dev/null 2>&1; then
		    say_err "Nginx is required to host the Bold BI application. Install the missing prerequisite to proceed."
		    return 1
		fi		
		    return 0
	elif [ "$server" = "apache" ]; then
		if [ "$distribution" = "ubuntu" ]; then
		    if ! hash "apache2" > /dev/null 2>&1; then
		        say_err "Apache is required to host the Bold BI application. Install the missing prerequisite to proceed."
		        return 1
		    fi
		else
		    if ! hash "httpd" > /dev/null 2>&1; then
		        say_err "Apache is required to host the Bold BI application. Install the missing prerequisite to proceed."
		        return 1
		    fi
		fi		
		return 0
	fi
}

# args:
# input - $1
to_lowercase() {
    #eval $invocation

    echo "$1" | tr '[:upper:]' '[:lower:]'
    return 0
}

# args:
# input - $1
remove_trailing_slash() {
    #eval $invocation

    local input="${1:-}"
    echo "${input%/}"
    return 0
}

# args:
# input - $1
remove_beginning_slash() {
    #eval $invocation

    local input="${1:-}"
    echo "${input#/}"
    return 0
}

read_user() {
	# eval $invocation

	# Read user from existing service file
	read_user="$(grep -F -m 1 'User=' $system_dir/bold-id-web.service)"
	IFS='='
	read -ra user_arr <<< "$read_user"
	user="${user_arr[1]%%[[:cntrl:]]}"
	# user="${user%%[[:cntrl:]]}"
}

read_host_url() {
	# eval $invocation

	# Read Host URL from existing product.json file
	if [ -d "$install_dir" ]; then
		read_url="$(grep -F -m 1 '<Idp>' $boldbi_config_xml_location)"
	else
		read_url="$(grep -F -m 1 '<Idp>' $old_install_dir/boldbi/app_data/configuration/config.xml)"
	fi
    IFS='>'
    read -ra url_arr1 <<< "$read_url"
    temp_url="${url_arr1[1]%%[[:cntrl:]]}"
    IFS='<'
    read -ra url_arr2 <<< "$temp_url"
    host_url="${url_arr2[0]%%[[:cntrl:]]}"
}

enable_boldbi_services() {
	eval $invocation

	for t in ${services_array[@]}; do
		if $common_idp_fresh; then
			if [ $t = "bold-id-web" ] || [ $t = "bold-id-api" ] || [ $t = "bold-ums-web" ]; then
				continue
			fi
		fi
		if systemctl is-enabled "$t" > /dev/null 2>&1; then
	            echo "$t-service already enabled"
	        else
	            echo "Enabling service - $t"
	            systemctl enable "$t"
	        fi
	done
}

copy_files_to_installation_folder() {
	eval $invocation
	
	cp -a application/. $install_dir/application/
	cp -a uninstall-boldbi.sh $install_dir/uninstall-boldbi.sh
	cp -a clientlibrary/. $install_dir/clientlibrary/
	cp -a dotnet/. $install_dir/dotnet/
	cp -a services/. $install_dir/services/
	cp -a Infrastructure/. $install_dir/Infrastructure/
}

start_boldbi_services() {
	eval $invocation
	
	for t in ${services_array[@]}; do
		if $common_idp_fresh; then
			if [ $t = "bold-id-web" ] || [ $t = "bold-id-api" ] || [ $t = "bold-ums-web" ]; then
				continue
			fi
		fi
		say "Starting service - $t"
		systemctl start $t

		if ! ( $common_idp_fresh || $common_idp_upgrade ); then
			if [ $t = "bold-id-web" ]; then
				say "Initializing $t"
				sleep 5
			fi
		fi
	done
}

status_boldbi_services() {
	eval $invocation

	systemctl --type=service | grep bold-id-*
	systemctl --type=service | grep bold-ums-web
	systemctl --type=service | grep bold-bi-*
}

stop_boldbi_services() {
    eval $invocation
    for t in "${services_array[@]}"; do
        if systemctl is-enabled "$t" >/dev/null 2>&1; then
            say "Stopping service - $t"
            systemctl stop "$t"  # Stop the service
        else
            say "Unable to stop $t service as it is not enabled"
        fi
    done
}

restart_boldbi_services() {
	eval $invocation
	for t in ${services_array[@]}; do
		say "Restarting service - $t"
		systemctl restart $t

		if [ $t = "bold-id-web" ]; then
			sleep 5
		fi
	done
}

check_config_file_generated() {
	eval $invocation
	if [ ! -f "$boldbi_config_xml_location" ]; then
		say "Generating configuration files..."
		restart_boldbi_services
	fi
}

chrome_package_installation() {
	eval $invocation

	[ ! -d "$app_data_location/bi" ] && mkdir -p "$app_data_location/bi"
	[ ! -d "$app_data_location/bi/dataservice" ] && mkdir -p "$app_data_location/bi/dataservice"
	[ ! -d "$puppeteer_location" ] && mkdir -p "$puppeteer_location"

	"$install_dir/dotnet/dotnet" "$install_dir/application/utilities/adminutils/Syncfusion.Server.Commands.Utility.dll" "installpuppeteer" -path "$puppeteer_location"
	install-chromium-dependencies
	
	if [ -d "$puppeteer_location/Linux-901912" ]; then
	    ## Removing PhantomJS
		[ -f "$app_data_location/bi/dataservice/phantomjs" ] && rm -rf "$app_data_location/bi/dataservice/phantomjs"
		say "Chrome package installed successfully"
	fi
}

update_url_in_product_json() {
	eval $invocation
	old_url="http:\/\/localhost\/"
	new_url="$(remove_trailing_slash "$host_url")"

	idp_url="$new_url"
	say "IDP URL - $idp_url"
	
	bi_url="$new_url/bi"
	say "BI URL - $bi_url"
	
	bi_designer_url="$new_url/bi/designer"
	say "BI Designer URL - $bi_designer_url"
	
	sed -i $boldbi_product_json_location -e "s|\"Idp\":.*\",|\"Idp\":\"$idp_url\",|g" -e "s|\"Bi\":.*\",|\"Bi\":\"$bi_url\",|g" -e "s|\"BiDesigner\":.*\",|\"BiDesigner\":\"$bi_designer_url\",|g"
	
	say "Product.json file URLs updated."
}
	
copy_service_files () {
    eval $invocation
    for t in "${services_array[@]}"; do
        if [ ! -f "$system_dir/$t.service" ]; then
            cp -a "$services_dir/$t.service" "$system_dir/"
            say "Copying required $t.service file"
        fi
    done
}

configure_nginx () {
	eval $invocation

	if [ "$distribution" = "centos" ]; then
		centos_nginx_dir="/etc/nginx/conf.d"
		[ ! -d "$centos_nginx_dir" ] && mkdir -p "$centos_nginx_dir"
		say "Copying Bold BI Nginx config file"
		cp boldbi-nginx-config $centos_nginx_dir/boldbi-nginx-config
		mv $centos_nginx_dir/boldbi-nginx-config $centos_nginx_dir/boldbi-nginx-config.conf

		if [ $VER == "8" ]; then
			sed -i "s|80 default_server|8080 default_server|g" "/etc/nginx/nginx.conf"
			sed -i "s|[::]:80 default_server|[::]:8080 default_server|g" "/etc/nginx/nginx.conf"
		fi

	else
		nginx_sites_available_dir="/etc/nginx/sites-available"
		nginx_sites_enabled_dir="/etc/nginx/sites-enabled"
		
		[ ! -d "$nginx_sites_available_dir" ] && mkdir -p "$nginx_sites_available_dir"
		[ ! -d "$nginx_sites_enabled_dir" ] && mkdir -p "$nginx_sites_enabled_dir"
		
		say "Copying Bold BI Nginx config file"
		cp boldbi-nginx-config $nginx_sites_available_dir/boldbi-nginx-config
		
		nginx_default_file=$nginx_sites_available_dir/default
		if [ -f "$nginx_default_file" ]; then
			say "Taking backup of default nginx file"
			mv $nginx_default_file $nginx_sites_available_dir/default_backup
			say "Removing the default Nginx file"
			rm $nginx_sites_enabled_dir/default
		fi
		
		say "Creating symbolic links from these files to the sites-enabled directory"
		ln -s $nginx_sites_available_dir/boldbi-nginx-config $nginx_sites_enabled_dir/
	fi

	if [ ! -e /var/run/nginx.pid ]; then
		systemctl start nginx
	fi
	
	validate_nginx_config
}

configure_apache () {
	eval $invocation

	apachectl_path=$(which apachectl)
	say "Starting apache server"
	$apachectl_path start

	if [ "$distribution" = "centos" ]; then
		apache_sites_available_dir="/etc/httpd/sites-available"
		apache_sites_enabled_dir="/etc/httpd/sites-enabled"
		httpd_conf_file_path="/etc/httpd/conf/httpd.conf"
		sed -i "s|Protocols h2 http/1.1|# Protocols h2 http/1.1|g" boldbi-apache-config.conf
		sed -i "s|RequestHeader set|# RequestHeader set|g" boldbi-apache-config.conf
		grep -qxF 'IncludeOptional sites-enabled/*.conf' "$httpd_conf_file_path" || echo 'IncludeOptional sites-enabled/*.conf' >> "$httpd_conf_file_path"
	else
		apache_sites_available_dir="/etc/apache2/sites-available"
		apache_sites_enabled_dir="/etc/apache2/sites-enabled"
	fi
	
	[ ! -d "$apache_sites_available_dir" ] && mkdir -p "$apache_sites_available_dir"
	[ ! -d "$apache_sites_enabled_dir" ] && mkdir -p "$apache_sites_enabled_dir"
	
	say "Copying Bold BI apache config file"
	cp boldbi-apache-config.conf $apache_sites_available_dir/boldbi-apache-config.conf
	
	if [ "$distribution" = "ubuntu" ]; then
		apache_default_file=$apache_sites_available_dir/000-default.conf
		if [ -f "$apache_default_file" ]; then
			say "Taking backup of default apache file"
			mv $apache_default_file $apache_sites_available_dir/000-default-backup.conf
			say "Removing the default apache file"
			rm $apache_sites_enabled_dir/000-default.conf
		fi
	fi

	port=""
	server_name=($(echo $host_url | cut -d'/' -f3))
	
	if [[ $host_url == *"localhost"* ]]; then
		port=($(echo $host_url | cut -d':' -f3))
		port=($(echo $port | cut -d'/' -f1))
		say "Port: $port"
		if [ "$distribution" = "ubuntu" ]; then
			echo "Listen $port"  >> /etc/apache2/ports.conf
			echo "#The above is the port included by Bold BI" >> /etc/apache2/ports.conf
		else
			echo "Listen $port"  >> /etc/httpd/conf.d/ports.conf
			echo "#The above is the port included by Bold BI" >> /etc/httpd/conf.d/ports.conf
		fi
	else
		say "ServerName: $server_name"
		sed -i "s|ServerName localhost|ServerName $server_name|g" $apache_sites_available_dir/boldbi-apache-config.conf
		#sed -i "s|Redirect / localhost|Redirect / $host_url/|g" $apache_sites_available_dir/boldbi-apache-config.conf
	fi
	
	say "Enabling required modules for apache server"
	if [ "$distribution" = "ubuntu" ]; then
		a2enmod proxy
		a2enmod proxy_http
		a2enmod proxy_wstunnel
		a2enmod rewrite
		a2enmod headers
		a2enmod ssl
	else
		grep -qxF 'LoadModule proxy_module modules/mod_proxy.so' "$httpd_conf_file_path" || echo 'LoadModule proxy_module modules/mod_proxy.so' >> "$httpd_conf_file_path"
		grep -qxF 'LoadModule proxy_http_module modules/mod_proxy_http.so' "$httpd_conf_file_path" || echo 'LoadModule proxy_http_module modules/mod_proxy_http.so' >> "$httpd_conf_file_path"
		grep -qxF 'LoadModule proxy_wstunnel_module modules/mod_proxy_wstunnel.so' "$httpd_conf_file_path" || echo 'LoadModule proxy_wstunnel_module modules/mod_proxy_wstunnel.so' >> "$httpd_conf_file_path"
		grep -qxF 'LoadModule rewrite_module modules/mod_rewrite.so' "$httpd_conf_file_path" || echo 'LoadModule rewrite_module modules/mod_rewrite.so' >> "$httpd_conf_file_path"
		grep -qxF 'LoadModule headers_module modules/mod_headers.so' "$httpd_conf_file_path" || echo 'LoadModule headers_module modules/mod_headers.so' >> "$httpd_conf_file_path"
	fi
	$apachectl_path restart
	
	say "Creating symbolic links from these files to the sites-enabled directory"	
    ln -s $apache_sites_available_dir/boldbi-apache-config.conf $apache_sites_enabled_dir/
	say "Validating the apache configuration"
	$apachectl_path configtest
	say "Restarting the apache to apply the changes"
	$apachectl_path restart
}

install_client_libraries () {
	eval $invocation
	bash $install_dir/clientlibrary/install-optional.libs.sh install-optional-libs "$optional_libs"
}

update_optional_lib() {
	if [ -f "$install_dir/optional-lib.txt" ]; then
        eval $invocation
        value=$(<$install_dir/optional-lib.txt)
        echo "$value"
        cd "/var/www/bold-services/clientlibrary"
        bash "install-optional.libs.sh" "install-optional-libs" "$value"
	fi
}

is_boldreports_already_installed() {
	systemctl list-unit-files | grep "bold-reports-*" > /dev/null 2>&1
	return $?
}

is_boldbi_already_installed() {
	systemctl list-unit-files | grep "bold-bi-*" > /dev/null 2>&1
	return $?
}

taking_backup(){
	eval $invocation
	say "Started creating backup . . ."
	timestamp="$(date +"%T")"
	backup_file_location=""

    if [ ! -d "$install_dir" ]; then
	rm -rf $backup_folder/boldbi-embedded_backup_*.zip
	rm -rf $backup_folder/bold_services_backup_*.zip
		backup_file_location=$backup_folder/boldbi-embedded_backup_$timestamp.zip
	    zip -r $backup_file_location $old_install_dir 2>&1 | pv -lep -s $(ls -Rl1 $old_install_dir | egrep -c '^[-/]') > /dev/null
	else
		rm -rf $backup_folder/boldbi-embedded_backup_*.zip
		rm -rf $backup_folder/bold_services_backup_*.zip
	    backup_file_location=$backup_folder/bold_services_backup_$timestamp.zip
	    zip -r $backup_file_location $install_dir 2>&1 | pv -lep -s $(ls -Rl1 $install_dir | egrep -c '^[-/]') > /dev/null
	fi
	
	say "Backup file name:$backup_file_location"
	say "Backup process completed . . ."
	return $?
	
}

removing_old_files(){
	eval $invocation
	rm -rf $install_dir/application/bi
	rm -rf $install_dir/application/idp
	rm -rf $install_dir/clientlibrary
	rm -rf $install_dir/dotnet
	rm -rf $install_dir/services
	rm -rf $install_dir/Infrastructure
}
	
validate_user() {
	eval $invocation
	if [[ $# -eq 0 ]]; then
		say_err "Please specify the user that manages the service."
		return 1
	fi	
	
	# if grep -q "^$1:" /etc/passwd ;then
		# return 0
	# else
		# say_err "User $1 is not valid"
		# return 1
	# fi
	
	return 0
}

validate_host_url() {
	eval $invocation
	if [[ $# -eq 0 ]]; then
		say_err "Please specify the host URL."
		return 1
	fi	
	
	url_regex='(https?|ftp|file)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]'
	if [[ $1 =~ $url_regex ]]; then 
		return 0
	else
		say_err "Please specify the valid host URL."
		return 1
	fi
}
upgrade_log() {
    source_dir="$app_data_location"
    
	exclude_folders=("logs" "upgradelogs")
	
	[ ! -d "$app_data_location/upgradelogs" ] && mkdir -p "$app_data_location/upgradelogs"
	
	json_file="$app_data_location/configuration/product.json"

	# Read the JSON file into a variable
	json_data=$(cat "$json_file")

	# Search for the version key and extract the version value
	version=$(echo "$json_data" | grep -o '"Version": "[^"]*' | sed 's/"Version": "//')
	
	
	if [ -d "$app_data_location/upgradelogs/$version" ]; then
    rm -r "$app_data_location/upgradelogs/$version"
    fi
	
	mkdir -p "$app_data_location/upgradelogs/$version"
	
	find "$source_dir" -type d \( -name "${exclude_folders[0]}" -o -name "${exclude_folders[1]}" \) -prune -o -print > "$app_data_location/upgradelogs/$version/upgrade_logs.txt"
}		
validate_installation_type() {
	eval $invocation
	if  [[ $# -eq 0 ]]; then
		say_err "Please specify the installation type (new or upgrade)."
		return 1
	fi	

	if  [ "$(to_lowercase $1)" != "new" ] && [ "$(to_lowercase $1)" != "upgrade" ]; then
		say_err "Please specify the valid installation type."
		return 1
	fi

	return 0	
}

validate_nginx_config() {
	eval $invocation
	say "Validating the Nginx configuration"
	nginx -t
	say "Restarting the Nginx to apply the changes"
	systemctl restart nginx
}

update_nginx_configuration() {
    if [ "$distribution" = "centos" ]; then
        config_file="/etc/nginx/conf.d/boldbi-nginx-config"
    else
        config_file="/etc/nginx/sites-available/boldbi-nginx-config"
    fi

    # Check if the configuration file exists
    if [ -f "$config_file" ]; then

        # Unique identifier to check if the content already exists
        identifier="location /etlservice/"

        # Check if the identifier already exists in the configuration file
        if ! grep -q "$identifier" "$config_file"; then
            # Lines to add
            new_lines=$(cat <<EOL
	    
    location /etlservice/ {
	root               /var/www/bold-services/application/etl/etlservice/wwwroot;
	proxy_pass http://localhost:6509/;
	proxy_http_version 1.1;
	proxy_set_header   Upgrade \$http_upgrade;
	proxy_set_header   Connection "upgrade";
	proxy_set_header   Host \$http_host;
	proxy_cache_bypass \$http_upgrade;
	proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
	proxy_set_header   X-Forwarded-Proto \$scheme;
    }
    location /etlservice/_framework/blazor.server.js {
	root               /var/www/bold-services/application/etl/etlservice/wwwroot;
	proxy_pass http://localhost:6509/_framework/blazor.server.js;
	proxy_http_version 1.1;
	proxy_set_header   Upgrade \$http_upgrade;
	proxy_set_header   Connection "upgrade";
	proxy_set_header   Host \$http_host;
	proxy_cache_bypass \$http_upgrade;
	proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
	proxy_set_header   X-Forwarded-Proto \$scheme;
    }
EOL
            )

            # Use awk to insert new lines above the last curly brace
            awk -v new_lines="$new_lines" '/^}/ { print new_lines; } 1' "$config_file" > temp_file && mv temp_file "$config_file"

            echo "Redirection code block has been inserted for new service(s) in the Nginx configuration file."
	    
            validate_nginx_config
        fi
    else
        echo "Error: Nginx Configuration file not found in the default location. Please insert the redirection code block by referring to the documentation manually."
    fi
}

update_apache_configuration() {
    if [ "$distribution" = "centos" ]; then
        config_file="/etc/httpd/sites-available/000-default.conf"
    else
        config_file="/etc/apache2/sites-available/boldbi-apache-config.conf"
    fi

    # Check if the configuration file exists
    if [ -f "$config_file" ]; then

        # Unique identifier to check if the content already exists
        identifier="location /etlservice/"

        # Check if the identifier already exists in the configuration file
        if ! grep -q "$identifier" "$config_file"; then
            # Lines to add
            new_lines=$(cat <<EOL
	    
    <Location /etlservice>
	ProxyPass http://localhost:6509/ Keepalive=On
	ProxyPassReverse http://localhost:6509/
	RewriteEngine on
	RewriteCond %{HTTP:UPGRADE} ^WebSocket$ [NC]
	RewriteRule /etlservice/(.*) ws://localhost:6509/etlservice/\$1 [P]
	RequestHeader set "X-Forwarded-Proto" expr=%{REQUEST_SCHEME}
    </Location>

    <Location /etlservice/_framework/blazor.server.js>
	ProxyPass http://localhost:6509/_framework/blazor.server.js Keepalive=On
	ProxyPassReverse http://localhost:6509/_framework/blazor.server.js
	RewriteEngine on
	RewriteCond %{HTTP:UPGRADE} ^WebSocket$ [NC]
	RewriteRule /etlservice/_framework/blazor.server.js(.*) ws://localhost:6509/etlservice/_framework/blazor.server.js\$1 [P]
	RequestHeader set "X-Forwarded-Proto" expr=%{REQUEST_SCHEME}
    </Location>
EOL
            )

            # Use awk to insert new lines above the last curly brace
            awk -v new_lines="$new_lines" '/^<\/VirtualHost>/ { print new_lines; } 1' "$config_file" > temp_file && mv temp_file "$config_file"

            echo "Redirection code block has been inserted for new service(s) in the Nginx configuration file."

            # Apache specific reload command
            if [ "$distribution" = "centos" ]; then
                service httpd reload
            else
                service apache2 reload
            fi
        fi
    else
        echo "Error: Apache Configuration file not found in the default location. Please insert the redirection code block by referring to the documentation manually."
    fi
}

migrate_custom_widgets() {
    # eval $invocation

    custom_widget_source="$install_dir/application/bi/dataservice/CustomWidgets"
    custom_widget_dest="$install_dir/application/app_data/bi/dataservice/"
    shapefiles_dir="$install_dir/application/app_data/bi/shapefiles"
        if [ -d "$custom_widget_source" ]; then
            [ ! -d "$custom_widget_dest" ] && mkdir -p "$custom_widget_dest"
            cp -a "$custom_widget_source" "$custom_widget_dest"
        fi
	cd "$install_dir/application/utilities/customwidgetupgrader"
	"$install_dir/dotnet/dotnet" CustomWidgetUpgrader.dll true
	cd $current_dir
}

get_bing_map_config() {
    bi_appsettings_path="$install_dir/application/bi/dataservice/appsettings.json"
    if [ -f "$bi_appsettings_path" ]; then
		if grep -qF "widget:bing_map:enable" $bi_appsettings_path; then
			# script for getting bing map enabled value is true or false
			is_bing_map_enabled1="$(grep -F -m 1 'widget:bing_map:enable' $bi_appsettings_path)"
			IFS=' '
			read -ra bingmap_enable_arr1 <<< "$is_bing_map_enabled1"
			is_bing_map_enabled2="${bingmap_enable_arr1[1]%%[[:cntrl:]]}"
			IFS=','
			read -ra bingmap_enable_arr2 <<< "$is_bing_map_enabled2"
			is_bing_map_enabled="${bingmap_enable_arr2[0]%%[[:cntrl:]]}"
			
			# script for getting bing map api key	
			bing_map_api_key1="$(grep -F -m 1 'widget:bing_map:api_key' $bi_appsettings_path)"
			IFS=' '
			read -ra bing_map_api_key_arr1 <<< "$bing_map_api_key1"
			bing_map_api_key2="${bing_map_api_key_arr1[1]%%[[:cntrl:]]}"
			IFS=','
			read -ra bing_map_api_key_arr2 <<< "$bing_map_api_key2"
			bing_map_api_key="${bing_map_api_key_arr2[0]%%[[:cntrl:]]}"
		fi
	fi
}

bing_map_migration() {
	if ! grep -qF "<Designer>" $boldbi_config_xml_location; then
		eval $invocation

		"$install_dir/dotnet/dotnet" "$install_dir/application/utilities/installutils/installutils.dll" bing_map_config_migration $is_bing_map_enabled $bing_map_api_key
	fi
}

update_oauth_fix() {
	# eval $invocation

	nginx_path="/etc/nginx"
	nginx_conf_path=""
	nginx_conf_name=""

	if $common_idp_upgrade || $common_idp_fresh; then
		nginx_conf_name="boldreports-nginx-config"
	else
		nginx_conf_name="boldbi-nginx-config"
	fi

	if [ "$distribution" = "ubuntu" ]; then
		nginx_conf_path="$nginx_path/sites-available/$nginx_conf_name"
	elif [ "$distribution" = "centos" ]; then
		nginx_conf_path="$nginx_path/conf.d/$nginx_conf_name.conf"
	fi
	
	if ! grep -qF "large_client_header_buffers" $nginx_conf_path; then
		sed -n '/proxy_buffer_size/,/large_client_header_buffers/p' boldbi-nginx-config > "update_oauth_fix.txt"
		sed -i '/client_max_body_size/r update_oauth_fix.txt' $nginx_conf_path
		rm -rf "update_oauth_fix.txt"
	fi
}

check_boldbi_directory_structure() {
	# eval $invocation
	
	if [ "$1" = "rename_installed_directory" ]; then
		if [ ! -d "$install_dir" ]; then
			say "Changing Bold BI directory structure."
			mv "$old_install_dir" "$install_dir"
			mv "$install_dir/boldbi" "$install_dir/application"
		fi
	elif [ "$1" = "remove_services" ]; then
        find "$system_dir" -type f -name "bold-*" -print0 | xargs -0 sed -i "s|Environment=export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1||g"
        systemctl daemon-reload	    
		if grep -qF "/boldbi-embedded/boldbi/" "$system_dir/bold-bi-web.service"; then
			say "Removing old service files."
			rm -rf $system_dir/bold-*
			systemctl daemon-reload
			find "$services_dir" -type f -name "*.service" -print0 | xargs -0 sed -i "s|www-data|$user|g"
			if [ "$distribution" = "centos" ]; then
			find "$services_dir" -type f -name "bold-*" -print0 | xargs -0 sed -i '/DOTNET_PRINT_TELEMETRY_MESSAGE/a Environment=LD_LIBRARY_PATH=/usr/local/lib'			
			fi
	   		if [ ! -z "$azure_insight" ]; then
				find "$services_dir" -type f -name "bold-*" -print0 | xargs -0 sed -i '/DOTNET_PRINT_TELEMETRY_MESSAGE/a Environment=APPLICATIONINSIGHTS_CONNECTION_STRING='$azure_insight''
			fi
			if [ ! -z "$lic_key" ]; then
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/DOTNET_PRINT_TELEMETRY_MESSAGE/a Environment=BOLD_SERVICES_UNLOCK_KEY='$lic_key''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_UNLOCK_KEY/a Environment=BOLD_SERVICES_HOSTING_ENVIRONMENT=k8s'
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_HOSTING_ENVIRONMENT/a Environment=BOLD_SERVICES_DB_TYPE='$db_type''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_TYPE/a Environment=BOLD_SERVICES_DB_PORT='$db_port''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_PORT/a Environment=BOLD_SERVICES_DB_HOST='$db_host''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_HOST/a Environment=BOLD_SERVICES_POSTGRESQL_MAINTENANCE_DB='$maintain_db''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_POSTGRESQL_MAINTENANCE_DB/a Environment=BOLD_SERVICES_DB_USER='$db_user''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_USER/a Environment=BOLD_SERVICES_DB_PASSWORD='$db_pwd''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_PASSWORD/a Environment=BOLD_SERVICES_DB_NAME='$db_name''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_NAME/a Environment=BOLD_SERVICES_DB_ADDITIONAL_PARAMETERS='$add_parameters''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_ADDITIONAL_PARAMETERS/a Environment=BOLD_SERVICES_USER_EMAIL='$email''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_USER_EMAIL/a Environment=BOLD_SERVICES_USER_PASSWORD='$epwd''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_USER_PASSWORD/a Environment=BOLD_SERVICES_BRANDING_MAIN_LOGO='$main_logo''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_BRANDING_MAIN_LOGO/a Environment=BOLD_SERVICES_BRANDING_LOGIN_LOGO='$login_logo''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_BRANDING_LOGIN_LOGO/a Environment=BOLD_SERVICES_BRANDING_EMAIL_LOGO='$email_logo''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_BRANDING_EMAIL_LOGO/a Environment=BOLD_SERVICES_BRANDING_FAVICON='$favicon''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_BRANDING_FAVICON/a Environment=BOLD_SERVICES_BRANDING_FOOTER_LOGO='$footer_logo''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_BRANDING_FOOTER_LOGO/a Environment=BOLD_SERVICES_SITE_NAME='$site_name''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_SITE_NAME/a Environment=BOLD_SERVICES_SITE_IDENTIFIER='$site_identifier''
    				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_SITE_IDENTIFIER/a Environment=BOLD_SERVICES_USE_SITE_IDENTIFIER='$use_siteidentifier''
			fi
			copy_service_files		
			enable_boldbi_services
		fi
	elif [ "$1" = "check_nginx_config" ]; then
		nginx_config_path=""

		if [ "$distribution" = "ubuntu" ]; then
			nginx_dir="/etc/nginx/sites-available"
			nginx_config_path="/etc/nginx/sites-available/boldbi-nginx-config"
		elif [ "$distribution" = "centos" ]; then
			nginx_dir="/etc/nginx/conf.d"
			nginx_config_path="/etc/nginx/conf.d/boldbi-nginx-config.conf"
		fi
		
		if [[ -d "$nginx_dir" || -f "$nginx_config_path" ]]; then
			if grep -qF "/boldbi-embedded/boldbi/" "$nginx_config_path"; then
				sed -i "s|/boldbi-embedded/boldbi/|/bold-services/application/|g" "$nginx_config_path"
			fi
			
			if ! grep -qF "[::]:80 default_server;" "$nginx_config_path"; then
				sed -i '/80 default_server/a\\t\tlisten       [::]:80 default_server;' "$nginx_config_path"
			fi
		fi
		
		update_oauth_fix
		validate_nginx_config
	fi
}

common_idp_integration() {
	eval $invocation

	Extracted_Dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
	cp -a "$Extracted_Dir/application/utilities/installutils" "$install_dir/application/utilities/"
 	cp -a "$Extracted_Dir/application/utilities/customwidgetupgrader" "$install_dir/application/utilities/"
        cp -a "$Extracted_Dir/dotnet/shared" "$install_dir/dotnet/"
        cp -a "$Extracted_Dir/dotnet/host" "$install_dir/dotnet/"
	say "Modifying product.json"
	"$install_dir/dotnet/dotnet" "$install_dir/application/utilities/installutils/installutils.dll" common_idp_setup $Extracted_Dir
	
	if [ -f "$Extracted_Dir/idp-Version-check.txt" ]; then
		move_idp=($(cat "$Extracted_Dir/idp-Version-check.txt"))
	fi
	
	say "Moving Bold BI files to Bold Reports installed directory."
	cp -a "$Extracted_Dir/application/bi" "$install_dir/application/"
	chown -R "$user" "$install_dir/application/bi"
	chmod +rwx "$install_dir/application/bi"
	cp -a "$Extracted_Dir/Infrastructure/License Agreement/BoldBI_License.pdf" "$install_dir/Infrastructure/License Agreement/"

	if $move_idp; then
		say "Moving Bold ID files to Bold Reports installed directory."
		rm -r $install_dir/application/idp
		rm -r $install_dir/application/utilities/adminutils
		cp -a "$Extracted_Dir/application/idp" "$install_dir/application/"
		cp -a "$Extracted_Dir/application/utilities/adminutils" "$install_dir/application/utilities/"
		chown -R "$user" "$install_dir/application/idp"
		chmod +rwx "$install_dir/application/idp"
	fi
	
	rm -r $install_dir/application/utilities/installutils
	if [ -f "$Extracted_Dir/idp-Version-check.txt" ]; then
		rm -r "$Extracted_Dir/idp-Version-check.txt"
	fi
	
	if ! $common_idp_upgrade; then
		find "services" -type f -name "*.service" -print0 | xargs -0 sed -i "s|www-data|$user|g"
		if [ "$distribution" = "centos" ]; then
			find "$services_dir" -type f -name "bold-*" -print0 | xargs -0 sed -i '/DOTNET_PRINT_TELEMETRY_MESSAGE/a Environment=LD_LIBRARY_PATH=/usr/local/lib'
		fi
		if [ ! -z "$azure_insight" ]; then
			find "$services_dir" -type f -name "bold-*" -print0 | xargs -0 sed -i '/DOTNET_PRINT_TELEMETRY_MESSAGE/a Environment=APPLICATIONINSIGHTS_CONNECTION_STRING='$azure_insight''
		fi
  		if [ ! -z "$lic_key" ]; then
			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/DOTNET_PRINT_TELEMETRY_MESSAGE/a Environment=BOLD_SERVICES_UNLOCK_KEY='$lic_key''
			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_UNLOCK_KEY/a Environment=BOLD_SERVICES_HOSTING_ENVIRONMENT=k8s'
			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_HOSTING_ENVIRONMENT/a Environment=BOLD_SERVICES_DB_TYPE='$db_type''
			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_TYPE/a Environment=BOLD_SERVICES_DB_PORT='$db_port''
			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_PORT/a Environment=BOLD_SERVICES_DB_HOST='$db_host''
			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_HOST/a Environment=BOLD_SERVICES_POSTGRESQL_MAINTENANCE_DB='$maintain_db''
			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_POSTGRESQL_MAINTENANCE_DB/a Environment=BOLD_SERVICES_DB_USER='$db_user''
			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_USER/a Environment=BOLD_SERVICES_DB_PASSWORD='$db_pwd''
			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_PASSWORD/a Environment=BOLD_SERVICES_DB_NAME='$db_name''
			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_NAME/a Environment=BOLD_SERVICES_DB_ADDITIONAL_PARAMETERS='$add_parameters''
			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_ADDITIONAL_PARAMETERS/a Environment=BOLD_SERVICES_USER_EMAIL='$email''
			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_USER_EMAIL/a Environment=BOLD_SERVICES_USER_PASSWORD='$epwd''
			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_USER_PASSWORD/a Environment=BOLD_SERVICES_BRANDING_MAIN_LOGO='$main_logo''
			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_BRANDING_MAIN_LOGO/a Environment=BOLD_SERVICES_BRANDING_LOGIN_LOGO='$login_logo''
			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_BRANDING_LOGIN_LOGO/a Environment=BOLD_SERVICES_BRANDING_EMAIL_LOGO='$email_logo''
			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_BRANDING_EMAIL_LOGO/a Environment=BOLD_SERVICES_BRANDING_FAVICON='$favicon''
			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_BRANDING_FAVICON/a Environment=BOLD_SERVICES_BRANDING_FOOTER_LOGO='$footer_logo''
			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_BRANDING_FOOTER_LOGO/a Environment=BOLD_SERVICES_SITE_NAME='$site_name''
			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_SITE_NAME/a Environment=BOLD_SERVICES_SITE_IDENTIFIER='$site_identifier''
   			find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_SITE_IDENTIFIER/a Environment=BOLD_SERVICES_USE_SITE_IDENTIFIER='$use_siteidentifier''
		fi
		say "Moving BoldBI service files"
		cp -a services/bold-bi-* "$services_dir"
		cp -a services/bold-bi-* "$system_dir"

		reports_nginx_conf_path="";
		nginx_path="/etc/nginx"

		if [ "$distribution" = "ubuntu" ]; then
			reports_nginx_conf_path="/etc/nginx/sites-available"
			reports_sites_enabled_path="/etc/nginx/sites-enabled"
		elif [ "$distribution" = "centos" ]; then
			reports_nginx_conf_path="/etc/nginx/conf.d"
		fi

		if [ "$server" = "nginx" ]; then
			if [ ! -f "$reports_nginx_conf_path/boldbi-nginx-config" ] ; then
				say "Modifying Nginx config"
					
				if [ "$distribution" = "ubuntu" ]; then
					sed -n '/# Start of bi locations/,/# End of bi locations/p' boldbi-nginx-config > "$reports_nginx_conf_path/boldbi-nginx-config"
					sed -i '$i'"$(echo 'include /etc/nginx/sites-available/boldbi-nginx-config;')" "$reports_nginx_conf_path/boldreports-nginx-config"
				elif [ "$distribution" = "centos" ]; then
					[ ! -d "$nginx_path/boldbi" ] && mkdir -p "$nginx_path/boldbi"
					sed -n '/# Start of bi locations/,/# End of bi locations/p' boldbi-nginx-config > "$nginx_path/boldbi/boldbi-nginx-config"
					sed -i '$i'"$(echo 'include /etc/nginx/boldbi/boldbi-nginx-config;')" "$reports_nginx_conf_path/boldreports-nginx-config.conf"
				fi
			fi
		fi
	fi

	update_oauth_fix
	validate_nginx_config
	
	if $common_idp_upgrade; then bing_map_migration; fi
	[ ! -d "$puppeteer_location/Linux-901912" ] && chrome_package_installation
 	migrate_custom_widgets
	if $common_idp_fresh; then enable_boldbi_services; fi
	start_boldbi_services
	systemctl  restart bold-*
	status_boldbi_services
	
}

install_boldbi() {
	eval $invocation
    local download_failed=false
    local asset_name=''
    local asset_relative_path=''
	if [[ -z "$distribution" ]]; then check_distribution; fi
	
	check_min_reqs
	if [[ "$?" != "0" ]]; then
		return 1
	fi
	
	validate_installation_type $installation_type
	if [[ "$?" != "0" ]]; then
		return 1
	fi
    if [ -z "$user" ] && [ "$installation_type" = "upgrade" ]; then upgrade_log; fi
	if [ -z "$user" ] && [ "$installation_type" = "upgrade" ]; then read_user; fi

	validate_user $user
	if [[ "$?" != "0" ]]; then
		return 1
	fi

	if [ -z "$host_url" ] && [ "$installation_type" = "upgrade" ]; then read_host_url; fi

	validate_host_url $host_url
	if [[ "$?" != "0" ]]; then
		return 1
	fi

	if is_boldreports_already_installed && is_boldbi_already_installed ; then
		####### Combination build already exists. Need to update Bold BI ######
		
		if [ "$(to_lowercase $installation_type)" = "new" ]; then
			say_err "Bold BI already present in this machine. Terminating the installation process..."
			return 1
		fi
			
		say "Bold BI already present in this machine."
		common_idp_upgrade=true
		stop_boldbi_services
		sleep 5
		check_boldbi_directory_structure "rename_installed_directory"
	
		if taking_backup; then
			get_bing_map_config
			rm -r $install_dir/application/bi
			common_idp_integration
			say "Bold BI upgraded successfully!!!"
			return 0
		else
			return 1
		fi

	elif is_boldreports_already_installed ; then
		####### Combination build setup ######
		common_idp_fresh=true
		if [ "$installation_type" = "upgrade" ]; then
			say_err "Bold BI is not present in this machine. Terminating the installation process..."
			say_err "Please do a fresh install."
			return 1
		fi
			
		while true; do
			say "Bold Reports is already installed in this machine."
			read -p "Do you wish to configure Bold BI on top of Bold Reports? [yes / no]:  " yn
			case $yn in
				[Yy]* ) common_idp_integration; break;;
				[Nn]* ) exit;;
				* ) echo "Please answer yes or no.";;
			esac
		done
		
		say "Bold BI installation completed!!!"
		return 0

	else		
		if is_boldbi_already_installed; then
			####### Bold BI Upgrade Install######
			
			if [ "$(to_lowercase $installation_type)" = "new" ]; then
				say_err "Bold BI already present in this machine. Terminating the installation process..."
				return 1
			fi
		
			say "Bold BI already present in this machine."
			
			if taking_backup; then
			
                	stop_boldbi_services
			
			    sleep 5
				
				check_boldbi_directory_structure "rename_installed_directory"
				
                		get_bing_map_config

				removing_old_files
				
				copy_files_to_installation_folder
    
    				find "$services_dir" -type f -name "*.service" -print0 | xargs -0 sed -i "s|www-data|$user|g"

    				copy_service_files
				
				chown -R "$user" "$install_dir"

				chmod +rwx "$dotnet_dir/dotnet"
				
				"$install_dir/dotnet/dotnet" "$install_dir/application/utilities/installutils/installutils.dll" upgrade_version linux
				
				update_url_in_product_json
				
				check_boldbi_directory_structure "remove_services"
				
    				migrate_custom_widgets
				
				bing_map_migration

				[ ! -d "$puppeteer_location/Linux-901912" ] && chrome_package_installation
    
    				enable_boldbi_services
				
				start_boldbi_services
				
				sleep 5
				
				status_boldbi_services

				if [ "$distribution" = "centos" ]; then
				    if [ -f "/etc/httpd/sites-available/000-default.conf" ]; then
				        server="apache"
				    elif [ -f "/etc/nginx/conf.d/boldbi-nginx-config" ]; then
				        server="nginx"
				    fi
				else
				    if [ -f "/etc/apache2/sites-available/boldbi-apache-config.conf" ]; then
				        server="apache"
				    elif [ -f "/etc/nginx/sites-available/boldbi-nginx-config" ]; then
				        server="nginx"
				    fi
				fi

				if [ "$server" = "nginx" ]; then check_boldbi_directory_structure "check_nginx_config"; fi				
				
				update_optional_lib
    
    				if [ "$server" = "nginx" ]; then
				    update_nginx_configuration
				elif [ "$server" = "apache" ]; then
				    update_apache_configuration
				fi
				say "Bold BI upgraded successfully!!!"
    
				return 0
			else
				return 1
			fi
		else
			####### Bold BI Fresh Install######
		
			if [ "$installation_type" = "upgrade" ]; then
				say_err "Bold BI is not present in this machine. Terminating the installation process..."
				say_err "Please do a fresh install."
				return 1
			fi
		
			mkdir -p "$install_dir"
			
			if [ ! -d "$backup_folder/.dotnet" ]; then
				mkdir -p "$backup_folder/.dotnet"
			fi
			
			chown -R "$user" "$backup_folder/.dotnet"
			chmod +rwx "$backup_folder/.dotnet"
			
			copy_files_to_installation_folder
			update_url_in_product_json
			find "$services_dir" -type f -name "*.service" -print0 | xargs -0 sed -i "s|www-data|$user|g"
			if [ "$distribution" = "centos" ]; then
			find "$services_dir" -type f -name "bold-*" -print0 | xargs -0 sed -i '/DOTNET_PRINT_TELEMETRY_MESSAGE/a Environment=LD_LIBRARY_PATH=/usr/local/lib'
			fi
	   		if [ ! -z "$azure_insight" ]; then
				find "$services_dir" -type f -name "bold-*" -print0 | xargs -0 sed -i '/DOTNET_PRINT_TELEMETRY_MESSAGE/a Environment=APPLICATIONINSIGHTS_CONNECTION_STRING='$azure_insight''
			fi
			if [ ! -z "$lic_key" ]; then
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/DOTNET_PRINT_TELEMETRY_MESSAGE/a Environment=BOLD_SERVICES_UNLOCK_KEY='$lic_key''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_UNLOCK_KEY/a Environment=BOLD_SERVICES_HOSTING_ENVIRONMENT=k8s'
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_HOSTING_ENVIRONMENT/a Environment=BOLD_SERVICES_DB_TYPE='$db_type''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_TYPE/a Environment=BOLD_SERVICES_DB_PORT='$db_port''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_PORT/a Environment=BOLD_SERVICES_DB_HOST='$db_host''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_HOST/a Environment=BOLD_SERVICES_POSTGRESQL_MAINTENANCE_DB='$maintain_db''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_POSTGRESQL_MAINTENANCE_DB/a Environment=BOLD_SERVICES_DB_USER='$db_user''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_USER/a Environment=BOLD_SERVICES_DB_PASSWORD='$db_pwd''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_PASSWORD/a Environment=BOLD_SERVICES_DB_NAME='$db_name''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_NAME/a Environment=BOLD_SERVICES_DB_ADDITIONAL_PARAMETERS='$add_parameters''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_DB_ADDITIONAL_PARAMETERS/a Environment=BOLD_SERVICES_USER_EMAIL='$email''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_USER_EMAIL/a Environment=BOLD_SERVICES_USER_PASSWORD='$epwd''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_USER_PASSWORD/a Environment=BOLD_SERVICES_BRANDING_MAIN_LOGO='$main_logo''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_BRANDING_MAIN_LOGO/a Environment=BOLD_SERVICES_BRANDING_LOGIN_LOGO='$login_logo''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_BRANDING_LOGIN_LOGO/a Environment=BOLD_SERVICES_BRANDING_EMAIL_LOGO='$email_logo''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_BRANDING_EMAIL_LOGO/a Environment=BOLD_SERVICES_BRANDING_FAVICON='$favicon''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_BRANDING_FAVICON/a Environment=BOLD_SERVICES_BRANDING_FOOTER_LOGO='$footer_logo''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_BRANDING_FOOTER_LOGO/a Environment=BOLD_SERVICES_SITE_NAME='$site_name''
				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_SITE_NAME/a Environment=BOLD_SERVICES_SITE_IDENTIFIER='$site_identifier''
    				find "$services_dir" -type f -name "bold-ums-web.service" -print0 | xargs -0 sed -i '/BOLD_SERVICES_SITE_IDENTIFIER/a Environment=BOLD_SERVICES_USE_SITE_IDENTIFIER='$use_siteidentifier''
			fi
			copy_service_files
			if [ ! -z "$optional_libs" ]; then
   			install_client_libraries
			fi
	
			chmod +x "$dotnet_dir/dotnet"
			
			sleep 5
			
			chrome_package_installation
			migrate_custom_widgets
			enable_boldbi_services
                        sudo chown -R "$user" "$install_dir"
			start_boldbi_services
			
			sleep 5
		
			check_config_file_generated			
			status_boldbi_services
			
			if [ "$server" = "nginx" ]; then
				configure_nginx
			elif [ "$server" = "apache" ]; then
				configure_apache
			fi
			say "Bold BI installation completed!!!"
			return 0
		fi
	fi
	
	#zip_path="$(mktemp "$temporary_file_template")"
    #say_verbose "Zip path: $zip_path"
	
	# Failures are normal in the non-legacy case for ultimately legacy downloads.
    # Do not output to stderr, since output to stderr is considered an error.
    #say "Downloading primary link $download_link"
	
	# The download function will set variables $http_code and $download_error_msg in case of failure.
    #http_code=""; download_error_msg=""
    #download "$download_link" "$zip_path" 2>&1 || download_failed=true
    #primary_path_http_code="$http_code"; primary_path_download_error_msg="$download_error_msg"
	
	#say "Extracting zip from $download_link"
	
	#extract_boldbi_package "$zip_path" "$install_dir" || return 1
}

install_boldbi
