#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# Dépendances recommandées pour un audit optimal :
#   apt install apache2-utils sysstat mysql-client php lsb-release coreutils procps grep awk sed
#
# - apache2-utils : pour apachectl/apache2ctl
# - sysstat        : pour iostat
# - mysql-client   : pour mysql
# - php            : pour php -i
# - lsb-release    : pour lsb_release (si besoin)
# - coreutils, procps, grep, awk, sed : outils shell standards
# =====================================================================

# Paramètres
SLOW_LOG="${SLOW_LOG:-/var/log/mysql/slow.log}"
OUT="${1:-/webserv/webserv_audit.log}"
SAMPLE="${SAMPLE:-30}"   # durée d’échantillonnage (s)

# Choix des creds: debian.cnf si dispo, sinon socket root
if [[ -f /etc/mysql/debian.cnf ]]; then
  MYSQL=(mysql --defaults-file=/etc/mysql/debian.cnf -N -B)
else
  MYSQL=(mysql -N -B)
fi

q() { "${MYSQL[@]}" -e "$1"; }

APACHECTL=$(command -v apachectl || command -v apache2ctl || true)

# Fonction: calcule et affiche les directives MPM worker effectives
compute_mpm_effective() {
  local files
  files=$($APACHECTL -t -D DUMP_INCLUDES 2>&1 | awk '{ for (i=1;i<=NF;i++) if ($i ~ /^\/etc\/apache2\//) print $i }') || true
  if [[ -z "$files" ]]; then
    files=$(printf "%s\n" \
      "/etc/apache2/apache2.conf" \
      "/etc/apache2/ports.conf" \
      $(ls -1 /etc/apache2/mods-enabled/*.conf 2>/dev/null) \
      $(ls -1 /etc/apache2/conf-enabled/*.conf 2>/dev/null) \
      $(ls -1 /etc/apache2/sites-enabled/*.conf 2>/dev/null) \
    )
  fi

  local active_mpm
  active_mpm=$($APACHECTL -t -D DUMP_RUN_CFG 2>/dev/null | awk -F ':' '/Server MPM/ {gsub(/[[:space:]]/, "", $2); print tolower($2)}') || true
  if [[ -z "$active_mpm" ]]; then
    active_mpm=$($APACHECTL -V 2>/dev/null | awk -F ':' '/Server MPM/ {gsub(/[[:space:]]/, "", $2); print tolower($2)}') || true
  fi
  [[ -z "$active_mpm" ]] && active_mpm="worker"

  local StartServers="" ServerLimit="" ThreadLimit="" ThreadsPerChild="" \
        MaxRequestWorkers="" MinSpareThreads="" MaxSpareThreads="" \
        MaxConnectionsPerChild=""

  while IFS= read -r f; do
    [[ ${f##*.} == "load" ]] && continue
    base=$(basename "$f")
    if [[ "$base" == "mpm_worker.conf" ]]; then
      while IFS='=' read -r k v; do
        case "$k" in
          StartServers) StartServers="$v" ;;
          ServerLimit) ServerLimit="$v" ;;
          ThreadLimit) ThreadLimit="$v" ;;
          ThreadsPerChild) ThreadsPerChild="$v" ;;
          MaxRequestWorkers) MaxRequestWorkers="$v" ;;
          MinSpareThreads) MinSpareThreads="$v" ;;
          MaxSpareThreads) MaxSpareThreads="$v" ;;
          MaxConnectionsPerChild) MaxConnectionsPerChild="$v" ;;
        esac
      done < <(
        awk 'BEGIN{ } /^[\t ]*#/ { next } { sub(/#.*/, ""); gsub(/^[\t ]+/, ""); if(NF>=2){ name=$1; val=$2; if(name=="MaxClients") name="MaxRequestWorkers"; if(name=="MaxRequestsPerChild") name="MaxConnectionsPerChild"; if(name ~ /^(StartServers|ServerLimit|ThreadLimit|ThreadsPerChild|MaxRequestWorkers|MinSpareThreads|MaxSpareThreads|MaxConnectionsPerChild)$/) printf("%s=%s\n", name, val); }}' "$f"
      )
    else
      while IFS='=' read -r k v; do
        case "$k" in
          StartServers) StartServers="$v" ;;
          ServerLimit) ServerLimit="$v" ;;
          ThreadLimit) ThreadLimit="$v" ;;
          ThreadsPerChild) ThreadsPerChild="$v" ;;
          MaxRequestWorkers) MaxRequestWorkers="$v" ;;
          MinSpareThreads) MinSpareThreads="$v" ;;
          MaxSpareThreads) MaxSpareThreads="$v" ;;
          MaxConnectionsPerChild) MaxConnectionsPerChild="$v" ;;
        esac
      done < <(
        sed -n '/<IfModule[[:space:]]\+"\?mpm_worker[^>]*>/,/<\/IfModule>/p' "$f" \
        | awk 'BEGIN{} /^[\t ]*#/ { next } { sub(/#.*/, ""); gsub(/^[\t ]+/, ""); if(NF>=2){ name=$1; val=$2; if(name=="MaxClients") name="MaxRequestWorkers"; if(name=="MaxRequestsPerChild") name="MaxConnectionsPerChild"; if(name ~ /^(StartServers|ServerLimit|ThreadLimit|ThreadsPerChild|MaxRequestWorkers|MinSpareThreads|MaxSpareThreads|MaxConnectionsPerChild)$/) printf("%s=%s\n", name, val); }}'
      )
    fi
  done <<< "$files"

  echo "== MPM worker effectif (après overrides par ordre d'include) =="
  echo "StartServers: ${StartServers:-N/A}"
  echo "ServerLimit: ${ServerLimit:-N/A}"
  echo "ThreadLimit: ${ThreadLimit:-N/A}"
  echo "ThreadsPerChild: ${ThreadsPerChild:-N/A}"
  echo "MaxRequestWorkers: ${MaxRequestWorkers:-N/A}"
  echo "MinSpareThreads: ${MinSpareThreads:-N/A}"
  echo "MaxSpareThreads: ${MaxSpareThreads:-N/A}"
  echo "MaxConnectionsPerChild: ${MaxConnectionsPerChild:-N/A}"
}
{
  echo "== Informations système =="
  echo -n "Debian version: "; cat /etc/debian_version 2>/dev/null || echo "(inconnu)"
  echo -n "Kernel: "; uname -a
  echo -n "Uptime: "; uptime -p
  echo -n "CPU: "; grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs
  echo -n "Cores: "; grep -c '^processor' /proc/cpuinfo
  echo -n "RAM total: "; free -h | awk '/Mem:/ {print $2}'
  echo -n "RAM disponible: "; free -h | awk '/Mem:/ {print $7}'
  echo
  echo "[free -h] Vue synthétique de la mémoire (total/used/free/shared/buffers/cache/available) :"
  free -h
  echo
  echo "[vmstat] Statistiques système (mémoire, swap, IO, CPU) sur 2 intervalles :"
  if command -v vmstat >/dev/null 2>&1; then
    vmstat 2 2
  else
    echo "(commande vmstat non trouvée)"
  fi
  echo "(Colonne 'si/so' = swap in/out, 'us' = user CPU, 'sy' = system CPU, 'id' = idle, 'wa' = IO wait)"
  # Swap: gérer les systèmes sans swap en lisant /proc/meminfo
  SWAP_KB_TOTAL=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
  SWAP_KB_FREE=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo)
  if [[ -n "$SWAP_KB_TOTAL" && "$SWAP_KB_TOTAL" -gt 0 && -n "$SWAP_KB_FREE" ]]; then
    SWAP_TOTAL_MB=$((SWAP_KB_TOTAL/1024))
    SWAP_USED_MB=$(((SWAP_KB_TOTAL-SWAP_KB_FREE)/1024))
    echo "Swap total: ${SWAP_TOTAL_MB}Mi"
    echo "Swap utilisé: ${SWAP_USED_MB}Mi"
  else
    echo "Swap total: 0Mi"
    echo "Swap utilisé: 0Mi"
  fi
  echo "Load average: $(cat /proc/loadavg)"
  echo -n "Disques: "; df -h --total | awk '/total/ {print $2 " used:" $3 ", free:" $4}'
  echo -n "IO (top 5): "; /usr/bin/iostat -dx 1 2 | awk 'NR==1{next} NR==2{next} /Device/ {print "[Device] r/s w/s util%"} /^[a-z]/ {print $1, $4, $5, $NF}' | head -6 2>/dev/null || echo "(commande iostat non trouvée)"
  echo

  echo "== Apache2 =="
  echo -n "Apache version: "; $APACHECTL -v 2>/dev/null | grep 'Server version' || apache2 -v 2>/dev/null | grep 'Server version' || echo "(inconnu)"
  echo -n "MPM: "; $APACHECTL -V 2>/dev/null | grep -i mpm || echo "(inconnu)"
  echo -n "Config principale: "; $APACHECTL -V 2>/dev/null | grep SERVER_CONFIG_FILE | cut -d'"' -f2 || echo "(inconnu)"
  echo
  echo "== Modules Apache actifs =="
  if [[ -n "$APACHECTL" ]]; then
    $APACHECTL -M 2>/dev/null || echo "(commande apachectl -M échouée)"
  else
    echo "(apachectl non trouvé, impossible de lister les modules)"
  fi
  echo

  echo "== PHP =="
  echo -n "PHP version: "; php -v | head -1
  echo -n "PHP SAPI: "; php -i | grep '^Server API' | awk -F'=> ' '{print $2}'
  echo -n "PHP-FPM pools: "; ls /etc/php/*/fpm/pool.d/*.conf 2>/dev/null | wc -l
  echo -n "php.ini utilisé: "; php -i | grep 'Loaded Configuration File' | awk -F'=> ' '{print $2}'
  echo

  echo "== PHP info (FPM simulé via CLI) =="
  if command -v php >/dev/null 2>&1; then
    FPM_INI=$(ls /etc/php/*/fpm/php.ini 2>/dev/null | head -1)
    if [[ -n "$FPM_INI" && -r "$FPM_INI" ]]; then
      FPM_DIR=$(dirname "$FPM_INI")
      FPM_SCAN_DIR="${FPM_DIR}/conf.d"
      echo "[source] php -i avec PHPRC=${FPM_DIR} et PHP_INI_SCAN_DIR=${FPM_SCAN_DIR} (SAPI=CLI, INI=FPM)"
      PHPRC="$FPM_DIR" PHP_INI_SCAN_DIR="$FPM_SCAN_DIR" php -i
    else
      echo "(php.ini FPM introuvable; fallback sur php -i CLI)"
      php -i
    fi
  else
    echo "(php non trouvé)"
  fi
  echo

  echo "== PHP-FPM (pools: configuration clé) =="
  POOL_FILES=$(ls /etc/php/*/fpm/pool.d/*.conf 2>/dev/null || true)
  if [[ -n "$POOL_FILES" ]]; then
    for f in $POOL_FILES; do
      POOL_NAME=$(awk -F'[][]' '/^\[.*\]/{print $2; exit}' "$f" 2>/dev/null)
      [[ -z "$POOL_NAME" ]] && POOL_NAME=$(basename "$f")
      echo "-- Pool: $POOL_NAME ($f)"
      awk '
        /^[\t ]*#/ { next }
        { sub(/#.*/, ""); gsub(/^[\t ]+/, ""); }
        # Paramètres pm et associés, au format "name = value"
        /^(pm|pm\.max_children|pm\.start_servers|pm\.min_spare_servers|pm\.max_spare_servers|pm\.process_idle_timeout|pm\.max_requests|request_terminate_timeout|catch_workers_output|rlimit_files|rlimit_core)[[:space:]]*=/ {
          split($0, a, "=");
          name=a[1]; val=a[2]; gsub(/[\t ]+$/, "", name); gsub(/^[\t ]+/, "", val);
          printf "%s=%s\n", name, val
        }
        # php_admin_value/flag et php_value/flag
        /^php_admin_(value|flag)\[/ {
          match($0, /php_admin_(value|flag)\[([^\]]+)\][[:space:]]*=[[:space:]]*(.*)/, m);
          if (m[2] != "") { printf "php_admin:%s=%s\n", m[2], m[3] }
        }
        /^php_(value|flag)\[/ {
          match($0, /php_(value|flag)\[([^\]]+)\][[:space:]]*=[[:space:]]*(.*)/, m);
          if (m[2] != "") { printf "php_value:%s=%s\n", m[2], m[3] }
        }
      ' "$f"
      echo
    done
  else
    echo "(Aucun fichier de pool FPM trouvé)"
  fi
  echo -n "php.ini FPM utilisé: "; ls /etc/php/*/fpm/php.ini 2>/dev/null || echo "(introuvable)"
  echo

  echo "== PHP-FPM opcache (config FPM) =="
  OP_INIS=$(ls /etc/php/*/fpm/conf.d/*.ini /etc/php/*/fpm/php.ini 2>/dev/null || true)
  if [[ -n "$OP_INIS" ]]; then
    grep -H -E '^(zend_extension=.*opcache|opcache\.)' $OP_INIS 2>/dev/null | sed -n '1,50p'
    echo "[i] Liste tronquée à 50 lignes. Ajustez si besoin."
  else
    echo "(Aucun fichier ini FPM opcache détecté)"
  fi
  echo

  echo "== PHP-FPM processus (mémoire agrégée) =="
  read -r PCOUNT PRSS_KB <<<"$(ps -eo rss,comm | awk '/php-fpm/{c++; sum+=$1} END{print c, sum+0}')"
  if [[ -n "$PCOUNT" && "$PCOUNT" -gt 0 ]]; then
    TOT_MB=$(awk -v x="$PRSS_KB" 'BEGIN{printf "%.1f", x/1024}')
    AVG_MB=$(awk -v x="$PRSS_KB" -v c="$PCOUNT" 'BEGIN{printf "%.1f", (c>0?x/1024/c:0)}')
    echo "Processus php-fpm: $PCOUNT | RSS total ~ ${TOT_MB} MiB | RSS moyen ~ ${AVG_MB} MiB"
    ps -eo pid,comm,rss --sort=-rss | awk '/php-fpm/{printf "%s %s %.1f MiB\n", $1, $2, $3/1024}' | head -5
  else
    echo "(Aucun processus php-fpm détecté)"
  fi
  echo

  echo "== MariaDB/MySQL =="
  echo -n "MySQL version: "; q "SELECT VERSION();"
  echo
  echo "==== Server Audit $(date -Iseconds) on $(hostname) ===="
  echo

    echo "== Variables clés (MySQL) =="
    q "SELECT 'version', VERSION();"
    q "SHOW VARIABLES WHERE Variable_name IN
      ('thread_handling','thread_pool_size','innodb_buffer_pool_size','innodb_log_file_size','innodb_log_files_in_group',
      'innodb_flush_method','innodb_flush_neighbors','max_connections','table_open_cache',
      'open_files_limit','tmp_table_size','max_heap_table_size','key_buffer_size','query_cache_size','join_buffer_size','sort_buffer_size','read_buffer_size','read_rnd_buffer_size','innodb_log_buffer_size','innodb_buffer_pool_instances','performance_schema','log_error',
      'wait_timeout','interactive_timeout','max_allowed_packet','sql_mode','default_storage_engine','tmpdir',
      'slow_query_log','slow_query_log_file','long_query_time','log_bin','binlog_format','sync_binlog','innodb_flush_log_at_trx_commit');"

  echo "== Charge système (CPU/RAM/IO) =="
  echo -n "Uptime: "; uptime
  echo -n "Charge CPU (top 5): "; ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -6
  echo -n "Charge RAM (top 5): "; ps -eo pid,comm,%cpu,%mem --sort=-%mem | head -6
  echo -n "Utilisation disque: "; df -h --total | grep total
  echo -n "IO (iostat): "; /usr/bin/iostat -dx 1 2 | awk 'NR==1{next} NR==2{next} /Device/ {print "[Device] r/s w/s util%"} /^[a-z]/ {print $1, $4, $5, $NF}' | head -6 2>/dev/null || echo "(commande iostat non trouvée)"
  echo

  echo "== Estimation mémoire MySQL (hors OS) =="
  q "SELECT CONCAT(ROUND((@@innodb_buffer_pool_size+@@key_buffer_size+@@query_cache_size+@@innodb_log_buffer_size)/POWER(1024,2),1),' Mo') AS 'Buffer principal',
            CONCAT(ROUND((@@max_connections*(@@sort_buffer_size+@@read_buffer_size+@@read_rnd_buffer_size+@@join_buffer_size))/POWER(1024,2),1),' Mo') AS 'Buffer par connexion (max)',
            CONCAT(ROUND(((@@innodb_buffer_pool_size+@@key_buffer_size+@@query_cache_size+@@innodb_log_buffer_size)+(@@max_connections*(@@sort_buffer_size+@@read_buffer_size+@@read_rnd_buffer_size+@@join_buffer_size)))/POWER(1024,3),2),' Go') AS 'Total théorique max';"
  echo

  echo "== Statuts de base =="
  q "SHOW GLOBAL STATUS WHERE Variable_name IN
     ('Uptime','Threads_connected','Threads_running','Max_used_connections',
      'Questions','Queries','Com_select','Com_insert','Com_update','Com_delete',
      'Created_tmp_tables','Created_tmp_disk_tables','Sort_merge_passes','Innodb_buffer_pool_pages_free','Innodb_buffer_pool_pages_total','Innodb_buffer_pool_pages_dirty','Innodb_buffer_pool_pages_data');"
  echo

  echo "== Buffer Pool Hit Ratio (robuste) =="
  q "SELECT IF(req=0 OR reads_cnt>req OR uptime<300, 'N/A', ROUND(100*(1 - (reads_cnt/req)), 2)) AS bp_hit_ratio_pct
FROM (
  SELECT
    SUM(CASE WHEN VARIABLE_NAME='Innodb_buffer_pool_read_requests' THEN VARIABLE_VALUE ELSE 0 END) AS req,
    SUM(CASE WHEN VARIABLE_NAME='Innodb_buffer_pool_reads'          THEN VARIABLE_VALUE ELSE 0 END) AS reads_cnt,
    MAX(CASE WHEN VARIABLE_NAME='Uptime'                           THEN VARIABLE_VALUE ELSE 0 END) AS uptime
  FROM information_schema.GLOBAL_STATUS
) s;"
  echo

  # == Échantillonnage ${SAMPLE}s: QPS/TPS/Threads_running ==
  read -r Q0 S0 I0 U0 D0 TR0 <<<"$(
    "${MYSQL[@]}" -N -B -e "SHOW GLOBAL STATUS WHERE Variable_name IN ('Queries','Com_select','Com_insert','Com_update','Com_delete','Threads_running');" \
    | awk 'NR>0{a[$1]=$2} END{print a["Queries"],a["Com_select"],a["Com_insert"],a["Com_update"],a["Com_delete"],a["Threads_running"]}'
  )" || true

  sleep "${SAMPLE}"

  read -r Q1 S1 I1 U1 D1 TR1 <<<"$(
    "${MYSQL[@]}" -N -B -e "SHOW GLOBAL STATUS WHERE Variable_name IN ('Queries','Com_select','Com_insert','Com_update','Com_delete','Threads_running');" \
    | awk 'NR>0{a[$1]=$2} END{print a["Queries"],a["Com_select"],a["Com_insert"],a["Com_update"],a["Com_delete"],a["Threads_running"]}'
  )" || true

  dq=$((Q1-Q0)); ds=$((S1-S0)); di=$((I1-I0)); du=$((U1-U0)); dd=$((D1-D0))
  qps=$(awk -v x="${dq}" -v t="${SAMPLE}" 'BEGIN{printf "%.2f", (t>0?x/t:0)}')
  sps=$(awk -v x="${ds}" -v t="${SAMPLE}" 'BEGIN{printf "%.2f", (t>0?x/t:0)}')
  tps=$(awk -v x="$((di+du+dd))" -v t="${SAMPLE}" 'BEGIN{printf "%.2f", (t>0?x/t:0)}')
  echo "QPS=${qps} | SELECT/s=${sps} | TPS(ins+upd+del)/s=${tps} | Threads_running_end=${TR1}"

  echo

  echo "== InnoDB STATUS (sections principales, 200 premières lignes) =="
  "${MYSQL[@]}" -e "SHOW ENGINE INNODB STATUS\G" | sed -n '1,200p'
  echo

  echo "== Top 10 tables volumineuses (InnoDB/MyISAM) =="
  q "SELECT table_schema, table_name, engine, ROUND(data_length/1024/1024,1) AS data_MB, ROUND(index_length/1024/1024,1) AS idx_MB, ROUND((data_length+index_length)/1024/1024,1) AS total_MB FROM information_schema.tables WHERE table_schema NOT IN ('mysql','information_schema','performance_schema','sys') ORDER BY (data_length+index_length) DESC LIMIT 10;"
  echo

    echo "== Profiling SQL (slow_log ou Performance Schema) =="
  PS_STATE=$(q "SHOW VARIABLES LIKE 'performance_schema';" | awk '{print tolower($2)}' | tr -d '\r' || true)
  SLOW_ON=$(q "SHOW VARIABLES LIKE 'slow_query_log';" | awk '{print tolower($2)}' | tr -d '\r' || true)
  SLOW_FILE=$(q "SHOW VARIABLES LIKE 'slow_query_log_file';" | awk '{print $2}' | tr -d '\r' || true)

  if [[ "$SLOW_ON" == "on" && -n "$SLOW_FILE" && -r "$SLOW_FILE" ]]; then
    echo "-- Analyse slow query log: $SLOW_FILE --"
    # Prefer mariadb-dumpslow (MariaDB>=10.5) then mysqldumpslow, fallback to awk
    DUMPSLOW_CMD=""
    if command -v mariadb-dumpslow >/dev/null 2>&1; then
      DUMPSLOW_CMD="mariadb-dumpslow"
    elif command -v mysqldumpslow >/dev/null 2>&1; then
      DUMPSLOW_CMD="mysqldumpslow"
    fi

    if [[ -n "$DUMPSLOW_CMD" ]]; then
      echo "-- Top 20 par temps total ($DUMPSLOW_CMD -s t) --"
      "$DUMPSLOW_CMD" -s t -t 20 "$SLOW_FILE" 2>/dev/null || true
      echo
      echo "-- Top 20 par occurrences ($DUMPSLOW_CMD -s c) --"
      "$DUMPSLOW_CMD" -s c -t 20 "$SLOW_FILE" 2>/dev/null || true
    else
      echo "[i] ni mariadb-dumpslow ni mysqldumpslow trouvés, utilisation d'un résumé awk (approx.)"
      awk '
        /^# Query_time:/ { qt=$3; q=""; getline; q=$0; gsub(/^[ \t]+|[ \t]+$/, "", q); cnt[q]+=1; sum[q]+=qt; if(max[q]=="" || qt+0>max[q]) max[q]=qt }
        END{ printf("count avg_qt max_qt query\n"); for (k in cnt) printf("%d %.6f %.6f %s\n", cnt[k], sum[k]/cnt[k], max[k], k) }'
        "$SLOW_FILE" | sort -nr | head -n 20 || true
    fi
    echo
  elif [[ "$PS_STATE" == "on" || "$PS_STATE" == "1" ]]; then
    echo "-- Top requêtes par temps total (digest) --"
      q "SELECT DIGEST,
      MIN(LEFT(DIGEST_TEXT, 300)) AS DIGEST_TEXT,
      SUM(COUNT_STAR) AS execs,
      ROUND(SUM(SUM_TIMER_WAIT)/1e12, 2) AS total_s,
      ROUND((SUM(SUM_TIMER_WAIT)/SUM(COUNT_STAR))/1e9, 2) AS avg_ms
    FROM performance_schema.events_statements_summary_by_digest
    GROUP BY DIGEST
    ORDER BY SUM(SUM_TIMER_WAIT) DESC
    LIMIT 20;"
    echo
    echo "-- Requêtes générant le plus de tables temporaires --"
      q "SELECT DIGEST,
      MIN(LEFT(DIGEST_TEXT, 300)) AS DIGEST_TEXT,
      SUM(SUM_CREATED_TMP_TABLES)        AS tmp_tables,
      SUM(SUM_CREATED_TMP_DISK_TABLES)   AS tmp_disk_tables,
      SUM(SUM_SORT_ROWS)                 AS sort_rows,
      SUM(SUM_SORT_MERGE_PASSES)         AS sort_merges
    FROM performance_schema.events_statements_summary_by_digest
    GROUP BY DIGEST
    ORDER BY tmp_tables DESC
    LIMIT 20;"
    echo
    echo "-- Requêtes avec le plus de merges de tri --"
      q "SELECT DIGEST,
      MIN(LEFT(DIGEST_TEXT, 300)) AS DIGEST_TEXT,
      SUM(SUM_SORT_MERGE_PASSES) AS sort_merges,
      SUM(SUM_SORT_ROWS)         AS sort_rows
    FROM performance_schema.events_statements_summary_by_digest
    GROUP BY DIGEST
    ORDER BY sort_merges DESC
    LIMIT 20;"
    echo
    SYS_OK=$(q "SELECT IF(EXISTS(SELECT 1 FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='sys'), 'yes','no');" | tr -d '\r' || true)
    if [[ "$SYS_OK" == "yes" ]]; then
      echo "-- Index inutilisés (sys.schema_unused_indexes) --"
      q "SELECT object_schema, object_name, index_name
         FROM sys.schema_unused_indexes
         ORDER BY object_schema, object_name
         LIMIT 50;"
      echo
      echo "-- Index redondants (sys.schema_redundant_indexes) --"
      COLS=$(q "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='sys' AND TABLE_NAME='schema_redundant_indexes' ORDER BY ORDINAL_POSITION;" | tr -d '\r' || true)
      if printf "%s\n" "$COLS" | grep -q '^duplicate_of_index_name$'; then
        q "SELECT table_schema, table_name, redundant_index_name, redundant_index_columns, duplicate_of_index_name
          FROM sys.schema_redundant_indexes
          ORDER BY table_schema, table_name
          LIMIT 50;"
      elif printf "%s\n" "$COLS" | grep -q '^sql_drop_index$'; then
        q "SELECT table_schema, table_name, redundant_index_name, redundant_index_columns, sql_drop_index
          FROM sys.schema_redundant_indexes
          ORDER BY table_schema, table_name
          LIMIT 50;"
      else
        q "SELECT table_schema, table_name, redundant_index_name, redundant_index_columns
          FROM sys.schema_redundant_indexes
          ORDER BY table_schema, table_name
          LIMIT 50;"
      fi
      echo
      echo "-- Tables les plus lues (sys.*schema_table_statistics* ) --"
      SYS_TBL=$(q "SELECT CASE
          WHEN EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA='sys' AND TABLE_NAME='schema_table_statistics_with_buffer') THEN 'schema_table_statistics_with_buffer'
          WHEN EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA='sys' AND TABLE_NAME='schema_table_statistics') THEN 'schema_table_statistics'
          ELSE '' END;" | tr -d '\r' || true)
      if [[ -n "$SYS_TBL" ]]; then
        COLS=$(q "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='sys' AND TABLE_NAME='${SYS_TBL}' ORDER BY ORDINAL_POSITION;" | tr -d '\r' || true)
        READ_COL=""
        if printf "%s\n" "$COLS" | grep -q '^rows_read$'; then
          READ_COL="rows_read"
        elif printf "%s\n" "$COLS" | grep -q '^rows_fetched$'; then
          READ_COL="rows_fetched"
        elif printf "%s\n" "$COLS" | grep -q '^io_read$'; then
          READ_COL="io_read"
        fi
        CHANGED_EXPR=""
        if printf "%s\n" "$COLS" | grep -q '^rows_changed$'; then
          CHANGED_EXPR="rows_changed"
        elif printf "%s\n" "$COLS" | grep -q '^rows_inserted$' && printf "%s\n" "$COLS" | grep -q '^rows_updated$' && printf "%s\n" "$COLS" | grep -q '^rows_deleted$'; then
          CHANGED_EXPR="(rows_inserted+rows_updated+rows_deleted) AS rows_changed"
        fi
        SQL_SEL="SELECT table_schema, table_name"
        if [[ -n "$READ_COL" ]]; then SQL_SEL+=" , $READ_COL"; fi
        if [[ -n "$CHANGED_EXPR" ]]; then SQL_SEL+=" , $CHANGED_EXPR"; fi
        SQL_FROM=" FROM sys.$SYS_TBL"
        if [[ -n "$READ_COL" ]]; then
          SQL_ORDER=" ORDER BY $READ_COL DESC"
        else
          SQL_ORDER=" ORDER BY table_name"
        fi
        SQL_LIMIT=" LIMIT 20;"
        q "$SQL_SEL$SQL_FROM$SQL_ORDER$SQL_LIMIT"
      else
        echo "[i] Aucune vue sys.schema_table_statistics* trouvée. Impossible d'afficher les tables les plus lues."
      fi
    else
      echo "[i] Schéma 'sys' absent. Pour analyses avancées, installez le sys schema (souvent fourni avec MariaDB/MySQL)."
    fi
  else
    echo "[i] Ni slow_log fichier ni Performance Schema disponibles pour le profiling SQL. Activez l'un des deux."
  fi
  echo

  # Capacité totale des redo logs (datadir)
  DATADIR=$(q "SHOW VARIABLES LIKE 'datadir';" | awk '{print $2}')
  if [[ -n "$DATADIR" ]]; then
    echo
    echo "== Redo log (capacité totale via datadir) =="
    ls -lh "$DATADIR"/ib_logfile* 2>/dev/null || echo "(ib_logfile* non trouvés dans $DATADIR)"
    TOTAL_BYTES=$(ls -l "$DATADIR"/ib_logfile* 2>/dev/null | awk '{sum+=$5} END{print sum+0}')
    FILES_CNT=$(ls -l "$DATADIR"/ib_logfile* 2>/dev/null | wc -l)
    if [[ -n "$TOTAL_BYTES" && "$FILES_CNT" -gt 0 ]]; then
      TOTAL_GIB=$(awk -v b="$TOTAL_BYTES" 'BEGIN{printf "%.2f", b/1024/1024/1024}')
      if [[ "$FILES_CNT" -eq 1 ]]; then FSUFFIX="fichier"; else FSUFFIX="fichiers"; fi
      echo "Redo total: ${TOTAL_GIB} GiB (${FILES_CNT} ${FSUFFIX})"
    fi
  fi

  # Reconstruction Apache: includes et MPM worker effectif
  if [[ -n "$APACHECTL" ]]; then
    echo
    echo "== Apache includes (ordre des fichiers) =="
    APACHE_INCLUDES=$($APACHECTL -t -D DUMP_INCLUDES 2>&1)
    echo "$APACHE_INCLUDES" | awk '/\) \/etc\//{print $0}'

    echo
    compute_mpm_effective
    echo
    echo "== Vhosts et logs d'accès =="
    AP_SITES=$($APACHECTL -S 2>/dev/null || true)
    if [[ -n "$AP_SITES" ]]; then
      echo "-- Vhosts détectés (443/80) --"
      awk 'match($0, /port[[:space:]]+([0-9]+)[[:space:]]+namevhost[[:space:]]+([^[:space:]]+)/, m){printf("port %s %s\n", m[1], m[2])}' <<<"$AP_SITES" | sort -u
    else
      echo "(apachectl -S non disponible)"
    fi

    # Collecte des fichiers d'accès potentiels
    declare -a CAND_LOGS=()
    while IFS= read -r p; do [[ -n "$p" ]] && CAND_LOGS+=("$p"); done < <(grep -hE "^\s*CustomLog\s+(/[^\s]+)" -o /etc/apache2/sites-enabled/*.conf 2>/dev/null | awk '{print $2}' | sed 's/"//g')
    for p in /var/log/apache2/*access*.log /var/log/apache2/other-vhosts-access.log /var/log/apache2/access.log; do [[ -f "$p" ]] && CAND_LOGS+=("$p"); done
    # Dédupliquer
    mapfile -t CAND_LOGS < <(printf "%s\n" "${CAND_LOGS[@]}" | awk '!seen[$0]++')
    BEST_LOG=""; BEST_SIZE=0
    for p in "${CAND_LOGS[@]}"; do
      [[ -r "$p" ]] || continue
      sz=$(stat -c %s "$p" 2>/dev/null || echo 0)
      if [[ "$sz" =~ ^[0-9]+$ ]] && (( sz > BEST_SIZE )); then
        BEST_SIZE=$sz; BEST_LOG="$p"
      fi
    done
    if [[ -n "$BEST_LOG" ]]; then
      echo "-- Log d'accès sélectionné: $BEST_LOG (taille: $BEST_SIZE octets) --"
    else
      echo "[i] Aucun log d'accès lisible trouvé."
    fi

    # Mapping CustomLog -> ServerName/ServerAlias (pour logs par vhost)
    declare -A LOG2DOMAIN
    for cf in /etc/apache2/sites-enabled/*.conf; do
      [[ -r "$cf" ]] || continue
      awk '
        BEGIN{dom=""}
        /^[\t ]*#/ {next}
        /<VirtualHost[[:space:]]/ {dom=""}
        match($0, /^[\t ]*ServerName[[:space:]]+([^\t ]+)/, m){dom=m[1]}
        match($0, /^[\t ]*ServerAlias[[:space:]]+([^\t ]+)/, m){ if(dom=="") dom=m[1] }
        match($0, /^[\t ]*CustomLog[[:space:]]+([^\t ]+)/, m){ if(dom!=""){ gsub(/"/, "", m[1]); printf("%s\t%s\n", m[1], dom) } }
      ' "$cf" 2>/dev/null | while IFS=$'\t' read -r lp dm; do LOG2DOMAIN["$lp"]="$dm"; done
    done

    # Choix du domaine et de la page la plus demandée à partir du log sélectionné
    CHOSEN_DOMAIN=""; CHOSEN_PATH=""
    if [[ -n "$BEST_LOG" ]]; then
      # 1) other-vhosts-access.log: domaine dans la 1ère colonne (vhost:port)
      CHOSEN_DOMAIN=$(awk 'match($1, /^([^:]+):/, m){dom=m[1]; cnt[dom]++} END{max=0; d=""; for (k in cnt){if(cnt[k]>max){max=cnt[k]; d=k}} if(d!=""){print d}}' "$BEST_LOG" 2>/dev/null || true)
      # 2) Si non trouvé, utiliser mapping CustomLog -> ServerName
      if [[ -z "$CHOSEN_DOMAIN" && -n "${LOG2DOMAIN[$BEST_LOG]:-}" ]]; then
        CHOSEN_DOMAIN="${LOG2DOMAIN[$BEST_LOG]}"
      fi
      # Heuristique supplémentaire: si le mapping CustomLog n'existe pas,
      # tenter de déduire le vhost depuis le nom du fichier de log ou les fichiers de site.
      if [[ -z "$CHOSEN_DOMAIN" ]]; then
        base=$(basename "$BEST_LOG")
        name_no_ext=${base%%.*}
        # 1) chercher un fichier de site contenant ce fragment
        cfg=$(ls /etc/apache2/sites-enabled/*${name_no_ext}* 2>/dev/null | head -1 || true)
        if [[ -n "$cfg" ]]; then
          CHOSEN_DOMAIN=$(awk '/^[[:space:]]*ServerName[[:space:]]+/ {print $2; exit}' "$cfg" 2>/dev/null || true)
        fi
        # 2) chercher dans tous les sites un ServerName/ServerAlias contenant le fragment
        if [[ -z "$CHOSEN_DOMAIN" ]]; then
          CHOSEN_DOMAIN=$(grep -hR "${name_no_ext}" /etc/apache2/sites-enabled 2>/dev/null | awk '/ServerName|ServerAlias/ {print $2}' | head -1 || true)
        fi
        # 3) tenter d'extraire le host depuis des URLs absolues présentes dans le log (rare)
        if [[ -z "$CHOSEN_DOMAIN" ]]; then
          CHOSEN_DOMAIN=$(awk 'match($0, /https?:\/\/([^\/:\"]+)/, m){cnt[m[1]]++} END{mx=0; d=""; for(k in cnt) if(cnt[k]>mx){mx=cnt[k]; d=k} if(d!="") print d}' "$BEST_LOG" 2>/dev/null || true)
        fi
      fi
      # Page la plus demandée (indépendamment du domaine si per-vhost)
      # Filtrer les assets statiques pour obtenir une page applicative représentative
      SKIP_STATIC_RE=${SKIP_STATIC_RE:-"\.(css|js|png|jpg|jpeg|gif|ico|woff2?|svg|map|ttf|eot|otf|mp4|webp)$"}
      CHOSEN_PATH=$(awk -v skip_re="$SKIP_STATIC_RE" '
        { if(match($0, /"(GET|POST|HEAD|OPTIONS|PUT|DELETE)[[:space:]]+([^[:space:]]+)/, r)) { path=r[2]; sub(/\?.*/, "", path); lp=tolower(path); if(lp ~ skip_re) next; cnt[path]++ } }
        END{max=0; p=""; for(k in cnt){ if(cnt[k]>max){max=cnt[k]; p=k} } if(p!=""){print p}}
      ' "$BEST_LOG" 2>/dev/null || true)
      if [[ -n "$CHOSEN_PATH" ]]; then
        echo "[i] Filtre static assets appliqué: SKIP_STATIC_RE=${SKIP_STATIC_RE} -> CHOSEN_PATH=${CHOSEN_PATH}"
      fi
    fi
    # Fallback: si non trouvé, utiliser premier vhost en 443 ou 80, et /
    DOMAIN_443=$(awk '/port[[:space:]]+443[[:space:]]+namevhost[[:space:]]+/ {print $4; exit}' <<<"$AP_SITES")
    DOMAIN_80=$(awk '/port[[:space:]]+80[[:space:]]+namevhost[[:space:]]+/ {print $4; exit}' <<<"$AP_SITES")
    if [[ -z "$CHOSEN_DOMAIN" ]]; then
      if [[ -n "$DOMAIN_443" ]]; then CHOSEN_DOMAIN="$DOMAIN_443"; fi
      if [[ -z "$CHOSEN_DOMAIN" && -n "$DOMAIN_80" ]]; then CHOSEN_DOMAIN="$DOMAIN_80"; fi
    fi
    if [[ -z "$CHOSEN_PATH" ]]; then CHOSEN_PATH="/"; fi

    # Schéma préférentiel
    SCHEME="https"
    if [[ -n "$CHOSEN_DOMAIN" ]]; then
      # Vérifier si le domaine est présent en 443
      if ! awk -v d="$CHOSEN_DOMAIN" '/port[[:space:]]+443[[:space:]]+namevhost[[:space:]]+/ {print $4}' <<<"$AP_SITES" | grep -qx "$CHOSEN_DOMAIN"; then
        SCHEME="http"
      fi
    fi

    echo
    echo "== HTTP/2 vs HTTP/1.1 (curl TTFB) =="
    CURL_REPS=${CURL_REPS:-10}
    if command -v curl >/dev/null 2>&1 && [[ -n "$CHOSEN_DOMAIN" ]]; then
      # Construire l’URL et ajouter un cache-buster
      BASE_URL="${SCHEME}://${CHOSEN_DOMAIN}${CHOSEN_PATH}"
      if [[ "$BASE_URL" == *"?"* ]]; then URL="${BASE_URL}&cb=$(date +%s)"; else URL="${BASE_URL}?cb=$(date +%s)"; fi
      echo "Domaine testé: ${SCHEME}://${CHOSEN_DOMAIN}"
      echo "Page la plus demandée: ${CHOSEN_PATH}"

      run_curl_reps() {
        local proto="$1"; shift
        local url="$1"; shift
        local out=""; local tmpfile
        tmpfile=$(mktemp)
        for i in $(seq 1 $CURL_REPS); do
          if [[ "$proto" == "h2" ]]; then
            curl -sS -o /dev/null --max-time 8 --http2 -w "%{time_starttransfer} %{time_total}\n" -H "Cache-Control: no-cache" -H "Pragma: no-cache" -H "Accept-Encoding: identity" "$url" >>"$tmpfile" 2>/dev/null || echo "0 0" >>"$tmpfile"
          else
            curl -sS -o /dev/null --max-time 8 --http1.1 -w "%{time_starttransfer} %{time_total}\n" -H "Cache-Control: no-cache" -H "Pragma: no-cache" -H "Accept-Encoding: identity" "$url" >>"$tmpfile" 2>/dev/null || echo "0 0" >>"$tmpfile"
          fi
          sleep 0.15
        done
        # Calcul moyenne/écart-type via awk: cols 1=ttfb, 2=total
        awk 'BEGIN{n=0;s1=0;s2=0;t1=0;t2=0} {n++; s1+=$1; s2+=$1*$1; t1+=$2; t2+=$2*$2} END{ if(n==0){print "n=0"; exit} mean1=s1/n; sd1=(s2/n - mean1*mean1); if(sd1<0) sd1=0; sd1=sqrt(sd1); mean2=t1/n; sd2=(t2/n - mean2*mean2); if(sd2<0) sd2=0; sd2=sqrt(sd2); printf("reps=%d mean_ttfb=%.6f sd_ttfb=%.6f mean_total=%.6f sd_total=%.6f\n", n, mean1, sd1, mean2, sd2) }' "$tmpfile"
        rm -f "$tmpfile"
      }

      echo "h2 (runs=${CURL_REPS}): "
      run_curl_reps h2 "$URL"
      echo "h1.1 (runs=${CURL_REPS}): "
      run_curl_reps h1.1 "$URL"
    else
      echo "[i] Impossible de mesurer h2/h1.1 (curl absent ou domaine non détecté)."
    fi
  fi

  echo "== Audit croisé Apache/MySQL =="
  if [[ -n "$APACHECTL" ]]; then
    # Extraction dynamique via apachectl
    APACHE_DUMP_CFG=$($APACHECTL -t -D DUMP_RUN_CFG 2>&1)
    APACHE_TIMEOUT=$(echo "$APACHE_DUMP_CFG" | awk '/Timeout:/{print $2; exit}')
    APACHE_KEEPALIVE=$(echo "$APACHE_DUMP_CFG" | awk '/KeepAlive:/{print $2; exit}')
    APACHE_KEEPALIVE_TIMEOUT=$(echo "$APACHE_DUMP_CFG" | awk '/KeepAliveTimeout:/{print $2; exit}')
    APACHE_MPM_SRC="run_cfg"
    APACHE_TIMEOUT_SRC="run_cfg"
    APACHE_KEEPALIVE_SRC="run_cfg"
    APACHE_KEEPALIVE_TIMEOUT_SRC="run_cfg"
    APACHE_MPM=$(echo "$APACHE_DUMP_CFG" | awk -F: '/Server MPM:/{print $2; exit}' | xargs)
    if [[ -z "$APACHE_MPM" ]]; then
      APACHE_MPM=$($APACHECTL -V 2>/dev/null | awk -F ':' '/Server MPM/ {print $2; exit}' | xargs)
      [[ -n "$APACHE_MPM" ]] && APACHE_MPM_SRC="apachectl -V"
    fi
    APACHE_MAX_WORKERS=0
    APACHE_MAX_WORKERS_SRC="run_cfg"
    APACHE_THREADS_PER_CHILD=$(echo "$APACHE_DUMP_CFG" | awk '/ThreadsPerChild:/{print $2; exit}')
    APACHE_THREADS_PER_CHILD_SRC="run_cfg"
    PREFORK_MEM=""
    WORKER_MEM=""
    TMP_MAX_WORKERS=$(echo "$APACHE_DUMP_CFG" | awk '/MaxRequestWorkers:/{print $2; exit}')
    if [[ -n "$TMP_MAX_WORKERS" && "$TMP_MAX_WORKERS" =~ ^[0-9]+$ ]]; then
      APACHE_MAX_WORKERS="$TMP_MAX_WORKERS"
    fi
    APACHE_START_SERVERS=$(echo "$APACHE_DUMP_CFG" | awk '/StartServers:/{print $2; exit}')
    APACHE_START_SERVERS_SRC="run_cfg"

    # Fallbacks: si DUMP_RUN_CFG n'expose pas ces valeurs, utiliser compute_mpm_effective() et parser Timeout/KeepAlive depuis les includes
    if [[ -z "$APACHE_TIMEOUT$APACHE_KEEPALIVE$APACHE_KEEPALIVE_TIMEOUT" ]]; then
      mapfile -t FILES2 < <(echo "$APACHE_INCLUDES" | awk '/\) \/etc\//{print $2}')
      F_TIMEOUT=""; F_KEEPALIVE=""; F_KEEPALIVE_TIMEOUT=""
      for f in "${FILES2[@]}"; do
        [[ -r "$f" ]] || continue
        while IFS= read -r line; do
          [[ $line =~ ^[[:space:]]*# ]] && continue
          k=$(awk '{print $1}' <<<"$line")
          v=$(awk '{print $2}' <<<"$line")
          case "$k" in
            Timeout) F_TIMEOUT="$v" ;;
            KeepAlive) F_KEEPALIVE="$v" ;;
            KeepAliveTimeout) F_KEEPALIVE_TIMEOUT="$v" ;;
          esac
        done < "$f"
      done
      if [[ -z "$APACHE_TIMEOUT" && -n "$F_TIMEOUT" ]]; then APACHE_TIMEOUT="$F_TIMEOUT"; APACHE_TIMEOUT_SRC="includes"; fi
      if [[ -z "$APACHE_KEEPALIVE" && -n "$F_KEEPALIVE" ]]; then APACHE_KEEPALIVE="$F_KEEPALIVE"; APACHE_KEEPALIVE_SRC="includes"; fi
      if [[ -z "$APACHE_KEEPALIVE_TIMEOUT" && -n "$F_KEEPALIVE_TIMEOUT" ]]; then APACHE_KEEPALIVE_TIMEOUT="$F_KEEPALIVE_TIMEOUT"; APACHE_KEEPALIVE_TIMEOUT_SRC="includes"; fi
    fi

    if [[ -z "$APACHE_THREADS_PER_CHILD" || -z "$APACHE_START_SERVERS" || -z "$APACHE_MAX_WORKERS" || "$APACHE_MAX_WORKERS" == "0" ]]; then
      # Récupère les valeurs via compute_mpm_effective()
      while IFS=': ' read -r key val; do
        case "$key" in
          StartServers) APACHE_START_SERVERS="$val"; APACHE_START_SERVERS_SRC="mpm_effective" ;;
          ThreadsPerChild) APACHE_THREADS_PER_CHILD="$val"; APACHE_THREADS_PER_CHILD_SRC="mpm_effective" ;;
          MaxRequestWorkers) APACHE_MAX_WORKERS="$val"; APACHE_MAX_WORKERS_SRC="mpm_effective" ;;
        esac
      done < <(compute_mpm_effective | tail -n +2)
    fi
    # Affichage
    echo "MPM: $APACHE_MPM [source: $APACHE_MPM_SRC]"
    echo "Timeout: $APACHE_TIMEOUT [source: $APACHE_TIMEOUT_SRC]"
    echo "KeepAlive: $APACHE_KEEPALIVE [source: $APACHE_KEEPALIVE_SRC]"
    echo "KeepAliveTimeout: $APACHE_KEEPALIVE_TIMEOUT [source: $APACHE_KEEPALIVE_TIMEOUT_SRC]"
    echo "MaxRequestWorkers: $APACHE_MAX_WORKERS [source: $APACHE_MAX_WORKERS_SRC]"
    echo "ThreadsPerChild: $APACHE_THREADS_PER_CHILD [source: $APACHE_THREADS_PER_CHILD_SRC]"
    echo "StartServers: $APACHE_START_SERVERS [source: $APACHE_START_SERVERS_SRC]"

    # Fallbacks redondants supprimés: on s'appuie sur apachectl et la section MPM effectif ci-dessus.

    # Extraction max_connections MySQL
    MAX_CONN=$(q "SHOW VARIABLES LIKE 'max_connections';" | awk '{print $2}')
    echo "MySQL max_connections: $MAX_CONN"

    # Comparaison Apache vs MySQL
    if [[ -n "$APACHE_MAX_WORKERS" && -n "$MAX_CONN" && "$APACHE_MAX_WORKERS" =~ ^[0-9]+$ && "$MAX_CONN" =~ ^[0-9]+$ && $APACHE_MAX_WORKERS -gt $MAX_CONN ]]; then
      echo "[!] Apache peut ouvrir $APACHE_MAX_WORKERS connexions simultanées, mais MySQL n'en accepte que $MAX_CONN. Risque d'erreurs 503 ou de blocages PHP/MySQL. Pensez à aligner ces valeurs."
    fi

    # Estimation mémoire Apache (approximative)
    RAM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    RAM_MB=$((RAM_KB/1024))
    if [[ -n "$APACHE_MAX_WORKERS" && "$APACHE_MAX_WORKERS" =~ ^[0-9]+$ ]]; then
      if [[ "$APACHE_MPM" == "prefork" ]]; then
        PREFORK_MEM=$((APACHE_MAX_WORKERS*40))
        echo "Estimation mémoire Prefork: $PREFORK_MEM Mo ($APACHE_MAX_WORKERS x 40Mo)"
        if [[ -n "$PREFORK_MEM" && "$PREFORK_MEM" =~ ^[0-9]+$ && $PREFORK_MEM -gt $((RAM_MB/2)) ]]; then
          echo "[!] La configuration prefork peut consommer plus de 50% de la RAM totale. Risque d'overcommit."
        fi
      fi
      if [[ "$APACHE_MPM" == "worker" || "$APACHE_MPM" == "event" ]]; then
        WORKER_MEM=$((APACHE_MAX_WORKERS*15))
        echo "Estimation mémoire $APACHE_MPM: $WORKER_MEM Mo ($APACHE_MAX_WORKERS x 15Mo)"
        if [[ -n "$WORKER_MEM" && "$WORKER_MEM" =~ ^[0-9]+$ && $WORKER_MEM -gt $((RAM_MB/2)) ]]; then
          echo "[!] La configuration $APACHE_MPM peut consommer plus de 50% de la RAM totale. Risque d'overcommit."
        fi
      fi
    fi

    # Timeout croisé
    MYSQL_WAIT_TIMEOUT=$(q "SHOW VARIABLES LIKE 'wait_timeout';" | awk '{print $2}')
    if [[ -n "$APACHE_TIMEOUT" && -n "$MYSQL_WAIT_TIMEOUT" && $APACHE_TIMEOUT -lt $MYSQL_WAIT_TIMEOUT ]]; then
      echo "[i] Le Timeout Apache ($APACHE_TIMEOUT s) est inférieur au wait_timeout MySQL ($MYSQL_WAIT_TIMEOUT s). C'est généralement souhaitable."
    fi
    if [[ -n "$APACHE_KEEPALIVE_TIMEOUT" && $APACHE_KEEPALIVE_TIMEOUT -gt 5 ]]; then
      echo "[!] KeepAliveTimeout Apache est assez élevé ($APACHE_KEEPALIVE_TIMEOUT s). Pour les sites à fort trafic, une valeur basse (1-5s) est recommandée."
    fi
  else
    echo "[!] apachectl/apache2ctl non trouvé. Fallback sur les fichiers mpm_*.conf."
    # Fallback direct sur les fichiers mpm_*.conf
    FALLBACK_MAXWORKERS=0
    FALLBACK_THREADS_PER_CHILD=0
    for f in /etc/apache2/mods-enabled/mpm_*.conf; do
      if [[ -f "$f" ]]; then
        echo "--- $f ---"
        grep -E '^(\s*)?(MaxRequestWorkers|StartServers|MinSpareServers|MaxSpareServers|ThreadsPerChild|ServerLimit|ThreadLimit|MaxConnectionsPerChild|MaxClients)' "$f" | grep -v '^\s*#'
        # Extraction pour calcul mémoire
        if grep -q 'MaxRequestWorkers' "$f"; then
          TMP_MW=$(awk '/MaxRequestWorkers/{print $2}' "$f" | head -1)
          if [[ -n "$TMP_MW" && "$TMP_MW" =~ ^[0-9]+$ ]]; then
            FALLBACK_MAXWORKERS=$TMP_MW
          fi
        fi
        if grep -q 'ThreadsPerChild' "$f"; then
          TMP_TPC=$(awk '/ThreadsPerChild/{print $2}' "$f" | head -1)
          if [[ -n "$TMP_TPC" && "$TMP_TPC" =~ ^[0-9]+$ ]]; then
            FALLBACK_THREADS_PER_CHILD=$TMP_TPC
          fi
        fi
      fi
    done
    echo "--- Fin fallback fichiers mpm_*.conf ---"
    # Calcul mémoire croisée Apache/MySQL
    RAM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    RAM_MB=$((RAM_KB/1024))
    # Hypothèse : 15 Mo par thread Apache worker/event
    if [[ $FALLBACK_MAXWORKERS -gt 0 && $FALLBACK_THREADS_PER_CHILD -gt 0 ]]; then
      APACHE_THREADS=$((FALLBACK_MAXWORKERS*FALLBACK_THREADS_PER_CHILD))
      APACHE_MEM_EST=$((FALLBACK_MAXWORKERS*15))
      echo "Estimation mémoire Apache (worker/event): $APACHE_MEM_EST Mo ($FALLBACK_MAXWORKERS workers x 15Mo)"
    elif [[ $FALLBACK_MAXWORKERS -gt 0 ]]; then
      APACHE_MEM_EST=$((FALLBACK_MAXWORKERS*15))
      echo "Estimation mémoire Apache (worker/event): $APACHE_MEM_EST Mo ($FALLBACK_MAXWORKERS workers x 15Mo)"
    fi
    # Mémoire MySQL (déjà calculée plus haut)
    BP_SIZE=$(q "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" | awk '{print $2}')
    BP_MB=$((BP_SIZE/1024/1024))
    # Addition
    if [[ -n "$APACHE_MEM_EST" && -n "$BP_MB" && "$APACHE_MEM_EST" =~ ^[0-9]+$ && "$BP_MB" =~ ^[0-9]+$ ]]; then
      TOTAL_EST=$((APACHE_MEM_EST+BP_MB))
      echo "Mémoire estimée Apache+MySQL: $TOTAL_EST Mo (Apache $APACHE_MEM_EST + MySQL $BP_MB) sur $RAM_MB Mo RAM physique."
      if [[ $TOTAL_EST -gt $((RAM_MB*8/10)) ]]; then
        echo "[!] La somme mémoire estimée Apache+MySQL approche ou dépasse 80% de la RAM physique. Risque de swap ou d'instabilité."
      fi
    fi
    echo "Résumé croisé: MaxRequestWorkers=$FALLBACK_MAXWORKERS, ThreadsPerChild=$FALLBACK_THREADS_PER_CHILD, BufferPool=$BP_MB Mo, RAM=$RAM_MB Mo."
  fi

  echo
  echo "== Suggestions automatiques MySQL =="
  # Suggestion: buffer pool < 70% RAM
  RAM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
  BP_SIZE=$(q "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" | awk '{print $2}')
  if [[ -n "$RAM_KB" && -n "$BP_SIZE" && $RAM_KB -gt 0 ]]; then
    BP_MB=$((BP_SIZE/1024/1024))
    RAM_MB=$((RAM_KB/1024))
    PCT=$((BP_MB*100/RAM_MB))
    if [[ $PCT -lt 70 ]]; then
      echo "[!] innodb_buffer_pool_size est à $PCT% de la RAM ($BP_MB/$RAM_MB Mo). Vous pouvez probablement l'augmenter."
    fi
  fi
  # Suggestion: max_connections très élevé
  MAX_CONN=$(q "SHOW VARIABLES LIKE 'max_connections';" | awk '{print $2}')
  if [[ -n "$MAX_CONN" && $MAX_CONN -gt 500 ]]; then
    echo "[!] max_connections est très élevé ($MAX_CONN). Ajustez selon la charge réelle pour éviter la surconsommation mémoire."
  fi
  # Suggestion: tables volumineuses
  echo "(Consultez le top 10 des tables volumineuses ci-dessus pour optimiser indexation et archivage)"

  echo
  echo "== MySQLTuner (résumé) =="
  if command -v mysqltuner >/dev/null 2>&1; then
    mysqltuner | head -200
  else
    echo "mysqltuner non trouvé dans le PATH. Installez-le pour obtenir un diagnostic avancé."
  fi

} | tee "${OUT}"

echo "Audit écrit dans: ${OUT}"
