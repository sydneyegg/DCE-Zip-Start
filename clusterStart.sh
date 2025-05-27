#!/bin/bash

me=$0
action=$1
shift
# Default app nodes directories
appnodes=${SQ_APP_NODES:-app1 app2}
# Default search nodes directories
searchnodes=${SQ_SEARCH_NODES:-es1 es2 es3}

usage() {
      base=`basename $me`
      echo ""
      echo "Usage: $base start|stop|restart|status|plugin-sync <ee-install-directory>|change-ip <new-ip>|clean-logs|clean-es"
      echo ""
      echo "Various cluster level operations to simplify operation (cluster on a single machine)"
      echo ""
      echo "  start|stop|restart|status: Same as corresponding single node operation"
      echo "  plugin-sync: Synchronizes plugins with an Enterprise Edition, where plugins can be installed from marketplace :)"
      echo "  change-ip:   Automatically change the IP address of the node in all 5 sonar.properties files"
      echo "  clean-logs:  Delete all logs files"
      echo "  clean-es:    Delete all ES indexes to trigger ES reindex"
      echo ""
}

case $action in
   start)
      nodelist="$searchnodes $appnodes"
      sleeptime=10
      ;;
   stop)
      nodelist="$appnodes $searchnodes"
      sleeptime=1
      ;;
   status)
      nodelist="$appnodes $searchnodes"
      sleeptime=0
      ;;
   restart)
      $me stop
		sleep 3
		$me start
      exit 1
      ;;
   plugin-sync)
      if [ $# = 0 ]; then
         usage
         exit 1
      fi
      eedir=$1
      nodelist="$appnodes"
      sleeptime=0
      ;;
   change-ip)
      if [ $# = 0 ]; then
         usage
         exit 1
      fi
      new_ip=$1
      nodelist="$appnodes $searchnodes"
      sleeptime=0
      ;;
   clean-logs)
      nodelist="$appnodes $searchnodes"
      sleeptime=0
      ;;
   clean-es)
      nodelist="$searchnodes"
      sleeptime=0
      ;;
   *)
      usage
      exit 1
      ;;
esac

os="linux-x86-64"
if [ `uname` = "Darwin" ]; then
   os="macosx-universal-64"
fi

# Sanity check that targeted directories exist
for node in $nodelist; do
   if [ ! -d $node ]; then
      echo "Directory $node missing, (are you in the DCE cluster root directory ?), aborting..."
      exit 2
   fi
done

wait_for_operational() {
   node_dir="$1"
   log_file="$node_dir/logs/sonar.log"
   echo "Waiting for $node_dir to become operational..."
   # Wait up to 60 seconds for log file to appear
   for i in {1..60}; do
      if [ -f "$log_file" ]; then
         break
      fi
      sleep 1
   done
   if [ ! -f "$log_file" ]; then
      echo "ERROR: Log file $log_file did not appear for $node_dir after 60 seconds."
      return 1
   fi
   # Wait up to 120 seconds for the operational message
   for i in {1..120}; do
      if grep -q "SonarQube is operational" "$log_file"; then
         echo "$node_dir is operational."
         return 0
      fi
      sleep 1
   done
   echo "ERROR: Timeout waiting for $node_dir to become operational (waited 120 seconds after log file appeared)."
   echo "Last 10 lines of $log_file:"
   tail -10 "$log_file"
   return 1
}

for node in $nodelist; do
    echo "$node $action $*"
    if [ "$action" = "plugin-sync" ]; then
       for plugin in $(ls "$eedir/extensions/plugins/"*.jar); do
          echo "Syncing $plugin"
          plugbase=$(basename "$plugin" | sed 's/plugin-.*/plugin/')
          rm "$node/extensions/plugins/$plugbase"-*
          cp "$plugin" "$node/extensions/plugins/"
       done
    elif [ "$action" = "change-ip" ]; then
       mv "$node/conf/sonar.properties" "$node/conf/sonar.properties.bak"
       sed -E -e "s/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/$new_ip/g" "$node/conf/sonar.properties.bak" > "$node/conf/sonar.properties"
    elif [ "$action" = "clean-logs" ]; then
      rm -rf "$node/logs/"*.log
    elif [ "$action" = "clean-es" ]; then
      rm -rf "$node/data/es"*.log
    else
       "$node/bin/$os/sonar.sh" $action
       if [ "$action" = "start" ]; then
          wait_for_operational "$node" || exit 3
          continue  # Skip sleep after waiting for operational
       fi
    fi
    sleep $sleeptime
done

