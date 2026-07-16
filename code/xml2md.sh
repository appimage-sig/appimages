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
date=$(grep date= | head -n1 | sed -n 's/.*date="\([^"]*\)".*/\1/p' )
# gh_download=$(curl -s https://api.github.com/repos/"$source"/releases/latest | grep "browser_download_url.*AppImage" | cut -d : -f 2,3 | tr -d \"))
# screenshot=$(cat $1 | grep "<image>" | head -n1 | tr -d '<>,' | cut -c5- )

echo "+++
title = \"$title\"
description = \"$summary\"
date = "$date"
[taxonomies]
categories =
authors = [\"$author\"]
tags =
frameworks = [\"Electron\"]
architectures = [\"x86_64\"]
license = [\"$license\"]
+++

<img src="$screenshot" alt="Main screenshot">

$summary

License: $license

Web page: <$homepage>
Source code: <$source>

Become a sponsor: <$donation>
Translate: <$translate>

Report the bug: <$bugtracker>

<div class="d_buttons">
<button class="c-button c-button--primary c-button--large"
    <a href="">Download x86_64</a>
</button>
<button class="c-button c-button--primary c-button--large"
    <a href="">Download arm64</a>
</button>
<button class="c-button c-button--primary c-button--large"
    <a href="">Download x86</a>
</button>
<button class="c-button c-button--primary c-button--large"
    <a href="">Download armv7l</a>
</button>
<button class="c-button c-button--primary c-button--large"
    <a href="">Download riscv64</a>
</button>
<button class="c-button c-button--primary c-button--large"
    <a href="">Download ppc64el</a>
</button>
</div>" >> ~/apps-for-linux.github.io/content/apps/$title.md
