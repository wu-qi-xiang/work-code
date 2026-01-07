#!/bin/bash

root="/opt/java/openjdk"

rm -f "${root}"/src.zip
rm -rf "${root}"/sample
rm -rf "${root}"/man
rm -f "${root}"/lib/ct.sym

#注意最后就算不精简，这里解压重新打包的逻辑最好也有一下，经测试rt.jar解压后重新打包大小会小很多
del_list=(java/applet sun/applet sun/swing com/sun/swing com/sun/java/swing)


echo -n "INFO: Trimming classes in rt.jar..."
mkdir -p "${root}"/rt_class
pushd "${root}"/rt_class >/dev/null || return 
jar -xf "${root}"/jre/lib/rt.jar

for class in ${del_list[*]};
do
	rm -rf "${class}"
done
# 2.5. Restruct rt.jar
jar -cfm "${root}"/jre/lib/rt2.jar META-INF/MANIFEST.MF ./* 
mv "${root}"/jre/lib/rt2.jar "${root}"/jre/lib/rt.jar
popd >/dev/null || return
rm -rf "${root}"/rt_class
echo "done"