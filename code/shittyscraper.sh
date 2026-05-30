#!/bin/sh

set -eux

# Конфигурация
CONTENT_DIR="content"
GITHUB_API_BASE="https://api.github.com/repos"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Функция для получения ссылки на latest релиз из GitHub
get_latest_github_release() {
    repo_owner="$1"
    repo_name="$2"
    asset_pattern="${3:-.AppImage}"
    
    api_url="${GITHUB_API_BASE}/${repo_owner}/${repo_name}/releases/latest"
    
    headers="-H 'Accept: application/vnd.github.v3+json'"
    if [ -n "$GITHUB_TOKEN" ]; then
        headers="${headers} -H 'Authorization: token ${GITHUB_TOKEN}'"
    fi
    
    response=$(eval "curl -s $headers '$api_url'" 2>/dev/null || echo "{}")
    
    # Проверяем на 404 (репозиторий не найден)
    if echo "$response" | grep -q "\"message\".*\"Not Found\""; then
        echo "404"
        return 1
    fi
    
    # Проверяем на "No releases here" или пустой массив релизов
    if echo "$response" | grep -q "\"message\".*\"release\""; then
        echo "no_release"
        return 1
    fi
    
    if echo "$response" | grep -q "\"message\".*\"not found\""; then
        echo "no_release"
        return 1
    fi
    
    download_url=$(echo "$response" | grep -o "\"browser_download_url\": \"[^\"]*${asset_pattern}[^\"]*\"" | head -1 | cut -d'"' -f4)
    
    # Если релиз найден но нет нужного файла
    if [ -z "$download_url" ]; then
        # Проверяем есть ли вообще релиз
        if echo "$response" | grep -q "\"tag_name\""; then
            echo "no_asset"
            return 1
        else
            echo "no_release"
            return 1
        fi
    fi
    
    echo "$download_url"
    return 0
}

# Функция для извлечения owner/repo из ссылки GitHub
parse_github_url() {
    url="$1"
    url=$(echo "$url" | sed 's/[>)\s]*$//')
    
    case "$url" in
        *github.com/*)
            owner=$(echo "$url" | sed 's|.*github\.com/\([^/]*\)/.*|\1|')
            repo=$(echo "$url" | sed 's|.*github\.com/[^/]*/\([^/]*\).*|\1|')
            echo "${owner}/${repo}"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Функция для экранирования специальных символов в sed
escape_sed() {
    echo "$1" | sed 's/[\/&]/\\&/g'
}

# Функция для обновления ссылки в index.md
update_download_link() {
    index_file="$1"
    new_url="$2"
    app_name="$3"
    
    if [ ! -f "$index_file" ]; then
        echo -e "${RED}✗ Файл не найден: $index_file${NC}"
        return 1
    fi
    
    # Ищем ссылку в формате href="..."
    old_url=$(grep 'href="[^"]*github\.com[^"]*' "$index_file" | head -1 | sed 's/.*href="\([^"]*\)".*/\1/')
    
    # Если не найдено в href, ищем в других форматах
    if [ -z "$old_url" ]; then
        old_url=$(grep -o 'https://github\.com/[^/]*/[^/)]\+' "$index_file" | head -1)
    fi
    
    # Если всё ещё не найдено
    if [ -z "$old_url" ]; then
        echo -e "${YELLOW}⚠ Не найдена ссылка Download в $index_file${NC}"
        return 1
    fi
    
    if [ "$old_url" = "$new_url" ]; then
        echo -e "${GREEN}✓ $app_name: ссылка актуальна${NC}"
        return 0
    fi
    
    # Экранируем слеши для sed
    old_escaped=$(escape_sed "$old_url")
    new_escaped=$(escape_sed "$new_url")
    
    sed -i "s|$old_escaped|$new_escaped|g" "$index_file"
    
    echo -e "${GREEN}✓ $app_name: обновлена ссылка${NC}"
    echo -e "  ${YELLOW}Было:${NC} $old_url"
    echo -e "  ${GREEN}Стало:${NC} $new_url"
    
    return 0
}

# Функция для поиска index.md рекурсивно
find_index_md() {
    start_dir="$1"
    find "$start_dir" -maxdepth 10 -name "index.md" -type f | head -1
}

# Основной цикл
main() {
    if [ ! -d "$CONTENT_DIR" ]; then
        echo -e "${RED}✗ Папка $CONTENT_DIR не найдена${NC}"
        exit 1
    fi
    
    updated_count=0
    skipped_count=0
    error_count=0
    
    echo -e "${YELLOW}Начинаем обновление ссылок...${NC}\n"
    
    for app_dir in "$CONTENT_DIR"/*; do
        if [ ! -d "$app_dir" ]; then
            continue
        fi
        
        app_name=$(basename "$app_dir")
        index_file=$(find_index_md "$app_dir")
        
        if [ -z "$index_file" ] || [ ! -f "$index_file" ]; then
            echo -e "${YELLOW}⚠ Пропущено: $app_name (нет index.md)${NC}"
            skipped_count=$((skipped_count + 1))
            continue
        fi
        
        # Парсим GitHub URL более аккуратно
        github_repo=$(sed -n 's/.*\(https:\/\/github\.com\/[^\/]*\/[^\/[:space:]>)]*\).*/\1/p' "$index_file" | head -1)
        
        if [ -z "$github_repo" ]; then
            echo -e "${YELLOW}⚠ $app_name: GitHub репозиторий не найден${NC}"
            skipped_count=$((skipped_count + 1))
            continue
        fi
        
        repo_info=$(parse_github_url "$github_repo")
        if [ $? -ne 0 ]; then
            echo -e "${RED}✗ $app_name: не удалось распарсить URL: $github_repo${NC}"
            error_count=$((error_count + 1))
            continue
        fi
        
        new_url=$(get_latest_github_release "$repo_info" ".AppImage")
        release_status=$?
        
        if [ $release_status -ne 0 ]; then
            if [ "$new_url" = "no_release" ]; then
                echo -e "${YELLOW}⊘ $app_name: нет релизов в репозитории $repo_info${NC}"
                skipped_count=$((skipped_count + 1))
            elif [ "$new_url" = "no_asset" ]; then
                echo -e "${YELLOW}⊘ $app_name: релиз найден, но нет .AppImage файла в $repo_info${NC}"
                skipped_count=$((skipped_count + 1))
            elif [ "$new_url" = "404" ]; then
                echo -e "${RED}✗ $app_name: репозиторий не найден ($repo_info)${NC}"
                error_count=$((error_count + 1))
            else
                echo -e "${RED}✗ $app_name: не удалось получить latest релиз для $repo_info${NC}"
                error_count=$((error_count + 1))
            fi
            continue
        fi
        
        if [ -z "$new_url" ]; then
            echo -e "${RED}✗ $app_name: не удалось получить URL релиза${NC}"
            error_count=$((error_count + 1))
            continue
        fi
        
        if update_download_link "$index_file" "$new_url" "$app_name"; then
            updated_count=$((updated_count + 1))
        else
            error_count=$((error_count + 1))
        fi
    done
    
    echo -e "\n${YELLOW}=== Итоги ===${NC}"
    echo -e "${GREEN}Обновлено: $updated_count${NC}"
    echo -e "${YELLOW}Пропущено: $skipped_count${NC}"
    echo -e "${RED}Ошибок: $error_count${NC}"
}

main "$@"
