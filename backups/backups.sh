#!/bin/sh
# Name: Backups
# Backups: Version 0.1.0
# Date: 05-04-2016
# Author: BLG
# Description: Takes backups of websites on the current server - Reads site name and path from external file. Backs up filesystem. Checks for Wordpress database, backs up database if present. Saves backups in directory specified by external config file.
# Required: backup_config.txt - config file


## TODO put these in a separate config file
# File structure root
server_home="/var/www/html"

# Backups directory, relative to server home
backups_dir="$server_home/backups"

# Full path and name of log file
logfile="$backups_dir/backups$(date +'_%Y').log"

# Full path of file with list of sites to backup; format = [site],[full path to parent folder of site]
sites="$backups_dir/sites.txt"

# Number of backups to save
i=2
## END OF CONFIG FILE



# Log time backups started
hold="##### Backups started at $(date +'%Y-%m-%d %H:%M:%S') #####"

# If backups directorys does not exist, create it
if [ ! -d "$backups_dir" ]; then
  error=$(mkdir "$backups_dir")
  if [ $? == 0 ]; then
    hold=$hold\n"Backups directory $backups_dir/ created" >> "$templog"
  else
    error="$error\nBackups failed at $(date +'%d/%m/%Y %H:%M:%S')"
    echo -e $error ### | mail -s "Backups failed: No backup directory" "bethany@diamantegraphix.com"
    rm $templog
    exit 0
  fi
fi

today="$(date +'_%Y-%m-%d')"

# Create temporary log file
templog="$backups_dir/temp$(date +'%d%m%Y%H%M%S').log"
touch "$templog"
if [ $? == 0 ]; then
  echo -e $hold >> "$templog"
else
  echo "Backups $(date +'%Y-%m-%d'): Unable to create log file at $templog" ###| mail -s "Backups error: No log file" "bethany@diamantegraphix.com"
fi 

# Add 1 to number to backups to save, starts deleting on line following number to save
i=$(($i+1))

# Get error messages from all commands in a pipeline
set -o pipefail

# Get sites name and path (parent of site directory) from file
while IFS="," read site path; do 

  # Remove trailing slash from site directory path
  if [ "${path: -1}" = "/" ]; then 
    path="${path%?}"
  fi

  # Log site name
  echo >> "$templog"
  echo "# $site #" >> "$templog"

  # Check if site directory exists
  if [ -d "$path/$site" ]; then
    echo "Filesyetem located: $path" >> "$templog" 
  else
    echo "$site backup not completed; $path/$site not found" >> "$templog"
    errors=true
    continue
  fi

  # If backups folder for site does not exist, create it
  if [ ! -d "$backups_dir/$site" ]; then
    mkdir "$backups_dir/$site" 2>>"$templog"
    if [ $? == 0 ]; then 
      echo "$backups_dir/$site directory created" >> "$templog"
    else
      echo "Filesystem backup: FAILED; Unable to create directory $site/ in $backups_dir/" >> "$templog"  
      errors=true
      continue
    fi    
  fi

  # Move to directory containing site directory 
  pushd "$path" 2>&1>/dev/null

  # Create gzipped tar archive of filesystem
  zipfile="$backups_dir/$site/$site$today$(date +'%d%m%Y%H%M%S').tar.gz"
  tar -zcf "$zipfile" $site 2>>"$templog"

  # Log results of directorty compression
  if [ $? == 0 ]; then
    echo "Filesystem backup created: $zipfile" >> "$templog"    
  else
    echo "Filesystem backup: FAILED" >> "$templog"   
    errors=true
    continue
  fi

  # Move back to initial directory
  popd 2>&1>/dev/null 

  # Delete all but 2 most recent file backups
  ls -tp $backups_dir/$site/$site*.tar.gz 2>>"$templog" | tail -n +$i | xargs -I {} rm {} 2>>"$templog"
  if [ $? != 0 ]; then
    echo "Error deleting outdated tar backups" >> "$templog"
  fi

  # Check if site is wordpress site
  if [ -f "$path/$site/index.php" ]; then
    check=$(grep "/wp-blog-header.php" "$path/$site/index.php" | cut -d "'" -f2)

    # Check if the index.php file loads WordPress
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

    # Log name of database
    echo "Database located: $mysql_name" >> "$templog"

    # Database dump
    sqlfile="$backups_dir/$site/$site$today$(date +'%d%m%Y%H%M%S').sql.gz"
    mysqldump --user="$mysql_user" --password="$mysql_pass" --default-character-set=utf8 "$mysql_name" 2>>"$templog" | gzip > "$sqlfile" 2>>"$templog"

    # Log database dump results
    if [ $? == 0 ]; then
      echo "Database backup created: $sqlfile" >> "$templog"
    else
      echo "Database backup: FAILED" >> "$templog"
      errors=true
      continue
    fi  

    # delete all but 2 most recent database backups
    ls -tp $backups_dir/$site/$site*.sql.gz 2>>"$templog" | tail -n +$i | xargs -I {} rm {} 2>>"$templog"
    if [ $? != 0 ]; then
      echo "Error deleting outdated sql backups" >> "$templog"
    fi

  # Log error if config file not found for WordPress site
  else 
    echo "Config file wp-config.php not found for WordPress site" >> "$templog"
    errors=true
  fi
done < "$sites" 2>> "$templog"

# If file with list of sites does not exist, end program and email error message
if [ $? != 0 ]; then
  echo "Error: File not found: $sites" >> "$templog"
  echo "# Backups failed at $(date +'%d/%m/%Y %H:%M:%S') #" >> "$templog"
  cat "$templog" ###| mail -s "Backups failed: No site list file" "bethany@diamantegraphix.com"
  cat "$templog" >> "$logfile"
  rm "$templog"
  exit 0
fi

# If an error occurred, note that in the log and in subject of email notification
if [ $errors ]; then
  echo >> "$templog"
  echo "*** ERRORS OCCURRED DURING THIS BACKUP ***" >> "$templog"
  echo >> "$templog"
  subject="ERRORS OCCURRED: Backups complete on $(date +'%Y-%m-%d)"
else
  subject="Backups complete on $(date +'%Y-%m-%d)"
fi

# Log time backups were completed
echo "# Backups completed at $(date +'%Y-%m-%d %H:%M:%S') #" >> "$templog"

# Email log for current backup
#cat $templog | mail -s $subject "bethany@diamantegraphix.com"

# If logfile does not exist, create it
if [ ! -f "$logfile" ]; then
  touch "$logfile"
fi

# Copy temp log to log file
cat "$templog" >> "$logfile"
echo >> $logfile
echo >> $logfile

rm "$templog"

