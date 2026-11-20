#!/bin/sh

SEARCH_DIR="${1:-.}"

# Проверяем, существует ли переданная директория
if [ ! -d "$SEARCH_DIR" ]; then
    echo "Ошибка: директория '$SEARCH_DIR' не найдена." >&2
    exit 1
fi

missing_count=0
tmp_list=$(mktemp) || exit 1

# Гарантируем удаление временного файла при выходе или прерывании
trap 'rm -f "$tmp_list"' EXIT INT TERM

# Генерируем символ возврата каретки (CR) для совместимости с POSIX
cr=$(printf '\r')

find "$SEARCH_DIR" -type f -name "index.md" | while IFS= read -r file; do
    # Ищем строку с ключом и разделителем '=' (исключая закомментированные строки)
    line=$(grep -E '^[[:space:]]*metadata[[:space:]]*=' "$file" | head -n 1)

    if [ -z "$line" ]; then
        printf '%s\n' "$file" >>"$tmp_list"
    else
        # 1. Удаляем ключ до первого знака равно и пробелы после него
        # 2. Удаляем inline-комментарии (пробел и # до конца строки)
        # 3. Убираем кавычки, пробелы и символ CR
        val=$(printf '%s' "$line" | sed -E \
            -e 's/^[^=]*=[[:space:]]*//' \
            -e 's/[[:space:]]+#.*$//' \
            -e "s/[\"'[:space:]${cr}]//g")

        if [ -z "$val" ] || [ "$val" = "null" ] || [ "$val" = "~" ]; then
            printf '%s\n' "$file" >>"$tmp_list"
        fi
    fi
done

if [ -s "$tmp_list" ]; then
    echo "Файлы без заполненного metadata:"
    cat "$tmp_list"
    missing_count=$(wc -l <"$tmp_list" | tr -d ' ')
else
    echo "Во всех проверенных файлах поле metadata заполнено."
fi

echo "----------------------------------------"
echo "Итого файлов с пустым или отсутствующим полем: $missing_count"
