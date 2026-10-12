#!/bin/bash

SCRIPT_PATH="$(realpath "${BASH_SOURCE[-1]}")"
SCRIPT_DIRECTORY="$(dirname "$SCRIPT_PATH")"
source "${SCRIPT_DIRECTORY}/functions.sh"

printarr() { declare -n __p="$1"; for k in "${!__p[@]}"; do printf "%s=%s\n" "$k" "${__p[$k]}" ; done ;  }

clean_output_repo() {
    local repo_dir="$1"
    local repo_abs
    repo_abs=$(realpath "$repo_dir")
    local workspace_abs
    workspace_abs=$(realpath "$SCRIPT_DIRECTORY")

    # Refuse dangerous paths and anything outside this workspace.
    if [[ -z "$repo_abs" || "$repo_abs" == "/" || "$repo_abs" == "$HOME" || "$repo_abs" == "$workspace_abs" ]]; then
        echo "Refusing to clean unsafe path: $repo_dir"
        return 1
    fi
    if [[ "$repo_abs" != "$workspace_abs"/* ]]; then
        echo "Refusing to clean path outside workspace: $repo_abs"
        return 1
    fi

    # Disposable-clone mode: reset/clean repository contents aggressively.
    git -C "$repo_abs" reset --hard HEAD
    git -C "$repo_abs" clean -ffdqx
}

uses_shared_modules() {
    local manifest="$1"
    yq -r '.. | .modules? // empty | .[]? | select(type == "string")' "$manifest" \
        | rg -q '^(\./)?shared-modules/|^(\.\./)+shared-modules/'
}

init_shared_modules_submodule_if_needed() {
    local repo_dir="$1"
    local manifest="$2"
    if ! uses_shared_modules "$manifest"; then
        return
    fi

    git -C "$repo_dir" checkout HEAD -- .gitmodules shared-modules
    git -C "$repo_dir" submodule update --init --recursive shared-modules
    git -C "$repo_dir/shared-modules" checkout "$SHARED_MODULE_SHA"
}

update_tag() {
    echo update_tag for $1
    for k in "${!repo_tag[@]}"; do
        local repo_info="${repo_tag[$k]}"
        if [[ "$repo_info" =~ ^tag: ]]; then
            local tag_commit="${repo_tag_commit[$k]}"
            yq -y -i '(.. |select(.sources?) | .sources[]? | select(.type? == "git" and .url? == "https://github.com/'$k'")) .tag = "'${repo_info/tag:/}'"' $1
            yq -y -i '(.. |select(.sources?) | .sources[]? | select(.type? == "git" and .url? == "https://github.com/'$k'")) .commit = "'${tag_commit}'"' $1
            yq -y -i '(.. |select(.sources?) | .sources[]? | select(.type? == "git" and .url? == "https://github.com/'$k'")) |= del(.branch)' $1
        elif [[ "$repo_info" =~ ^commit: ]]; then
            yq -y -i '(.. |select(.sources?) | .sources[]? | select(.type? == "git" and .url? == "https://github.com/'$k'")) .commit = "'${repo_info/commit:/}'"' $1
            yq -y -i '(.. |select(.sources?) | .sources[]? | select(.type? == "git" and .url? == "https://github.com/'$k'")) |= del(.branch)' $1
        fi
    done
}

update_cherry_pick() {
    rm -f $GIT_REPO/cp-*.patch

    local CHERRY_PICK_LIST_FILE="${REPO/\//-}"
    if [[ ! -f cherry-picks/${CHERRY_PICK_LIST_FILE} ]]; then
        return
    fi

    for commit in `cat cherry-picks/${CHERRY_PICK_LIST_FILE}`; do
        wget https://github.com/$REPO/commit/$commit.patch -O $GIT_REPO/cp-$commit.patch
        yq -y -i '(.. |select(.modules?) | .modules[]? | select(.name? == "fcitx5")).sources += [{"type": "patch", "path": "'cp-$commit.patch'", "use-git": true}] ' $1
    done
}

populate_modules() {
    local source_file="$1"
    local target_file="$2"
    local source_dir
    source_dir=$(dirname "$source_file")
    local target_dir
    target_dir=$(dirname "$target_file")
    local module
    local patch

    # Expand YAML module references recursively.
    while IFS= read -r module; do
        [[ -z "$module" ]] && continue
        local source_module="$source_dir/$module"
        local module_dir
        module_dir=$(dirname "$module")

        # Keep shared-modules references as-is in the final manifest.
        if [[ "${source_module#./}" == shared-modules/* ]]; then
            continue
        fi

        local target_module="$target_dir/$module"
        mkdir -p "$(dirname "$target_module")"
        cp "$source_module" "$target_module"
        update_tag "$target_module"
        populate_modules "$source_module" "$target_module"

        # Inlined modules are resolved from the top-level manifest, so normalize
        # any relative shared-modules references to the top-level shared path.
        yq -y -i 'if (.modules | type) == "array" then .modules |= map(if type == "string" then (sub("^\\./shared-modules/"; "shared-modules/") | sub("^(\\.\\./)+shared-modules/"; "shared-modules/")) else . end) else . end' "$target_module"

        # Flatten relative patch paths for inlined modules by copying them next
        # to the parent manifest and rewriting .path to the patch basename.
        while IFS= read -r inlined_patch; do
            [[ -z "$inlined_patch" ]] && continue
            local old_patch_path
            old_patch_path="$(dirname "$target_module")/$inlined_patch"
            cp "$old_patch_path" "$target_dir/$(basename "$inlined_patch")"
            rm -f "$old_patch_path"
        done < <(yq -r '.sources[]? | select(type == "object" and .type? == "patch" and (.path? | type) == "string" and (.path | startswith("/") | not) and (.path | test("^[A-Za-z]+://") | not)) | .path' "$target_module")

        yq -y -i 'if (.sources | type) == "array" then .sources |= map(if (type == "object" and .type? == "patch" and (.path? | type) == "string" and (.path | startswith("/") | not) and (.path | test("^[A-Za-z]+://") | not)) then .path |= (split("/") | last) else . end) else . end' "$target_module"

        # Inline non-shared YAML modules and remove temporary copied files.
        local module_json
        module_json=$(yq -c '.' "$target_module")
        yq -y -i --arg module "$module" --argjson module_obj "$module_json" '.modules |= map(if type == "string" and . == $module then $module_obj else . end)' "$target_file"
        rm -f "$target_module"
    done < <(yq -r '.modules[]? | select(type == "string" and endswith(".yaml"))' "$source_file")

    # JSON source manifests remain file-based and are copied next to the target manifest.
    while IFS= read -r module; do
        [[ -z "$module" ]] && continue
        local moduledir
        moduledir=$(dirname "$module")
        mkdir -p "$target_dir/$moduledir"
        cp "$source_dir/$module" "$target_dir/$module"
    done < <(yq -r '.. | select(.sources?) | .sources[]? | select(type == "string" and endswith("-sources.json"))' "$source_file")

    # Patch files are also copied so patch paths stay valid after inlining.
    while IFS= read -r patch; do
        [[ -z "$patch" ]] && continue
        echo cp "$source_dir/$patch" "$target_dir"
        cp "$source_dir/$patch" "$target_dir"
    done < <(yq -r '.. | select(.sources?) | .sources[]? | select(.type? == "patch") | .path' "$source_file")
}

if [[ "$1" == "" ]]; then
    echo "Need to provide a flatpak package name"
    exit 1
fi

declare -A repo_tag
declare -A repo_tag_commit

cd shared-modules
SHARED_MODULE_SHA=`git rev-parse HEAD`
cd ..

REPO=
while IFS=, read repo package option; do
    if [[ "$option" =~ ^branch: ]]; then
        repo_tag[$repo]=commit:$(get_commit $repo ${option/branch:/})
    else
        tag_name=$(get_tag $repo)
        repo_tag[$repo]=tag:$tag_name
        repo_tag_commit[$repo]=$(get_tag_commit $repo $tag_name)
    fi

    if [[ "$package" == "$1" ]]; then
        REPO=$repo
    fi
done < projects

PACKAGE=$1

GIT_REPO=$PACKAGE
if [[ "$2" == "new" ]]; then
    GIT_REPO=flathub
fi

printarr repo_tag

rm -rf $GIT_REPO
gh repo clone flathub/$GIT_REPO -- --recursive

if [[ "$2" == "new" ]]; then
    pushd .
    cd $GIT_REPO
    git checkout new-pr
    popd
fi

clean_output_repo "$GIT_REPO"

cp $PACKAGE.yaml $GIT_REPO/$PACKAGE.yaml

rm -rf $GIT_REPO/modules

populate_modules $PACKAGE.yaml $GIT_REPO/$PACKAGE.yaml

# Remove temporary module directory only if inlining left it empty.
rmdir "$GIT_REPO/modules" 2>/dev/null || true

yq -y -i 'del(.branch)' $GIT_REPO/$PACKAGE.yaml
if [[ "$PACKAGE" =~ .*Addon.* ]]; then
    cp flathub.json $GIT_REPO/
    yq -y -i '."runtime-version" = "stable"' $GIT_REPO/$PACKAGE.yaml
else
    yq -y -i '."add-extensions"."org.fcitx.Fcitx5.Addon".version = "stable"' $GIT_REPO/$PACKAGE.yaml
fi

if [[ $REPO == "fcitx/mozc" ]]; then
    cp mozc-deps.yaml $GIT_REPO/
fi

update_tag $GIT_REPO/$PACKAGE.yaml
update_cherry_pick $GIT_REPO/$PACKAGE.yaml

cd $GIT_REPO

init_shared_modules_submodule_if_needed "$PWD" "$PACKAGE.yaml"

LABEL=${repo_tag[$REPO]/:/-}
git add .
if [[ "$2" == "new" ]]; then
    git checkout -b $PACKAGE
    git commit -a -m "Add $PACKAGE"
fi

if [[ "$2" != "new" ]] && [[ "$2" != dry ]]; then
    git checkout -b pr-$LABEL
    git commit -a -m "Update $PACKAGE to $LABEL"
    git push origin --force pr-$LABEL
    gh pr create --base master --title "Update to $LABEL" --body ""
fi
