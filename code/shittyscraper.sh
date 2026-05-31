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
	# Исправлено формирование корректного пути к API
	api_url="https://api.github.com/${repo_owner}/${repo_name}/releases/latest"

	if [ -n "$GITHUB_TOKEN" ]; then
		response=$(curl -s -H "Accept: application/vnd.github.v3+json" -H "Authorization: token ${GITHUB_TOKEN}" "$api_url" || echo "{}")
	else
		response=$(curl -s -H "Accept: application/vnd.github.v3+json" "$api_url" || echo "{}")
	fi

	# Проверяем ошибки API одной строкой
	if echo "$response" | grep -q "API rate limit exceeded"; then echo "rate_limit"; return 1; fi
	if echo "$response" | grep -q "\"message\".*\"Not Found\""; then echo "404"; return 1; fi

		if [ -z "$urls" ]; then
		if echo "$response" | grep -q "\"tag_name\""; then echo "no_asset"; else echo "no_release"; fi
		return 1
	fi

	echo "$urls"
	return 0
}

parse_github_url() {
	# Удаляем пробелы и скобки на конце
	url_stripped=$(echo "$1" | sed 's/[>)\s]*$//')
	
	# Безопасно отсекаем протокол и домен (работает в любом POSIX sh)
	# Сначала убираем схему https://github.com/ или http://github.com
	clean_url=$(echo "$url_stripped" | sed 's|^https*://[w.]*github\.com/||')
	# На случай, если ссылка была без протокола (просто ://github.com)
	clean_url=$(echo "$clean_url" | sed 's|^github\.com/||')

	# Выделяем owner и repo
	owner=$(echo "$clean_url" | cut -d'/' -f1)
	repo=$(echo "$clean_url" | cut -d'/' -f2)

	if [ -z "$owner" ] || [ -z "$repo" ]; then
		return 1
	fi
	echo "${owner}/${repo}"
	return 0
}

escape_sed() {
	echo "$1" | sed 's/[\/&]/\\&/g'
}

match_architecture() {
	old_url="$1"
	all_new_urls="$2"

	arch="default"
	
	if echo "$old_url" | grep -qiE "(arm64|aarch64)"; then
		arch="arm64"
	elif echo "$old_url" | grep -qiE "(armv7|armhf)"; then
		arch="armv7"
	elif echo "$old_url" | grep -qiE "(x86_64|x64|amd64)"; then
		arch="x64"
	fi

	# 1. Попытка точного совпадения по известной архитектуре
	if [ "$arch" != "default" ]; then
		for new_url in $all_new_urls; do
			if [ "$arch" = "arm64" ]; then
				if echo "$new_url" | grep -qiE "(arm64|aarch64)"; then echo "$new_url"; return 0; fi
			elif [ "$arch" = "armv7" ]; then
				if echo "$new_url" | grep -qiE "(armv7|armhf)"; then echo "$new_url"; return 0; fi
			elif [ "$arch" = "x64" ]; then
				if ! echo "$new_url" | grep -qiE "(arm64|aarch64|armv7|armhf)"; then
					if echo "$new_url" | grep -qiE "(x86_64|x64|amd64)"; then echo "$new_url"; return 0; fi
				fi
			fi
		done
	fi

	# 2. Резервный план: если старая ссылка не содержит архитектуру (напр. app.AppImage)
	for new_url in $all_new_urls; do
		if ! echo "$new_url" | grep -qiE "(arm64|aarch64|armv7|armhf)"; then
			echo "$new_url"
			return 0
		fi
	done

	# 3. Если вообще ничего не отфильтровалось, отдаем первую доступную ссылку
	echo "$all_new_urls" | head -n 1
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

		# Ищем репозиторий GitHub в блоке релизов
		github_repo=$(grep -o 'https://github\.com/[^/]*/[^/]*/releases/download' "$index_file" | sed 's|/releases/download||' | head -1)

		if [ -z "$github_repo" ]; then
			# Исправлено регулярное выражение (удален ломающий логику пробел в конце)
			github_repo=$(grep -o "https://github\.com/[^/[:space:]>)]*/[^/[:space:]>)]*" "$index_file" | head -n 1)
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

		repo_owner=$(echo "$repo_info" | cut -d'/' -f1)
		repo_name=$(echo "$repo_info" | cut -d'/' -f2)

		all_assets=$(get_all_github_assets "$repo_owner" "$repo_name")
		asset_status=$?

		if [ $asset_status -ne 0 ]; then
			if [ "$all_assets" = "no_release" ]; then
				echo "⊘ $app_name: нет релизов в репозитории $repo_info"
				skipped_count=$((skipped_count + 1))
			elif [ "$all_assets" = "no_asset" ]; then
				echo "⊘ $app_name: релиз найден, но нет .AppImage в $repo_info"
				skipped_count=$((skipped_count + 1))
			elif [ "$all_assets" = "404" ]; then
				echo "✗ $app_name: репозиторий не найден ($repo_info)"
				error_count=$((error_count + 1))
			elif [ "$all_assets" = "rate_limit" ]; then
				echo "✗ Превышен лимит запросов GitHub API."
				error_count=$((error_count + 1))
			fi
			continue
		fi

		old_urls=$(grep -o 'https://github\.com/[^"]*\(releases/download\)[^"]*' "$index_file" | tr -d '"')

		if [ -z "$old_urls" ]; then
			echo "⚠ GitHub ссылки на скачивание не найдены в $app_name"
			skipped_count=$((skipped_count + 1))
			continue
		fi

		is_file_updated=0

		for old_url in $old_urls; do
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

		if [ $is_file_updated -eq 1 ]; then
			echo "✓ $app_name: ссылки успешно обновлены"
			updated_count=$((updated_count + 1))
		else
			echo "✓ $app_name: все ссылки уже актуальны"
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