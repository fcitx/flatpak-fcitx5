#!/bin/bash

get_tag() {
    gh api repos/fcitx/$1/tags --jq .[].name --paginate | sort -r -V | head -n 1
}

get_commit() {
    gh api repos/fcitx/$1/commits/$2 --jq .sha
}

printarr() { declare -n __p="$1"; for k in "${!__p[@]}"; do printf "%s=%s\n" "$k" "${__p[$k]}" ; done ;  }

update_tag() {
    for k in "${!repo_tag[@]}"; do
        repo_info="${repo_tag[$k]}"
        if [[ "$repo_info" =~ ^tag: ]]; then
            yq -y -i '(.. |select(.sources?) | .sources[]? | select(.type == "git" and .url == "https://github.com/fcitx/'$k'")) .tag = "'${repo_info/tag:/}'"' $1
        elif [[ "$repo_info" =~ ^commit: ]]; then
            yq -y -i '(.. |select(.sources?) | .sources[]? | select(.type == "git" and .url == "https://github.com/fcitx/'$k'")) .commit = "'${repo_info/commit:/}'"' $1
            yq -y -i '(.. |select(.sources?) | .sources[]? | select(.type == "git" and .url == "https://github.com/fcitx/'$k'")) |= del(.branch)' $1
        fi
    done
}

if [[ "$1" == "" ]]; then
    echo "Need to provide a flatpak package name"
    exit 1
fi

declare -A repo_tag

REPO=
while read repo package option; do
    if [[ "$option" =~ ^branch: ]]; then
        repo_tag[$repo]=commit:$(get_commit $repo ${option/branch:/})
    else
        repo_tag[$repo]=tag:$(get_tag $repo)
    fi

    if [[ "$package" == "$1" ]]; then
        REPO=$repo
    fi
done < projects

PACKAGE=$1

printarr repo_tag

rm -rf $PACKAGE
gh repo clone flathub/$PACKAGE

cp $PACKAGE.yaml $PACKAGE/$PACKAGE.yaml

for module in $(yq -r '.modules[] | select(type == "string" and startswith("modules/"))' $PACKAGE/$PACKAGE.yaml); do
    mkdir -p $PACKAGE/modules
    cp $module $PACKAGE/$module
    update_tag $PACKAGE/$module
done

yq -y -i '.branch = "stable"' $PACKAGE/$PACKAGE.yaml
if [[ "$PACKAGE" =~ .*Addon.* ]]; then
    yq -y -i '."runtime-version" = "stable"' $PACKAGE/$PACKAGE.yaml
else
    yq -y -i '."add-extensions"."org.fcitx.Fcitx5.Addon".version = "stable"' $PACKAGE/$PACKAGE.yaml
fi

update_tag $PACKAGE/$PACKAGE.yaml

cd $PACKAGE
LABEL=${repo_tag[$REPO]/:/-}
git checkout -b pr-$LABEL
git commit -a -m "Update $PACKAGE"
git push origin --force pr-$LABEL
gh pr create --base master --title "Update $LABEL" --body ""
