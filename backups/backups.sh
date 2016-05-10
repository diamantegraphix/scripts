#!/bin/sh
# Name: Backups
# Backups: Version 0.1.0
# Date: 05-04-2016
# Author: BLG
# Description: Takes backups of websites on the current server - Reads site name and path from external file. Backs up filesystem. Checks for Wordpress database, backs up database if present. Saves backups in directory specified by external config file.
# Required: backup_config.txt - config file, backups_sites.txt - list of sites to backup

### CONFIG FILE # TODO put these in a separate config file
# File structure root
server_home="/home/diamanv1"

# Backups directory, relative to server home
backups_dir="$server_home/backups"

# Log location
log_dir="logs"

# Full path of file with list of sites to backup; format = [site],[full path to parent folder of site]
sites="$server_home/scripts/backups_sites.txt"

# Number of backups to save
i=2

# Email to send reports
email="bethany@diamantegraphix.com"

## END OF CONFIG FILE



# Log time backups started
hold="##### Backups started at $(date +'%Y-%m-%d %H:%M:%S') #####"
hold="$hold\nBackup location: $backups_dir/"

# If file with list of sites does not exist, end program and email error message
if [ ! -f "$sites" ]; then
  hold="$hold\n\nError: File not found: $sites"
  hold="$hold\n\n# Backups failed at $(date +'%d/%m/%Y %H:%M:%S') #"
  echo -e "$hold" | mail -s "Backups Failed on $(date +'%Y-%m-%d'): No Site List File" -S from="diamanv1_backups" "$email"
  exit 0
fi

# If backups directory does not exist, create it
if [ ! -d "$backups_dir" ]; then
  error=$(mkdir "$backups_dir" 2>&1)
  if [ $? == 0 ]; then
    hold="$hold\nBackups directory $backups_dir/ created"
  else
    hold="$hold\n\n$error"
    hold="$hold\n\n# Backups failed at $(date +'%d/%m/%Y %H:%M:%S')"
    echo -e $hold | mail -s "Backups Failed on $(date +'%Y-%m-%d'): No Backup Directory" -S from="diamanv1_backups" "$email"
    exit 0
  fi
fi

# Ensure newline following last site in list, else last site is not read
lastline=$(tail -n 1 "$sites")
###if [ "$lastline" != "" ]; then
#  echo "" >> "$sites"
#fi

today="$(date +'_%Y-%m-%d')"

# Create temporary log file
templog="$backups_dir/temp$(date +'%d%m%Y%H%M%S').log"
touch "$templog" 2>/dev/null
if [ $? == 0 ]; then
  echo -e $hold >> "$templog"
else
  echo "Backups $(date +'%Y-%m-%d'): Unable to create log file at $templog" | mail -s "Backups Warning on $(date +'%Y-%m-%d'): No Log File" -S from="diamanv1_backups" "$email"
fi 

# If log directory does not exist, create it
if [ ! -d "$backups_dir/$logs_dir" ]; then
  mkdir "$backups_dir/$logs_dir" 2>>"$templog"
  if [ $? == 0 ]; then 
    echo "$backups_dir/$logs_dir directory created" >> "$templog"
  else
    echo "Unable to create directory $logs_dir/ in $backups_dir/" >> "$templog"  
    errors=true
  fi    
fi

# Log file named by year
logfile="$backups_dir/$logs_dir/backups$(date +'_%Y').log"

# Add 1 to number to backups to save, starts deleting on line following number to save
i=$(($i+1))

# Get error messages from all commands in a pipeline
set -o pipefail

# Get sites name and path (parent of site directory) from file
while IFS="," read site path name; do 
  if [ -z "$site" ]; then
    break
  fi
  if [ -z "$name" ]; then
    name="$site"
  fi

  # Remove trailing slash from site directory path
  if [ "${path: -1}" = "/" ]; then 
    path="${path%?}"
  fi

  # Log site name
  echo >> "$templog"
  echo "# $name #" >> "$templog"

  # Check if site directory exists
  if [ -d "$path/$site" ]; then
    echo "Filesyetem located: $path" >> "$templog" 
  else
    echo "$site backup not completed; $path/$site not found" >> "$templog"
    errors=true
    continue
  fi

  # If backups folder for site does not exist, create it
  if [ ! -d "$backups_dir/$name" ]; then
    mkdir "$backups_dir/$name" 2>>"$templog"
    if [ $? == 0 ]; then 
      echo "$backups_dir/$name directory created" >> "$templog"
    else
      echo "Filesystem backup: FAILED; Unable to create directory $name/ in $backups_dir/" >> "$templog"  
      errors=true
      continue
    fi    
  fi

  # Move to directory containing site directory 
  pushd "$path" 2>&1>/dev/null

  # Create gzipped tar archive of filesystem
  zipfile="$name$today.tar.gz"
  tar -zcf "$backups_dir/$name/$zipfile" $site 2>>"$templog"

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
  ls -tp $backups_dir/$name/$name*.tar.gz 2>>"$templog" | tail -n +$i | xargs -I {} rm {} 2>>"$templog"
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
    sqlfile="$name$today.sql.gz"
    mysqldump --user="$mysql_user" --password="$mysql_pass" --default-character-set=utf8 "$mysql_name" 2>>"$templog" | gzip > "$backups_dir/$name/$sqlfile" 2>>"$templog"

    # Log database dump results
    if [ $? == 0 ]; then
      echo "Database backup created: $sqlfile" >> "$templog"
    else
      echo "Database backup: FAILED" >> "$templog"
      errors=true
      continue
    fi  

    # delete all but 2 most recent database backups
    ls -tp $backups_dir/$name/$name*.sql.gz 2>>"$templog" | tail -n +$i | xargs -I {} rm {} 2>>"$templog"
    if [ $? != 0 ]; then
      echo "Error deleting outdated sql backups" >> "$templog"
    fi

  # Log error if config file not found for WordPress site
  else 
    echo "Config file wp-config.php not found for WordPress site" >> "$templog"
    errors=true
  fi
done < "$sites" 2>> "$templog"

# If an error occurred, note that in the log and in subject of email notification
if [ $errors ]; then
  echo >> "$templog"
  echo "*** ERRORS OCCURRED DURING THIS BACKUP ***" >> "$templog"
  subject="Backups Completed with Errors on $(date +'%Y-%m-%d')"
else
  subject="Backups Completed on $(date +'%Y-%m-%d')"
fi

# Log time backups were completed
echo >> "$templog"
echo "# Backups completed at $(date +'%Y-%m-%d %H:%M:%S') #" >> "$templog"

# Email log for current backup
cat "$templog" | mail -s "$subject" -S from="diamanv1_backups" "$email"

# Copy temp log to log file
cat "$templog" >> "$logfile"
echo >> "$logfile"
echo >> "$logfile"

rm "$templog"

exit 0
