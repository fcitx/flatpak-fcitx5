#!/bin/bash

DISTDIR=distdir
rm -rf $DISTDIR
mkdir -p $DISTDIR
cp -a mozc-deps.json mozc-deps.tmp
#dest-filename
jq -r '.[]|select(.url!="'$url'")| ( . ) + ( if ."dest-filename" != "" and ."dest-filename" != null then { "dest-filename": ."dest-filename", } else { "dest-filename": .url | split("/") |last } end ) ' mozc-deps.tmp|jq -s "." > mozc-deps.json
_MOZC_BAZEL_CACHE=/tmp/mozc_cache
urls=$(jq -r ".[]|.url" mozc-deps.json) 
for f in $(find $_MOZC_BAZEL_CACHE/content_addressable -type f);do [[ $(file $f) =~ JSON ]] && urls+=" "$(jq -r 'select(.url!=null and .url!="")|.url' $f||true); done
urls=$(echo $urls|xargs -n1|sort -u)
echo $urls|xargs -n1|wc -l
for url in $urls
do
	#remote patches download
	remote_patches=$(jq -r '.[]|select(.url=="'$url'")|select(.remote_patches!=null and .remote_patches!={})|.remote_patches' mozc-deps.json |awk '{FS=" "}{print $1}'|sed -e 's/":$//' -e 's/^"//' -e 's/^{$//' -e's/^}$//' -e '/^ *$/d')
	for patch in $remote_patches
	do
		filename=$(basename $url)
		strip_name="${filename%"${filename##*[0-9]}"}"
		[[ -z $strip_name ]] && strip_name=${filename#.*}
		filename=$(basename $patch)
		patchname=$strip_name"_"$filename
		echo $remote_patches
		echo $patch
		echo $strip_name
		echo $patchname
		wget -nc $patch -O $patchname
		cp -al $patchname $DISTDIR/$patchname
	done
	# archive download
	id=$(jq -r '.[]|select(.url=="'$url'")|.id' mozc-deps.json )
	sha=$(jq -r '.[]|select(.url=="'$url'")|.sha256' mozc-deps.json )
        filename=$(jq -r '.[]|select(.url=="'$url'")| ."dest-filename"' mozc-deps.json )
	[[ -z $filename ]] && filename=$(basename $url)
	wget -nc $url -O $filename
	cp -al $filename $DISTDIR/
done

