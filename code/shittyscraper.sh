#!/bin/sh

set -eux

CONTENT_DIR="content/apps"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
LOCK_FILE="/tmp/github-updater.lock"
MAX_RETRIES=3
RETRY_DELAY=5

# Проверка зависимостей
check_dependencies() {
	for cmd in curl jq sed; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			echo "✗ Ошибка: требуется установить '$cmd'"
			exit 1
		fi
	done
}

# Безопасный lock для предотвращения одновременного запуска
acquire_lock() {
	if [ -f "$LOCK_FILE" ]; then
		old_pid=$(cat "$LOCK_FILE" 2>/dev/null)
		if kill -0 "$old_pid" 2>/dev/null; then
			echo "✗ Скрипт уже запущен (PID: $old_pid)"
			exit 1
		fi
		rm -f "$LOCK_FILE"
	fi
	echo $$ >"$LOCK_FILE"
}

release_lock() {
	rm -f "$LOCK_FILE"
}

trap release_lock EXIT

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

	local attempt=1
	while [ $attempt -le $MAX_RETRIES ]; do
		response=$(curl -s -w "\n%{http_code}" \
			-H "Accept: application/vnd.github.v3+json" \
			${GITHUB_TOKEN:+-H "Authorization: token ${GITHUB_TOKEN}"} \
			"$api_url" 2>&1)
		
		http_code=$(echo "$response" | tail -1)
		response=$(echo "$response" | head -n -1)

		case "$http_code" in
			200)
				break
				;;
			404)
				echo "404"
				return 1
				;;
			403)
				if echo "$response" | grep -q "API rate limit exceeded"; then
					echo "rate_limit"
					return 1
				fi
				;;
			429)
				echo "rate_limit"
				return 1
				;;
			*)
				if [ $attempt -lt $MAX_RETRIES ]; then
					echo "⚠ Попытка $attempt/$MAX_RETRIES: HTTP $http_code, повторяем через ${RETRY_DELAY}с..."
					sleep "$RETRY_DELAY"
					attempt=$((attempt + 1))
					continue
				else
					echo "http_error_$http_code"
					return 1
				fi
				;;
		esac
	done

	# Парсим JSON с помощью jq
	urls=$(echo "$response" | jq -r '.assets[]? | select(.name | endswith(".AppImage")) | .browser_download_url' 2>/dev/null)

	if [ -z "$urls" ]; then
		if echo "$response" | jq -e '.tag_name' >/dev/null 2>&1; then
			echo "no_asset"
		else
			echo "no_release"
		fi
		return 1
	fi

	echo "$urls"
	return 0
}

parse_github_url() {
	url="$1"
	
	# Удаляем пробелы и специальные символы на конце
	url=$(echo "$url" | sed 's/[>)\s]*$//')
	
	# Убираем протокол и домен
	clean_url=$(echo "$url" | sed -E 's|^https?://(www\.)?github\.com/||')
	
	# Выделяем owner и repo
	owner=$(echo "$clean_url" | cut -d'/' -f1)
	repo=$(echo "$clean_url" | cut -d'/' -f2 | sed 's/\.git$//')

	if [ -z "$owner" ] || [ -z "$repo" ]; then
		return 1
	fi
	
	echo "${owner}/${repo}"
	return 0
}

escape_sed() {
	echo "$1" | sed 's/[\/&]/\\&/g'
}

# Определяем архитектуру старой ссылки
detect_arch() {
	url="$1"
	
	if echo "$url" | grep -iqE "(arm64|aarch64)"; then
		echo "arm64"
	elif echo "$url" | grep -iqE "(armv7|armhf)"; then
		echo "armv7"
	elif echo "$url" | grep -iqE "(x86_64|x64|amd64)"; then
		echo "x64"
	else
		echo "default"
	fi
}

# Улучшенная функция подбора архитектуры
match_architecture() {
	old_url="$1"
	all_new_urls="$2"

	arch=$(detect_arch "$old_url")

	case "$arch" in
		arm64)
			echo "$all_new_urls" | grep -iE "(arm64|aarch64)" | head -1
			return $?
			;;
		armv7)
			echo "$all_new_urls" | grep -iE "(armv7|armhf)" | head -1
			return $?
			;;
		x64)
			# Исключаем ARM версии
			echo "$all_new_urls" | grep -vE "(arm64|aarch64|armv7|armhf)" | head -1
			return $?
			;;
		*)
			# Для неизвестной архитектуры берем первую non-ARM версию
			echo "$all_new_urls" | grep -vE "(arm64|aarch64|armv7|armhf)" | head -1
			if [ $? -eq 0 ]; then
				return 0
			fi
			# Если non-ARM нет, берем первую доступную
			echo "$all_new_urls" | head -1
			return 0
			;;
	esac
}

main() {
	check_dependencies
	acquire_lock

	if [ ! -d "$CONTENT_DIR" ]; then
		echo "✗ Папка $CONTENT_DIR не найдена"
		exit 1
	fi

	updated_count=0
	skipped_count=0
	error_count=0

	echo "════════════════════════════════════════"
	echo "  Начинаем обновление GitHub ссылок"
	echo "════════════════════════════════════════"
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
			# Поиск простой ссылки на GitHub
			github_repo=$(grep -oE 'https://github\.com/[^/[:space:]>)]+/[^/[:space:]>)]+' "$index_file" | head -1)
		fi

		if [ -z "$github_repo" ]; then
			echo "⊘ Пропущено: $app_name (GitHub ссылки не найдены)"
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

		echo "→ Проверяем: $app_name ($repo_owner/$repo_name)"

		all_assets=$(get_all_github_assets "$repo_owner" "$repo_name")
		asset_status=$?

		if [ $asset_status -ne 0 ]; then
			case "$all_assets" in
				no_release)
					echo "  ⊘ Нет релизов в репозитории"
					skipped_count=$((skipped_count + 1))
					;;
				no_asset)
					echo "  ⊘ Релиз найден, но нет .AppImage"
					skipped_count=$((skipped_count + 1))
					;;
				404)
					echo "  ✗ Репозиторий не найден ($repo_owner/$repo_name)"
					error_count=$((error_count + 1))
					;;
				rate_limit)
					echo "  ✗ Превышен лимит запросов GitHub API"
					error_count=$((error_count + 1))
					;;
				*)
					echo "  ✗ Ошибка API: $all_assets"
					error_count=$((error_count + 1))
					;;
			esac
			continue
		fi

		# Находим все старые ссылки на скачивание
		old_urls=$(grep -oE 'https://github\.com/[^"]*releases/download[^"]*' "$index_file" || true)

		if [ -z "$old_urls" ]; then
			echo "  ⚠ Ссылки на скачивание не найдены"
			skipped_count=$((skipped_count + 1))
			continue
		fi

		is_file_updated=0
		updated_urls=0

		# Обрабатываем каждую старую ссылку
		echo "$old_urls" | while IFS= read -r old_url; do
			[ -z "$old_url" ] && continue

			new_url=$(match_architecture "$old_url" "$all_assets")

			if [ -z "$new_url" ]; then
				echo "    ⚠ Не найдена замена для: ${old_url##*/}"
				continue
			fi

			if [ "$old_url" = "$new_url" ]; then
				echo "    ✓ Ссылка уже актуальна: ${old_url##*/}"
				continue
			fi

			old_escaped=$(escape_sed "$old_url")
			new_escaped=$(escape_sed "$new_url")

			if sed_in_place "s|$old_escaped|$new_escaped|g" "$index_file"; then
				echo "    ✓ Обновлено: ${old_url##*/} → ${new_url##*/}"
				is_file_updated=1
			else
				echo "    ✗ Ошибка при замене ссылки"
			fi
		done

		if [ $is_file_updated -eq 1 ]; then
			echo "  ✓ Файл успешно обновлен"
			updated_count=$((updated_count + 1))
		else
			echo "  ○ Все ссылки уже актуальны"
			skipped_count=$((skipped_count + 1))
		fi
		echo ""

	done

	echo "════════════════════════════════════════"
	echo "  Итоговый отчет"
	echo "════════════════════════════════════════"
	echo "✓ Обновлено файлов:      $updated_count"
	echo "○ Пропущено/Актуально:   $skipped_count"
	echo "✗ Ошибок:                $error_count"
	echo ""

	if [ $error_count -gt 0 ]; then
		exit 1
	fi
}

main "$@"
