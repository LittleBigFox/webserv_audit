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

    echo "== Profiling requêtes sans slow_log (Performance Schema) =="
  echo "[Note] Ce serveur n'utilise pas le slow_log MariaDB; utilisation de Performance Schema pour l'observabilité."
  PS_STATE=$(q "SHOW VARIABLES LIKE 'performance_schema';" | awk '{print tolower($2)}' | tr -d '\r' || true)
  if [[ "$PS_STATE" == "on" || "$PS_STATE" == "1" ]]; then
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
    echo "[!] performance_schema est désactivé. Activez-le pour ce profilage (ajouter performance_schema=ON puis redémarrer MariaDB)."
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
