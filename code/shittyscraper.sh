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
	api_url="https://api.github.com/repos/{repo_owner}/${repo_name}/releases/latest"

	auth_header=""
	if [ -n "$GITHUB_TOKEN" ]; then
		auth_header="-H \"Authorization: token ${GITHUB_TOKEN}\""
	fi

	resp_file=$(mktemp)
	status=$(eval "curl -s -H 'Accept: application/vnd.github.v3+json' ${auth_header} -o \"$resp_file\" -w '%{http_code}' \"$api_url\"")
	body=$(cat "$resp_file")
	rm -f "$resp_file"

	if [ "$status" -eq 404 ]; then
		echo "404"
		return 1
	fi
	if [ "$status" -ge 400 ]; then
		if echo "$body" | grep -qi "API rate limit exceeded"; then
			echo "rate_limit"
			return 1
		fi
		echo "api_error"
		return 1
	fi

	tag=$(printf '%s' "$body" | jq -r '.tag_name // empty' 2>/dev/null)
	if [ -z "$tag" ]; then
		echo "no_release"
		return 1
	fi

	urls=$(printf '%s' "$body" | jq -r '.assets[] | select(.browser_download_url | endswith(".AppImage")) | .browser_download_url' 2>/dev/null | sed '/^$/d')
	if [ -z "$urls" ]; then
		echo "no_asset"
		return 1
	fi

	printf '%s\n' "$urls"
	return 0
}

parse_github_url() {
	url_stripped=$(printf '%s' "$1" | sed 's/[[:space:]>)]*$//')
	clean_url=$(printf '%s' "$url_stripped" | sed -E 's|^https?://(www\.)?github\.com/||I')
	clean_url=$(printf '%s' "$clean_url" | sed -E 's|^github\.com/||I')
	clean_url=$(printf '%s' "$clean_url" | sed -E 's/\.git$//; s|/.*$||2')

	owner=$(printf '%s' "$clean_url" | cut -d'/' -f1)
	repo=$(printf '%s' "$clean_url" | cut -d'/' -f2)

	if [ -z "$repo" ]; then
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

	case "$arch" in
		arm64)
			printf '%s\n' "$all_new_urls" | grep -iE "(arm64|aarch64)" | head -1
			if [ $? -eq 0 ]; then return 0; fi
			;;
		armv7)
			printf '%s\n' "$all_new_urls" | grep -iE "(armv7|armhf)" | head -1
			if [ $? -eq 0 ]; then return 0; fi
			;;
		x64)
			printf '%s\n' "$all_new_urls" | grep -vE "(arm64|aarch64|armv7|armhf)" | grep -iE "(x86_64|x64|amd64)" | head -1
			if [ $? -eq 0 ]; then return 0; fi
			;;
	esac

	printf '%s\n' "$all_new_urls" | grep -vE "(arm64|aarch64|armv7|armhf)" | head -1
	if [ $? -eq 0 ]; then return 0; fi

	printf '%s\n' "$all_new_urls" | head -1
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

	for app_dir in "$CONTENT_DIR"/*; do
		if [ ! -d "$app_dir" ]; then
			continue
		fi

		app_name=$(basename "$app_dir")
		index_file="${app_dir}/index.md"

		if [ ! -f "$index_file" ]; then
			skipped_count=$((skipped_count + 1))
			continue
		fi

		github_repo=$(grep -oE 'https?://(www\.)?github\.com/[^/[:space:]>)]*/[^/[:space:]>)]*/releases/download' "$index_file" | sed 's|/releases/download$||' | head -1)

		if [ -z "$github_repo" ]; then
			github_repo=$(grep -oE 'https?://(www\.)?github\.com/[^/[:space:]>)]*/[^/[:space:]> *]' "$index_file" | head -n 1)
		fi

		if [ -z "$github_repo" ]; then
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
				skipped_count=$((skipped_count + 1))
			elif [ "$all_assets" = "no_asset" ]; then
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

		old_urls=$(grep -oE 'https?://(www\.)?github\.com/[^"]*/releases/download[^"]*' "$index_file" | tr -d '"')

		if [ -z "$old_urls" ]; then
			skipped_count=$((skipped_count + 1))
			continue
		fi

		is_file_updated=0

		while IFS= read -r old_url; do
			[ -z "$old_url" ] && continue

			new_url=$(match_architecture "$old_url" "$all_assets")

			if [ -z "$new_url" ] || [ "$old_url" = "$new_url" ]; then
				continue
			fi

			old_escaped=$(escape_sed "$old_url")
			new_escaped=$(escape_sed "$new_url")

			sed_in_place "s|$old_escaped|$new_escaped|g" "$index_file"
			is_file_updated=1
		done <<EOF
$old_urls
EOF

		if [ $is_file_updated -eq 1 ]; then
			echo "✓ $app_name: ссылки успешно обновлены"
			updated_count=$((updated_count + 1))
		else
			skipped_count=$((skipped_count + 1))
		fi
	done

	echo ""
	echo "=== Итоги ==="
	echo "Обновлено файлов: $updated_count"
	echo "Пропущено/Актуально: $skipped_count"
	echo "Ошибок: $error_count"
}

main "$@"
