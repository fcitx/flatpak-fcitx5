#!/bin/sh

BASE=$PWD
DISTDIR=distdir
CACHE_TMP=tmp4
CACHE_TMP2=tmp5
rm -rf $CACHE_TMP $CACHE_TMP2
mkdir -p $CACHE_TMP
mkdir -p $CACHE_TMP2

CACHE=repo_cache
rm -rf $CACHE
mkdir -p $CACHE

_MOZC_BAZEL_CACHE=/tmp/mozc_cache
cp -a mozc-deps.json mozc-deps.tmp
jq -r '.[]|select(.url!="'$url'")| ( . ) + ( if ."dest-filename" != "" and ."dest-filename" != null then { "dest-filename": ."dest-filename", } else { "dest-filename": .url | split("/") |last } end ) ' mozc-deps.tmp|jq -s "." > mozc-deps.json
urls=$(jq -r ".[]|.url" mozc-deps.json) 
for f in $(find $_MOZC_BAZEL_CACHE/content_addressable -type f);do [[ $(file $f) =~ JSON ]] && urls+=" "$(jq -r 'select(.url!=null and .url!="")|.url' $f||true); done
urls=$(echo $urls|xargs -n1|sort -u)
for url in $urls
do
	id=$(jq -r '.[]|select(.url=="'$url'")|.id' mozc-deps.json )
	sha=$(jq -r '.[]|select(.url=="'$url'")|.sha256' mozc-deps.json )
        filename=$(jq -r '.[]|select(.url=="'$url'")| ."dest-filename"' mozc-deps.json )
	[[ -z $filename ]] && filename=$(basename $url)
	[[ -z $sha ]] && sha=$(sha256sum $filename|cut -f1 -d" ")
	mkdir -p $CACHE_TMP/$sha/
	if [[ -n $id ]];then
		echo $sha/$id
		touch $CACHE_TMP/$sha/$id
	fi
	cp -al "$DISTDIR/$filename" $CACHE_TMP/$sha/file
	echo "--------------"
	# MODULE.bazel of Archive
	(
	cd $CACHE_TMP2
	strip_name="${filename%"${filename##*[0-9]}"}"
	[[ -z $strip_name ]] && strip_name=${filename#.*}
	if [[ $filename =~ .zip ]];then
		#if [[ $(unzip -l $BASE/$filename|grep MODULE.bazel) ]]; then
			echo "MODULE:Zip:" $filename ":" $strip_name
			#unzip -x $BASE/$filename -d$strip_name "*MODULE.bazel"
			unzip -x $BASE/$filename -d$strip_name
			#files=$(find $strip_name -name MODULE.bazel -type f)
			files=()
			while read file
			do
				files+=("${file}")
			done < <( find $strip_name -type f )
			for f in "${files[@]}"
			do
			    sha=$(sha256sum "$f"|cut -f1 -d" ")
			    [[ -z $sha ]] && echo "DEBUG:" $f $url
			    mkdir -p $CACHE_TMP/$sha
			    cp -al "$f" $CACHE_TMP/$sha/file
			done
		#fi
	elif [[ $filename =~ .tar ]];then
		#if [[ $(tar tf $BASE/$filename|grep MODULE.bazel) ]]; then
			echo "MODULE:TAR:" $filename ":" $strip_name
			mkdir -p $strip_name
			#tar --wildcards -xf $BASE/$filename -C$strip_name "*MODULE.bazel"
			tar --wildcards -xf $BASE/$filename -C$strip_name
			#files=$(find $strip_name -name MODULE.bazel -type f)
			files=()
			while read file
			do
				files+=("${file}")
			done < <( find $strip_name -type f )
			for f in "${files[@]}"
			do
			    sha=$(sha256sum "$f"|cut -f1 -d" ")
			    [[ -z $sha ]] && echo "DEBUG:" $f $url
			    mkdir -p $CACHE_TMP/$sha
			    cp -al "$f" $CACHE_TMP/$sha/file
			done
		#fi
	fi
)
done

#remote patches
for url in $urls
do
	filename=$(basename $url)
	remote_patches=$(jq -r '.[]|select(.url=="'$url'")|select(.remote_patches!=null and .remote_patches!={})|.remote_patches' mozc-deps.json |awk '{FS=" "}{print $1}'|sed -e 's/":$//' -e 's/^"//' -e 's/^{$//' -e's/^}$//' -e '/^ *$/d')
	for patch in $remote_patches
	do
		strip_name="${filename%"${filename##*[0-9]}"}"
		[[ -z $strip_name ]] && strip_name=${filename#.*}
		patchname=$strip_name"_"$(basename $patch)
		sha=$(sha256sum $DISTDIR/$patchname|cut -f1 -d" ")
		echo $patchname $sha
		mkdir -p $CACHE_TMP/$sha/
		cp -al "$DISTDIR/$patchname" $CACHE_TMP/$sha/file
	done
done


rm -rf $CACHE
mkdir -p $CACHE/content_addressable/sha256/
cp -al $CACHE_TMP/* $CACHE/content_addressable/sha256/
rm -rf $CACHE_TMP
