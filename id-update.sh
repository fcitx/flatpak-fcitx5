#/bin/bash

function UpdateId() {
	local url=$1
	local hash=$2
	local id=$3
	jq '
	def update_id(url; hash; id):
	walk(
	if type == "object" and .url == url and .sha256 == hash then
		.id = id
	else
		.
	end
	);

	update_id("'$url'" ; "'$hash'" ; "'$id'")
	' $BASE/mozc-deps.json > $BASE/mozc-deps.tmp
	cp -a $BASE/mozc-deps.tmp $BASE/mozc-deps.json
	sync
}

BASE=$PWD
_MOZC_BAZEL_CACHE=/tmp/mozc_cache
jq -r -f $BASE/resolved.jq $BASE/resolved.json > $BASE/mozc-deps.tmp
cat $BASE/mozc-deps.tmp | jq '.[]|  ( . ) + { id: "", }'|jq -s "." > $BASE/mozc-deps.json

urls=$(jq -r -f $BASE/resolved.jq $BASE/resolved.json |jq -r ".[]|.url")

for url in $urls;
do
	sha=$(jq -r '.[]|select(.url == "'$url'")|.sha256' mozc-deps.json)
	dir=$(find $_MOZC_BAZEL_CACHE -name "$sha" -type d)
	id=$(find $dir -name 'id-*' -type f)
	if [[ -n $id ]]; then
		id=$(basename $id)
		UpdateId $url $sha $id
	fi
done



