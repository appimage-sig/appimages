#! /usr/bin/bash

title=$(awk -F '[<>]' '/id/{print $4}' $1 | head -n1 | sed 's/\.*\./&\n/g'| sed -n 3p | tr -d '.' )
summary=$(awk -F '[<>]' '/summary/{print $3}' $1 | head -n1)
author=$(awk -F '[<>]' '/developer_name/{print $3}' $1 | head -n1)
license=$(awk -F '[<>]' '/project_license/{print $3}' $1)
screenshot=$(awk -F '[<>]' '/image/{print $3}' $1 | grep https | head -n1)
homepage=$(awk -F '[<>]' '/homepage/{print $3}' $1)
source=$(awk -F '[<>]' '/vcs-browser/{print $3}' $1)
donation=$(awk -F '[<>]' '/donation/{print $3}' $1)
bugtracker=$(awk -F '[<>]' '/bugtracker/{print $3}' $1)
translate=$(awk -F '[<>]' '/translate/{print $3}' $1)
contribute=$(awk -F '[<>]' '/contribute/{print $3}' $1)
# gh_download=$(curl -s https://api.github.com/repos/"$source"/releases/latest | grep "browser_download_url.*AppImage" | cut -d : -f 2,3 | tr -d \"))
# screenshot=$(cat $1 | grep "<image>" | head -n1 | tr -d '<>,' | cut -c5- )

echo "---
title: $title
description: |
$summary
pubDate:
categories:
authors: $author
license: $license
draft: false
---
$screenshot

$summary

License: $license

Web page: $homepage
Source code: <$source>

Become a sponsor: <$donation>
Translate: <$translate>

Report the bug: <$bugtracker>

Download:  <https://>" >> ~/apps-for-linux.github.io/content/apps/$title.md

