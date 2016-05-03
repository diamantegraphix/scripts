#!/bin/sh
# site on same server
# backup saved on same server

# File listing sites to backup
# format - [site],[full path to parent folder of site]
sites="sites.txt"

server_root="/home1/diamanv1"

# Full path to directory where backups should be saved
backups_dir="$server_root/backups"

# Full path and name of log file
logfile="$backups_dir/backup_log.txt"


now="$(date +'%d_%m_%Y_%H_%M_%S')"
today="$(date +'_%Y-%m-%d')"

# If backups directorys does not exist, create it
if [ ! -d "$backups_dir" ]; then
  mkdir $backups_dir
  if [ $? -ne 0 ] ; then
    echo "Error: could not create backups directory"
    exit 1
  fi
fi

# If logfile does not exist, create it
if [ ! -f "$logfile" ]; then
  touch $logfile
fi

echo ""
echo "Backups started at $(date +'%Y-%m-%d %H:%M:%S')" #>> "$logfile"


while IFS="," read site path; do 

  if [ "${path: -1}" = "/" ]; then
    path="${path%?}"
  fi

  echo "Site: $site" #>> "$logfile"

  # If folder for site in backups directory does not exist, create it
  if [ ! -d "$backups_dir/$site" ]; then
    mkdir "$backups_dir/$site"
  fi

  # Create archive file and save in backups directory
  zipfile="$backups_dir/$site/$site$today.tar.gz"
  pushd $path
  ###tar -zcf "$zipfile" $site
  popd
  echo "Backup of directory $path/$site saved as $zipfile" #>> "$logfile"

  # delete all but 2 most recent file backups
  echo $(find "$backups_dir/$site" -maxdepth 1 -type f -name "$site*.tar.gz")

  #ls -tp $backups_dir/$site/$site*.tar.gz | tail -n +3 | xargs -I {} rm {}

  # Check if site is wordpress site
  if [ -f "$path/$site/index.php" ]; then
    check=$(grep "/wp-blog-header.php" $path/$site/index.php | cut -d "'" -f2)

    if [ -z "$check" ]; then
      # Not a WordPress site
      wp=""
    elif [ "$check" == '/wp-blog-header.php' ]; then
      # Active WordPress install is in site directory
      wp="/"
    else
      # Active WordPress install is in subdirectory of site
      wp=$(cut -d "/" -f2 <<< "$check")
      wp="/$wp/"
    fi
  else
    # Not a WordPress site
      wp=""
  fi

  # If WordPress site, get database info
  if [ -n "$wp" ]; then

    # Look for wp-config.php file
    wpconfig="$path/$site${wp}wp-config.php"
    if [ -f "$wpconfig" ]; then

      # Get database credentials
      mysql_name=$(cut -d "'" -f4 <<< $(grep DB_NAME "$wpconfig"))
      mysql_user=$(cut -d "'" -f4 <<< $(grep DB_USER "$wpconfig"))
      mysql_pass=$(cut -d "'" -f4 <<< $(grep DB_PASSWORD "$wpconfig"))
      #mysql_host=$(cut -d "'" -f4 <<< $(grep DB_HOST "$wpconfig"))

      sqlfile="$backups_dir/$site/$site$today.sql.gz"
      ###mysqldump --user="$mysql_user" --password="$mysql_pass" --default-character-set=utf8 "$mysql_name" | gzip > "$sqlfile"
      echo "Backup of database $mysql_name saved as $sqlfile" #>> "$logfile"

      # delete all but 2 most recent database backups
      ls -tp $backups_dir/$site/$site*.sql.gz | tail -n +3 | xargs -I {} rm {}

    else 
      echo "Config file wp-config.php not found"
    fi

  fi

done < $sites

exit 0
