#!/bin/sh
# site on same server
# backup saved on same server

today="$(date +'_%Y-%m-%d')"

# File structure root
server_home="/var/www/html"

# Web service root
web_root="/var/www/html/public_html"

# Backups directory, relative to server home
backups_dir="backups"

# Full path and name of log file
logfile="$server_home/$backups_dir/backup.log"

# Full path of file with list of sites to backup; format = [site],[full path to parent folder of site]
sites="$server_home/$backups_dir/sites.txt"

# Create temporary log file
tmplog="$server_home/tmplog$(date +'%d%m%Y%H%M%S').log"
touch $tmplog

# Get error messages from all commands in a pipeline
set -o pipefail

echo "### Backups started at $(date +'%Y-%m-%d %H:%M:%S') ###" ###>> "$tmplog"

# If backups directorys does not exist, create it
if [ ! -d "$server_home/$backups_dir" ]; then
  mkdir "$server_home/$backups_dir" 2>>"$tmplog"
  if [ $? == 0 ] ; then
    echo "Backups directory $backups_dir/ created" ###>> "$tmplog"
  else
    echo "Error: could not create backups directory" ###>> "$tmplog"
    echo "Backups failed at $(date +'%d/%m/%Y %H:%M:%S') " ###>> "$tmplog"
    ###cat $tmplog | mail -s "Backups failed" "bethany@diamantegraphix.com"
    exit 0
  fi
fi

# If logfile does not exist, create it
if [ ! -f "$logfile" ]; then
  touch "$logfile" 2>>"$tmplog"
  if [ $? != 0 ] ; then errors="ERRORS: "; fi
fi

# Get sites name and path (parent of site directory) from file
while IFS="," read site path; do 

  # Remove trailing slash from site directory path
  if [ "${path: -1}" = "/" ]; then 
    path="${path%?}"
  fi
  echo "--"
  echo "# $site" ###>> "$tmplog" 
  # Check if site directory exists
  if [ -d "$path/$site" ]; then
    echo "Filesyetem: $path" ###>> "$tmplog" 
  else
    echo "$site backup not completed; $path/$site not found" ###>> "$tmplog"
    echo "--"
    errors="ERRORS: "
    continue
  fi

  # If backups folder for site does not exist, create it
  if [ ! -d "$server_home/$backups_dir/$site" ]; then
    mkdir "$server_home/$backups_dir/$site" 2>>"$tmplog"
    if [ $? == 0 ]; then 
      echo "$server_home/$backups_dir/$site directory created" ###>> "$tmplog"
    else
      errors="ERRORS: "
      continue
    fi    
  fi

  # Create archive file and save in backups directory
  zipfile="$backups_dir/$site/$site$today.tar.gz"
  pushd "$path" 2>&1>/dev/null ###2>>"$tmplog"
  ###tar -zcf "$server_home/$zipfile" $site 2>>"$tmplog"
  touch "$server_home/$zipfile"
  if [ $? == 0 ]; then
    echo "Filesystem backup created: $zipfile" ###>> "$tmplog"    
  else
    echo "Filesystem backup: ERROR" ###>> "$tmplog"   
    errors="ERRORS: "
    continue
  fi
  popd 2>&1>/dev/null ###2>>"$tmplog"

  # delete all but 2 most recent file backups
  #ls -tp $server_home/$backups_dir/$site/$site*.tar.gz 2>>"$tmplog" | tail -n +3 | xargs -I {} rm {} 2>>"$tmplog"
  find $server_home/$backups_dir/$site -maxdepth 1 -name "$site*\.tar\.gz" | tail -n +3 | xargs -I {} rm {} 2>>"$tmplog"

  # Check if site is wordpress site
  if [ -f "$path/$site/index.php" ]; then
    check=$(grep "/wp-blog-header.php" "$path/$site/index.php" | cut -d "'" -f2)

    if [ -z "$check" ]; then
      # Not a WordPress site
      continue
    elif [ "$check" == '/wp-blog-header.php' ]; then
      # Active WordPress install is in site directory
      wp=""
    else
      # Active WordPress install is in subdirectory of site directory
      wp=$(cut -d "/" -f2 <<< "$check")
      wp="$wp/"
    fi
  else
    # Not a WordPress site
    continue
  fi

  # Get database info for WordPress site
  wpconfig="$path/$site/${wp}wp-config.php"
  if [ -f "$wpconfig" ]; then

    # Get database credentials
    mysql_name=$(cut -d "'" -f4 <<< $(grep DB_NAME "$wpconfig"))
    mysql_user=$(cut -d "'" -f4 <<< $(grep DB_USER "$wpconfig"))
    mysql_pass=$(cut -d "'" -f4 <<< $(grep DB_PASSWORD "$wpconfig"))
    #mysql_host=$(cut -d "'" -f4 <<< $(grep DB_HOST "$wpconfig"))

    echo "Database: $mysql_name" ###>> "$tmplog"

    sqlfile="$backups_dir/$site/$site$today.sql.gz"
    ###mysqldump --user="$mysql_user" --password="$mysql_pass" --default-character-set=utf8 "$mysql_name" 2>>"$tmplog" | gzip > "$server_home/$sqlfile" 2>>"$tmplog"

    if [ $? == 0 ]; then
      echo "Database backup created: $sqlfile" ###>> "$tmplog"
    else
      echo "Database backup: ERROR" ###>> "$tmplog"
      errors="ERRORS: "
      continue
    fi  

    # delete all but 2 most recent database backups
    ls -tp $server_home/$backups_dir/$site/$site*.sql.gz 2>>"$tmplog" | tail -n +3 | xargs -I {} rm {} 2>>"$tmplog"

   
  else 
    echo "Config file wp-config.php not found for WordPress site" ###>> "$tmplog"
    errors="ERRORS: "
  fi
done < "$sites"

echo "--"
echo "# Backups completed at $(date +'%Y-%m-%d %H:%M:%S')" ###>> "$tmplog"

cat "$tmplog" >> "$logfile"
rm "$tmplog"

echo " " >> $logfile
