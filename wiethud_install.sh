#!/bin/bash

# Fatal error spew
function error_report {
	echo "$1" >&2
	exit 1
}

# Needs full URL in $1 and file name from URL in $2
function download_repo {
	echo "Repo download start"
	# Previous repo download check
	if [[ -f "$2" ]]; then
		echo "Removing previous archive"
		rm "$2"
	fi
	# Throw error if neither curl, nor wget exist
	if type wget >/dev/null 2>&1; then
		echo "Using wget to download \"$1\""
		wget -q "$1"
		local status=$?
	elif type curl >dev/null 2>&1; then
		echo "Using curl to download \"$1\""
		curl -s "$1"
		local status=$?
	else
		error_report "curl and wget aren't installed"
	fi

	if [ ! $status -eq 0 ]; then
		error_report "Error during download"
	fi
}

# Needs file name from URL in $1, returns directory name
function extract_repo {
	echo "Extracting ZIP archive of repo"
	if type unzip >/dev/null 2>&1; then
		local rootdir_name=""
		# Get all directories with zipinfo
		# Take the top, remove trailing slash
		# Lowercase it as we'll be using unzip -LL
		rootdir_name=$(unzip -Z -1 "$1" "*/" | \
			head -1 | cut -d "/" -f 1 | \
			tr "[:upper:]" "[:lower:]")
		
		# Directory removal check
		if [[ -d "$rootdir_name" ]]; then
			echo "Removing previous extracted directory"
			rm -r "$rootdir_name"
		fi
		# Extraction
		# LL lowercases all files, q silences most output
		unzip -LL -q "$1"
		local status=$?
	else
		error_report "unzip isn't installed"
	fi

	if [ ! $status -eq 0 ]; then
		error_report "Error during extraction"
	fi

	# Hacky workaround to save name of the extracted directory
	export repodir_name="$rootdir_name"
}

# Meant to run after cd'ing into HUD directory
function prune_files {
	echo "Pruning Windows-specific files"
	[[ -d "hlextract" ]] && rm -r "hlextract"
	[[ -f "extract_base_hudfiles.bat" ]] && rm "extract_base_hudfiles.bat"
}

# Needs extracted name in $1, new name in $2
function correct_name {
	echo "Correcting directory name"
	if [[ -d "$2" ]]; then
		echo "Removing previous renamed directory"
		rm -r "$2"
	fi
	mv "$1" "$2"
}

# Needs base name in $1
function rebuild_base {
	echo "Recreating base directory \"$1\""
	[[ -d "$1" ]] && rm -r "$1"
	mkdir "$1"
}

# Needs expanded array of directory paths
function dir_structure {
	echo "Creating directories inside base"
	while read -r line; do
		mkdir -p "$line" || error_report "Couldn't create directory"
		echo "Creating \"$line\""
	done < <(echo "$@" | tr " " "\n" | sort -u)
}

# Needs expanded file array
function extract_base {
	echo "Begin extraction"
	# Define paths
	local base_path=""
	base_path="$(cd ../../../..; pwd)"
	local vpk_tool="$base_path/bin/vpk_linux32"
	local vpk_path="$base_path/tf/tf2_misc_dir.vpk"
	# vpk_linux32 fix for 64-bit systems
	case "$(uname -m)" in
		"x86_64"|"amd64")
			local lib_path="$base_path/bin"
			export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$lib_path" ;;
	esac
	"$vpk_tool" x "$vpk_path" "$@"
}

function post_tweaks {
	# Broken include in scripts/hudlayout.res
	echo "Applying tweaks"
	sed -i "s/default_hudfiles\/hudlayout.res/default_hudfiles\/scripts\/hudlayout.res/g" "./scripts/hudlayout.res"
	echo "Broken hudlayout.res include fix"
}

function main {
	# Initial declarations
	local wiet_url="https://github.com/wiethoofd/wiethud/archive/master.zip"
	local wiet_name="${wiet_url##*/}"
	local hud_base="default_hudfiles"
	local hudanim_tweak="scripts/hudanimations_tf.txt"
	# Download and extract
	download_repo "$wiet_url" "$wiet_name"
	repodir_name="" # Initialize variable for extract_repo
	extract_repo "$wiet_name"
	# Rename to just "wiethud"
	local final_name="wiethud"
	correct_name "$repodir_name" "$final_name"
	cd "$final_name" || error_report "Directory change error"
	# Clean up
	prune_files
	# Preparation phase
	echo "Looking for files to extract"
	# In case master directory is broken
	[[ -d "resource/ui" ]] || error_report "\"resource/ui\" not found inside"
	[[ -d "scripts" ]] || error_report "\"scripts\" not found inside"
	# Find all .res files inside default directories
	local res_files=()
	# Look only in necessary directories and use null terminator to separate
	while read -d $'\0' -r res_path; do
		res_files+=("$res_path")
	done < <(find "./resource" "./scripts" -type f -name "*.res" -print0)
	# Construct lists for structure creation and vpk_linux32
	local extraction_list=()
	local dir_list=()
	for res_file in "${res_files[@]}"; do
		# Only look for uncommented default_hudfiles includes
		if grep -qE "^#base.*default_hudfiles" "$res_file"; then
			# Format the name to prepare it for vpk_linux32
			formatted_name="${res_file:2}"
			# Extract directory name from it
			dir_name="${formatted_name%/*}"
			extraction_list+=("$formatted_name")
			dir_list+=("$dir_name")
		fi
	done
	# Apply tweak for hudanims extraction
	extraction_list+=("$hudanim_tweak")
	# Start with a fresh base directory
	rebuild_base "$hud_base"
	cd "$hud_base" || error_report "Error changing to \"$hud_base\""
	# Provide structure for vpk_linux32, it can't create directories
	dir_structure "${dir_list[@]}"
	# Extraction phase
	extract_base "${extraction_list[@]}"
	# Cleanup
	echo "Cleaning up zipped archive"
	rm "../../$wiet_name"
	# Tweaks
	cd ".." || error_report "Error changing to HUD root"
	post_tweaks
}

main
