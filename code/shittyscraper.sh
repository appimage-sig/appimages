set -euo pipefail

# Конфигурация
CONTENT_DIR="content"
GITHUB_API_BASE="https://api.github.com/repos"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"  # Установите переменную окружения для увеличения лимита API

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для получения ссылки на latest релиз из GitHub
get_latest_github_release() {
    local repo_owner="$1"
    local repo_name="$2"
    local asset_pattern="${3:-.AppImage}"  # По умолчанию ищем .AppImage файлы
    
    local api_url="${GITHUB_API_BASE}/${repo_owner}/${repo_name}/releases/latest"
    local headers="-H 'Accept: application/vnd.github.v3+json'"
    
    if [[ -n "$GITHUB_TOKEN" ]]; then
        headers="${headers} -H 'Authorization: token ${GITHUB_TOKEN}'"
    fi
    
    # Получаем информацию о latest релизе
    local response=$(curl -s ${headers} "$api_url" 2>/dev/null || echo "{}")
    
    # Проверяем на ошибку
    if echo "$response" | grep -q "\"message\".*\"Not Found\""; then
        echo ""
        return 1
    fi
    
    # Извлекаем URL первого подходящего ассета
    local download_url=$(echo "$response" | grep -o "\"browser_download_url\": \"[^\"]*${asset_pattern}[^\"]*\"" | head -1 | cut -d'"' -f4)
    
    if [[ -n "$download_url" ]]; then
        echo "$download_url"
        return 0
    else
        echo ""
        return 1
    fi
}

# Функция для извлечения owner/repo из ссылки GitHub
parse_github_url() {
    local url="$1"
    # Примеры: https://github.com/owner/repo или https://github.com/owner/repo/releases
    if [[ $url =~ github\.com/([^/]+)/([^/]+) ]]; then
        echo "${BASH_REMATCH}/${BASH_REMATCH}"
        return 0
    fi
    return 1
}

# Функция для обновления ссылки в index.md
update_download_link() {
    local index_file="$1"
    local new_url="$2"
    local app_name="$3"
    
    if [[ ! -f "$index_file" ]]; then
        echo -e "${RED}✗ Файл не найден: $index_file${NC}"
        return 1
    fi
    
    # Ищем строку с Download ссылкой (поддерживаем разные форматы)
    # Форматы: [Download](url), Download: url, download_url: url и т.д.
    local old_url=$(grep -oP '(?<=\[Download\]\(|download[_:]?\s*)[^)]*' "$index_file" | head -1)
    
    if [[ -z "$old_url" ]]; then
        echo -e "${YELLOW}⚠ Не найдена ссылка Download в $index_file${NC}"
        return 1
    fi
    
    # Если ссылки одинаковые, обновление не требуется
    if [[ "$old_url" == "$new_url" ]]; then
        echo -e "${GREEN}✓ $app_name: ссылка актуальна${NC}"
        return 0
    fi
    
    # Заменяем ссылку (поддерживаем разные форматы)
    sed -i "s|${old_url//|/\\|}|${new_url//|/\\|}|g" "$index_file"
    
    echo -e "${GREEN}✓ $app_name: обновлена ссылка${NC}"
    echo -e "  ${YELLOW}Было:${NC} $old_url"
    echo -e "  ${GREEN}Стало:${NC} $new_url"
    
    return 0
}

# Основной цикл
main() {
    if [[ ! -d "$CONTENT_DIR" ]]; then
        echo -e "${RED}✗ Папка $CONTENT_DIR не найдена${NC}"
        exit 1
    fi
    
    local updated_count=0
    local skipped_count=0
    local error_count=0
    
    echo -e "${YELLOW}Начинаем обновление ссылок...${NC}\n"
    
    # Проходим по каждой папке приложения
    for app_dir in "$CONTENT_DIR"/*; do
        if [[ ! -d "$app_dir" ]]; then
            continue
        fi
        
        local app_name=$(basename "$app_dir")
        local index_file="$app_dir/index.md"
        
        if [[ ! -f "$index_file" ]]; then
            echo -e "${YELLOW}⚠ Пропущено: $app_name (нет index.md)${NC}"
            ((skipped_count++))
            continue
        fi
        
        # Ищем ссылку на GitHub репозиторий в index.md
        local github_repo=$(grep -oP 'https://github\.com/[^/]+/[^/\s)]+' "$index_file" | head -1)
        
        if [[ -z "$github_repo" ]]; then
            echo -e "${YELLOW}⚠ $app_name: GitHub репозиторий не найден${NC}"
            ((skipped_count++))
            continue
        fi
        
        # Парсим owner/repo
        local repo_info=$(parse_github_url "$github_repo")
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}✗ $app_name: не удалось распарсить URL${NC}"
            ((error_count++))
            continue
        fi
        
        # Получаем latest релиз
        local new_url=$(get_latest_github_release "$repo_info" ".AppImage")
        if [[ $? -ne 0 ]] || [[ -z "$new_url" ]]; then
            echo -e "${RED}✗ $app_name: не удалось получить latest релиз${NC}"
            ((error_count++))
            continue
        fi
        
        # Обновляем ссылку
        if update_download_link "$index_file" "$new_url" "$app_name"; then
            ((updated_count++))
        else
            ((error_count++))
        fi
    done
    
    # Итоги
    echo -e "\n${YELLOW}=== Итоги ===${NC}"
    echo -e "${GREEN}Обновлено: $updated_count${NC}"
    echo -e "${YELLOW}Пропущено: $skipped_count${NC}"
    echo -e "${RED}Ошибок: $error_count${NC}"
}

# Запуск
main "$@"
