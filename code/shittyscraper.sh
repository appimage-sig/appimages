#!/bin/sh

set -ux

CONTENT_DIR="content/apps"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

sed_in_place() {
	if sed --version >/dev/null 2>&1; then
		sed -i "$@"
	else
		sed -i '' "$@"
	fi
}

get_all_github_assets() {
	repo_owner="$1"
	repo_name="$2"
	api_url="https://api.github.com/repos/${repo_owner}/${repo_name}/releases/latest"

	auth_header=""
	if [ -n "$GITHUB_TOKEN" ]; then
		auth_header="-H \"Authorization: token ${GITHUB_TOKEN}\""
	fi

	# Capture body and HTTP status
	resp_file=$(mktemp)
	status=$(eval "curl -s -H 'Accept: application/vnd.github.v3+json' ${auth_header} -o \"$resp_file\" -w '%{http_code}' \"$api_url\"")
	body=$(cat "$resp_file")
	rm -f "$resp_file"

	# HTTP status checks
	if [ "$status" -eq 404 ]; then
		echo "404"
		return 1
	fi
	if [ "$status" -ge 400 ]; then
		# Check for rate limit message as well
		if echo "$body" | grep -qi "API rate limit exceeded"; then
			echo "rate_limit"
			return 1
		fi
		# Generic error
		echo "api_error"
		return 1
	fi

	# Ensure there's a tag_name (meaning a release exists)
	tag=$(printf '%s' "$body" | jq -r '.tag_name // empty' 2>/dev/null)
	if [ -z "$tag" ]; then
		echo "no_release"
		return 1
	fi

	# Extract browser_download_url entries (one per line)
	urls=$(printf '%s' "$body" | jq -r '.assets[]?.browser_download_url' 2>/dev/null | sed '/^$/d')
	if [ -z "$urls" ]; then
		echo "no_asset"
		return 1
	fi

	printf '%s\n' "$urls"
	return 0
}

parse_github_url() {
	# Trim trailing spaces and trailing characters like ) or >
	url_stripped=$(printf '%s' "$1" | sed 's/[[:space:]>)]*$//')

	# Remove scheme and optional www.
	clean_url=$(printf '%s' "$url_stripped" | sed -E 's|^https?://(www\.)?github\.com/||I')

	# Remove possible leading github.com/ without scheme
	clean_url=$(printf '%s' "$clean_url" | sed -E 's|^github\.com/||I')

	# Strip trailing .git and any trailing slashes or extra path components beyond owner/repo
	clean_url=$(printf '%s' "$clean_url" | sed -E 's/\.git$//; s|/.*$||2')

	# Ensure we only keep owner/repo (two components)
	owner=$(printf '%s' "$clean_url" | cut -d'/' -f1)
	repo=$(printf '%s' "$clean_url" | cut -d'/' -f2)

	# If repo is empty, try extracting first two path segments from original cleaned string
	if [ -z "$repo" ]; then
		# take first two segments from original cleaned (before truncation)
		clean_url2=$(printf '%s' "$url_stripped" | sed -E 's|^https?://(www\.)?github\.com/||I; s/\.git$//;')
		owner=$(printf '%s' "$clean_url2" | cut -d'/' -f1)
		repo=$(printf '%s' "$clean_url2" | cut -d'/' -f2)
	fi

	if [ -z "$owner" ] || [ -z "$repo" ]; then
		return 1
	fi

	printf '%s/%s' "$owner" "$repo"
	return 0
}

escape_sed() {
	# Escape / and & for sed substitution
	printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

match_architecture() {
	old_url="$1"
	all_new_urls="$2"

	arch="default"

	if printf '%s' "$old_url" | grep -qiE "(arm64|aarch64)"; then
		arch="arm64"
	elif printf '%s' "$old_url" | grep -qiE "(armv7|armhf)"; then
		arch="armv7"
	elif printf '%s' "$old_url" | grep -qiE "(x86_64|x64|amd64)"; then
		arch="x64"
	fi

	# Ensure new urls are newline-separated; iterate safely
	printf '%s\n' "$all_new_urls" | while IFS= read -r new_url; do
		case "$arch" in
			arm64)
				if printf '%s' "$new_url" | grep -qiE "(arm64|aarch64)"; then
					printf '%s' "$new_url"
					exit 0
				fi
				;;
			armv7)
				if printf '%s' "$new_url" | grep -qiE "(armv7|armhf)"; then
					printf '%s' "$new_url"
					exit 0
				fi
				;;
			x64)
				# prefer x86_64/amd64 and not arm variants
				if ! printf '%s' "$new_url" | grep -qiE "(arm64|aarch64|armv7|armhf)"; then
					if printf '%s' "$new_url" | grep -qiE "(x86_64|x64|amd64)"; then
						printf '%s' "$new_url"
						exit 0
					fi
				fi
				;;
			default)
				;;
		esac
	done

	# If old_url had no explicit arch, try to pick a new_url without arm indicators
	printf '%s\n' "$all_new_urls" | while IFS= read -r new_url; do
		if ! printf '%s' "$new_url" | grep -qiE "(arm64|aarch64|armv7|armhf)"; then
			printf '%s' "$new_url"
			return 0
		fi
	done

	# Fallback: return the first available URL
	printf '%s\n' "$all_new_urls" | head -n 1
	return 0
}

main() {
	if [ ! -d "$CONTENT_DIR" ]; then
		echo "✗ Папка $CONTENT_DIR не найдена"
		exit 1
	fi

	updated_count=0
	skipped_count=0
	error_count=0

	echo "Начинаем обновление ссылок..."
	echo ""

	for app_dir in "$CONTENT_DIR"/*; do
		if [ ! -d "$app_dir" ]; then
			continue
		fi

		app_name=$(basename "$app_dir")
		index_file="${app_dir}/index.md"

		if [ ! -f "$index_file" ]; then
			echo "⚠ Пропущено: $app_name (нет index.md)"
			skipped_count=$((skipped_count + 1))
			continue
		fi

		github_repo=$(grep -oE 'https?://(www\.)?github\.com/[^/[:space:]>)]*/[^/[:space:]>)]*/releases/download' "$index_file" | sed 's|/releases/download$||' | head -1)

		if [ -z "$github_repo" ]; then
			github_repo=$(grep -oE 'https?://(www\.)?github\.com/[^/[:space:]>)]*/[^/[:space:]>)]*' "$index_file" | head -n 1)
		fi

		if [ -z "$github_repo" ]; then
			echo "⊘ Пропущено: $app_name (ссылка ведет не на GitHub)"
			skipped_count=$((skipped_count + 1))
			continue
		fi

		repo_info=$(parse_github_url "$github_repo")
		if [ $? -ne 0 ] || [ -z "$repo_info" ]; then
			echo "✗ $app_name: не удалось распарсить URL: $github_repo"
			error_count=$((error_count + 1))
			continue
		fi

		repo_owner=$(printf '%s' "$repo_info" | cut -d'/' -f1)
		repo_name=$(printf '%s' "$repo_info" | cut -d'/' -f2)

		all_assets=$(get_all_github_assets "$repo_owner" "$repo_name")
		asset_status=$?

		if [ $asset_status -ne 0 ]; then
			if [ "$all_assets" = "no_release" ]; then
				echo "⊘ $app_name: нет релизов в репозитории $repo_info"
				skipped_count=$((skipped_count + 1))
			elif [ "$all_assets" = "no_asset" ]; then
				echo "⊘ $app_name: релиз найден, но нет артефактов в $repo_info"
				skipped_count=$((skipped_count + 1))
			elif [ "$all_assets" = "404" ]; then
				echo "✗ $app_name: репозиторий не найден ($repo_info)"
				error_count=$((error_count + 1))
			elif [ "$all_assets" = "rate_limit" ]; then
				echo "✗ Превышен лимит запросов GitHub API."
				error_count=$((error_count + 1))
			else
				echo "✗ $app_name: ошибка при вызове API ($all_assets)"
				error_count=$((error_count + 1))
			fi
			continue
		fi

		# Extract old github release/download URLs (newline-separated)
		old_urls=$(grep -oE 'https?://(www\.)?github\.com/[^"]*/releases/download[^"]*' "$index_file" | tr -d '"')

		if [ -z "$old_urls" ]; then
			echo "⚠ GitHub ссылки на скачивание не найдены в $app_name"
			skipped_count=$((skipped_count + 1))
			continue
		fi

		is_file_updated=0

		# Iterate old URLs safely line by line
		printf '%s\n' "$old_urls" | while IFS= read -r old_url; do
			# match_architecture expects newline-separated all_assets
			new_url=$(match_architecture "$old_url" "$all_assets")

			if [ -z "$new_url" ]; then
				echo "⚠ $app_name: не удалось подобрать замену для $old_url"
				continue
			fi

			if [ "$old_url" = "$new_url" ]; then
				continue
			fi

			old_escaped=$(escape_sed "$old_url")
			new_escaped=$(escape_sed "$new_url")

			sed_in_place "s|$old_escaped|$new_escaped|g" "$index_file"
			is_file_updated=1
		done

		# Because while runs in a subshell, we check by testing whether index file changed via git diff (cheap approach)
		if git --no-pager diff --quiet -- "$index_file" 2>/dev/null; then
			# no changes
			if [ $is_file_updated -eq 1 ]; then
				# subshell change flag not visible here; re-check by content comparison
				:
			fi
			echo "✓ $app_name: все ссылки уже актуальны"
			skipped_count=$((skipped_count + 1))
		else
			echo "✓ $app_name: ссылки успешно обновлены"
			updated_count=$((updated_count + 1))
		fi
	done

	echo ""
	echo "=== Итоги ==="
	echo "Обновлено файлов: $updated_count"
	echo "Пропущено/Актуально: $skipped_count"
	echo "Ошибок: $error_count"
}

main "$@"
