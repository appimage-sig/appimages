#! /usr/bin/sh

### 1. open file
### 2. check previous link
### 3. export data
### 4. check next link with github api
### 5. export link
### 6. replace link

# Log all output to a file
LOG=updater.log
exec > >(tee -a "${LOG}") 2>&1


dir=$HOME/apps-for-linux.github.io/content/apps

repo=$( cat *.md | grep "Download" | cut -c 20 | sed -r 's/releases.+//' | sed '$ s/.$//' )

current_version=$(curl -s https://api.github.com/repos/"$repo"/releases/latest | grep "browser_download_url.*AppImage" | cut -d : -f 2,3 | tr -d \")
previous_version=$(grep "Download" | cut -c12- | tr -d '>')

for file in "$dir"/*.md; do
    sed -i "s|$previous_version|$current_version|g" "$file"
done
