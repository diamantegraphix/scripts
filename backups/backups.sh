#!/bin/sh

server_root="/var/www/html"
#server_root="/home1/diamanv1"
domain_root="$server_root/public_html"
backups_dir="$server_root/backups"
logfile="$backups_dir/backup_log.txt"
host_dir=('public_html/client-hosting' 'public_html/personal-sites' 'public_html/expressionsbydiamante')
site_list="site_backups.txt"


now="$(date +'%d_%m_%Y_%H_%M_%S')"
today="$(date +'_%Y-%m-%d')"

if [ ! -d "$backups_dir" ]; then
  mkdir $backups_dir
  if [ $? -ne 0 ] ; then
    echo "Error: could not create backups directory"
    exit 1
  fi
fi

if [ ! -f "$logfile" ]; then
  touch $logfile
fi

echo ""
echo "Backups started at $(date +'%Y-%m-%d %H:%M:%S')" #>> "$logfile"
echo "Backups directory: $backups_dir" #>> "$logfile"

#site="juzsolutions"
#site="royaltreatmentpetcare"
site="torreslandscapeva"
#site="backup"
#site="thebetterscale"
#site="mysite"
#site="othersite"

echo "Website: $site" #>> "$logfile"

# Look for site in hosting directories
for d in "${host_dir[@]}"; do
  check="$server_root/$d/$site"
  if [ -d "$check" ]; then
    path="$server_root/$d"
    break 2
  else
    path=""
  fi
done

# Check if site was found
if [ -n "$path" ]; then

  # Create backups directory if it does not exist
  if [ ! -d "$backups_dir/$site" ]; then
    mkdir "$backups_dir/$site"
  fi

  # Create archive file and save in backups directory
  zipfile="$backups_dir/$site/$site$today.tar.gz"
  pushd $path
  tar -zcf "$zipfile" $site
  popd
  echo "Backup of directory $path/$site saved as $zipfile" #>> "$logfile"

  # delete all but 2 most recent file backups
  ls -tp $backups_dir/$site/$site*.tar.gz | tail -n +3 | xargs -I {} rm {}

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
      mysqldump --user="$mysql_user" --password="$mysql_pass" --default-character-set=utf8 "$mysql_name" | gzip > "$sqlfile"
      echo "Backup of database $mysql_name saved as $sqlfile" #>> "$logfile"

      # delete all but 2 most recent database backups
      ls -tp $backups_dir/$site/$site*.sql.gz | tail -n +3 | xargs -I {} rm {}

    else 
      echo "Config file wp-config.php not found"
    fi

  fi

else 
  echo "Site directory not found" #>> "$logfile"
fi

exit 0