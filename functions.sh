#!/bin/bash

get_tag() {
    gh api repos/$1/tags --jq .[].name --paginate | sort -r -V | head -n 1
}

get_commit() {
    gh api repos/$1/commits/$2 --jq .sha
}

