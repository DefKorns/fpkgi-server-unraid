#!/bin/bash

########################################
# PS4 PKG FPKGi Server - JSON Edition
########################################

umask 000

########################################
# ENV
########################################
[ -f /tmp/pkg_server.lock ] && rm -f /tmp/pkg_server.lock
[ ! -f /data/index.html ] && cp -f /index.html /data/index.html

SERVER_URL="${SERVER_URL:-}"
LOG_DEBUG="${LOG_DEBUG:-0}"

if [ -z "$SERVER_URL" ]; then
	echo "[ERROR] SERVER_URL not set"
	sleep 30
	exit 1
fi

INPUT_DIR="/data"
IMG_DIR="$INPUT_DIR/_img"

PKGTOOL="/lib/OpenOrbisSDK/bin/linux/PkgTool.Core"

JSON_GAMES="$INPUT_DIR/GAMES.json"
JSON_UPDATES="$INPUT_DIR/UPDATES.json"
JSON_DLC="$INPUT_DIR/DLC.json"

for cmd in jq stat inotifywait "$PKGTOOL"; do
	if ! command -v ${cmd%% *} >/dev/null 2>&1; then
		echo "[ERROR] Required command '$cmd' not found. Exiting."
		exit 1
	fi
done

mkdir -p "$IMG_DIR"

########################################
# LOGGER
########################################
_log() {
	local level="$1"
	shift
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}

log_info() { _log "INFO" "$*"; }
log_warn() { _log "WARN" "$*"; }
log_error() { _log "ERROR" "$*"; }

log_debug() {
	if [ "$LOG_DEBUG" = "1" ]; then
		_log "DEBUG" "$*"
	fi
}

########################################
# CHECK IF PKG ALREADY EXISTS
########################################
pkg_exists_in_json() {
	local pkg_url="$1"
	local json_file="$2"

	jq -e --arg url "$pkg_url" '.DATA | has($url)' "$json_file" >/dev/null 2>&1
}

########################################
# PERMISSIONS FIX
########################################
fix_permissions() {
	chown -R 1001:users "$INPUT_DIR" 2>/dev/null || true
	chmod -R 775 "$INPUT_DIR" 2>/dev/null || true
}

########################################
# JSON INIT
########################################
init_json() {
	[ -f "$1" ] || echo '{"DATA":{}}' >"$1"
}

init_json "$JSON_GAMES"
init_json "$JSON_UPDATES"
init_json "$JSON_DLC"

########################################
# ATOMIC JSON UPDATE
########################################
update_json() {
	local file="$1"
	local key="$2"
	local value="$3"
	local tmp

	tmp=$(mktemp)

	jq --arg k "$key" --argjson v "$value" \
		'.DATA[$k]=$v' "$file" >"$tmp"
	local jq_status=$?
	if [ $jq_status -ne 0 ]; then
		log_error "JSON update failed for $file with key $key"
		rm -f "$tmp"
		return
	fi

	mv "$tmp" "$file"
	fix_permissions
	log_info "Added $key to $file"
}

########################################
# SAFE FIELD CLEANER
########################################
parse_sfo() {
	local sfo_file="$1"
	local field="$2"
	grep "^$field " "$sfo_file" 2>/dev/null | head -n1 | awk -F'=' '{print $2}' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

extract_cover() {
	local pkg="$1"
	local icon_index="$2"
	local cover_path="$3"
	if [ -n "$icon_index" ]; then
		log_info "Extracting cover"
		if $PKGTOOL pkg_extractentry "$pkg" "$icon_index" "$cover_path" >/dev/null 2>&1; then
			chown 1001:users "$cover_path" 2>/dev/null || log_warn "chown failed"
			chmod 775 "$cover_path" 2>/dev/null || log_warn "chmod failed"
		else
			log_warn "Cover extraction failed"
		fi
	fi
}

########################################
# PROCESS PKG
########################################
process_pkg() {
	local pkg="$1"
	local pkg_rel pkg_url param_index category title title_id version content_id raw_pubtool release release_raw region cover_path icon_index cover_url size json_entry
	log_info "Processing $pkg"
	local list_file sfo_file sfo_txt
	list_file=$(mktemp)
	sfo_file=$(mktemp)
	sfo_txt=$(mktemp)
	# Ensure cleanup on exit or error
	trap 'rm -f "$list_file" "$sfo_file" "$sfo_txt"' RETURN
	pkg_rel="${pkg#"$INPUT_DIR"/}"
	pkg_url="${SERVER_URL}/${pkg_rel}"

	########################################
	# DUPLICATE CHECK
	########################################
	if pkg_exists_in_json "$pkg_url" "$JSON_GAMES" ||
		pkg_exists_in_json "$pkg_url" "$JSON_UPDATES" ||
		pkg_exists_in_json "$pkg_url" "$JSON_DLC"; then
		log_info "Skip: $pkg already listed in JSONs."
		return 1
	fi

	log_info "Processing $pkg_rel"

	$PKGTOOL pkg_listentries "$pkg" >"$list_file" 2>/dev/null || {
		log_warn "Cannot read PKG entries for $pkg"
		return 1
	}

	param_index=$(grep PARAM_SFO "$list_file" | awk '{print $4}' | head -n1)
	[ -z "$param_index" ] && {
		log_warn "PARAM_SFO not found in $pkg"
		return 1
	}

	$PKGTOOL pkg_extractentry "$pkg" "$param_index" "$sfo_file" >/dev/null 2>&1 || {
		log_warn "Failed to extract PARAM_SFO from $pkg"
		return 1
	}
	$PKGTOOL sfo_listentries "$sfo_file" >"$sfo_txt" 2>/dev/null || {
		log_warn "Failed to list SFO entries for $pkg"
		return 1
	}
	########################################
	# SAFE PARSER
	########################################
	category=$(parse_sfo "$sfo_txt" "CATEGORY")
	title=$(parse_sfo "$sfo_txt" "TITLE")
	title="${title//™/}"
	title_id=$(parse_sfo "$sfo_txt" "TITLE_ID")
	version=$(parse_sfo "$sfo_txt" "APP_VER")
	content_id=$(parse_sfo "$sfo_txt" "CONTENT_ID")

	[ -z "$category" ] && category="gd"
	[ -z "$version" ] && version="0.00"
	[ -z "$title" ] && title="UNKNOWN_TITLE"
	[ -z "$title_id" ] && {
		log_warn "TITLE_ID missing — skipping $pkg"
		return 1
	}

	log_info "Title: $title"
	log_info "TitleID: $title_id"
	log_info "Version: $version"

	########################################
	# RELEASE DATE
	########################################
	raw_pubtool=$(grep PUBTOOLINFO "$sfo_txt" 2>/dev/null)
	release="null"
	release_raw=$(echo "$raw_pubtool" | grep -o 'c_date=[0-9]\{8\}' | cut -d'=' -f2)

	if [[ "$release_raw" =~ ^[0-9]{8}$ ]]; then
		release="${release_raw:0:4}-${release_raw:4:2}-${release_raw:6:2}"
	fi
	log_info "Release: $release"

	########################################
	# REGION
	########################################
	region="null"
	if [[ -n "$content_id" ]]; then
		case "${content_id:0:1}" in
		J) region="JAP" ;;
		E) region="EUR" ;;
		U) region="USA" ;;
		esac
	fi
	log_info "Region: $region"

	########################################
	# COVER
	########################################
	cover_path="$INPUT_DIR/_img/${title_id}.png"
	icon_index=$(grep ICON0_PNG "$list_file" | awk '{print $4}' | head -n1)
	extract_cover "$pkg" "$icon_index" "$cover_path"
	cover_url="${SERVER_URL}/_img/${title_id}.png"

	########################################
	# JSON ENTRY
	########################################
	size=$(stat -c %s "$pkg" 2>/dev/null || echo 0)
	json_entry=$(jq -n \
		--arg title_id "$title_id" \
		--arg name "$title" \
		--arg region "$region" \
		--arg version "$version" \
		--arg release "$release" \
		--arg cover_url "$cover_url" \
		--argjson size "$size" \
		'{title_id:$title_id,name:$name,region:$region,version:$version,release:$release,cover_url:$cover_url,size:$size}')

	########################################
	# CATEGORY ROUTING
	########################################
	log_info "Calling update_json for $pkg_url"
	case "$category" in
	gd) update_json "$JSON_GAMES" "$pkg_url" "$json_entry" ;;
	gp) update_json "$JSON_UPDATES" "$pkg_url" "$json_entry" ;;
	ac) update_json "$JSON_DLC" "$pkg_url" "$json_entry" ;;
	*) update_json "$JSON_GAMES" "$pkg_url" "$json_entry" ;;
	esac

	return 0
}

########################################
# PRO SETTINGS
########################################
CACHE_FILE="/tmp/pkg_cache.list"
LOCK_FILE="/tmp/pkg_server.lock"
# SCAN_INTERVAL=300

########################################
# CACHE SYSTEM
########################################
load_cache() {
	touch "$CACHE_FILE"
	sort -u "$CACHE_FILE" -o "$CACHE_FILE"
}

cache_has_pkg() {
	local pkg_url="$1"
	grep -Fxq "$pkg_url" "$CACHE_FILE"
}

cache_add_pkg() {
	local pkg_url="$1"
	echo "$pkg_url" >>"$CACHE_FILE"
}

########################################
# SINGLE INSTANCE LOCK
########################################
create_lock() {
	if [ -f "$LOCK_FILE" ]; then
		old_pid=$(cat "$LOCK_FILE")

		if kill -0 "$old_pid" 2>/dev/null; then
			log_error "Another instance is running (PID $old_pid)"
			exit 1
		fi
	fi

	echo $$ >"$LOCK_FILE"
}

remove_lock() {
	rm -f "$LOCK_FILE"
}

########################################
# MAIN LOOP (inotifywait)
########################################
log_info "PS4 PKG Server PRO (inotify) Started"

create_lock
load_cache

trap remove_lock EXIT INT TERM

# Ensure cache and permissions are correct at start
fix_permissions
find "$INPUT_DIR" -type f -iname "*.pkg" -print0 | while IFS= read -r -d '' fpkg; do
	log_info "Processing initial $fpkg"
	pkg_rel="${fpkg#"$INPUT_DIR"/}"
	pkg_url="${SERVER_URL}/${pkg_rel}"

	if cache_has_pkg "$pkg_url"; then
		log_debug "Cache skip $pkg_url"
		continue
	fi

	process_pkg "$fpkg"
	if [ $? -eq 0 ]; then
		cache_add_pkg "$pkg_url"
	fi
	load_cache
	fix_permissions
done

while true; do
	log_info "Waiting for new or modified PKG fileaaas..."
	inotifywait -e close_write -e moved_to -e create -r --format '%w%f' "$INPUT_DIR" --exclude '_img' | while read -r fpkg; do
		# Only process .pkg files
		log_info "Processing while true $fpkg"
		if [[ "$fpkg" == *.pkg ]]; then
			pkg_rel="${fpkg#"$INPUT_DIR"/}"
			pkg_url="${SERVER_URL}/${pkg_rel}"

			if cache_has_pkg "$pkg_url"; then
				log_debug "Cache skip $pkg_url"
				continue
			fi

			process_pkg "$fpkg"
			if [ $? -eq 0 ]; then
				cache_add_pkg "$pkg_url"
			fi
			load_cache
			fix_permissions
		fi
	done
done
