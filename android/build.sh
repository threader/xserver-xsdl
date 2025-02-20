#!/bin/sh

set -x

export BUILDDIR=`pwd`

[ -e $BUILDDIR/setCrossEnvironment.sh ] || {
	echo "Launch build.sh from arch-specific directory:"
	echo "cd armeabi-v7a ; ./build.sh"
	exit 1
}

NCPU=4
uname -s | grep -i "linux" && NCPU=`cat /proc/cpuinfo | grep -c -i processor`

NDK=`which ndk-build`
NDK=`dirname $NDK`
NDK=`readlink -f $NDK`

[ -z "$TARGET_ARCH" ] && TARGET_ARCH=armeabi-v7a
[ -z "$TARGET_HOST" ] && TARGET_HOST=arm-linux-androideabi
[ -z "$TARGET_DIR" ] && TARGET_DIR=/proc/self/cwd

AR=`$BUILDDIR/setCrossEnvironment.sh sh -c 'echo $AR'`
echo AR=$AR

export enable_malloc0returnsnull=true # Workaround for buggy autotools

# =========== android-shmem ===========

[ -e libandroid-shmem.a ] || {

[ -e ../android-shmem/LICENSE ] || {
	cd ../..
	git submodule update --init android/android-shmem || exit 1
	cd $BUILDDIR
} || exit 1
[ -e ../android-shmem/libancillary/ancillary.h ] || {
	cd ../android-shmem
	git submodule update --init libancillary || exit 1
	cd $BUILDDIR
} || exit 1

$BUILDDIR/setCrossEnvironment.sh \
env NDK=$NDK \
sh -c '$CC $CFLAGS \
	-I ../android-shmem \
	-I ../android-shmem/libancillary \
	-c ../android-shmem/*.c && \
	ar rcs libandroid-shmem.a *.o && \
	rm -f *.o' \
|| exit 1
cd $BUILDDIR
} || exit 1


# =========== xorgproto ===========

[ -e X11/Xfuncproto.h ] || {
PKGURL=https://cgit.freedesktop.org/xorg/proto/xorgproto/snapshot/xorgproto-2018.4.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1

cd $PKGDIR
patch -p0 < ../../xproto.diff || exit 1
$BUILDDIR/setCrossEnvironment.sh \
./autogen.sh --host=$TARGET_HOST --prefix=$BUILDDIR/usr \
|| exit 1
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 install 2>&1 || exit 1
cd $BUILDDIR
ln -sf $BUILDDIR/usr/include/X11 ./
} || exit 1

# =========== xtrans ===========

[ -e xtrans-1.3.5 ] || {
PKGURL=https://cgit.freedesktop.org/xorg/lib/libxtrans/snapshot/xtrans-1.3.5.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

patch -p0 < ../../xtrans.diff || exit 1

[ -e configure ] || \
autoreconf -v --install \
|| exit 1

env CFLAGS="-isystem$BUILDDIR/usr/include -include strings.h" \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST --prefix=$BUILDDIR/usr \
|| exit 1

$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 install 2>&1 || exit 1

cd $BUILDDIR
#ln -sf ../$PKGDIR X11/Xtrans
} || exit 1

# =========== libportable.a ===========
[ -e libportable.a ] || {
	rm -rf libportable
	mkdir -p libportable
	$BUILDDIR/setCrossEnvironment.sh \
	sh -c 'cd libportable && \
	$CC $CFLAGS -c '"$NDK/sources/android/cpufeatures/*.c"' && \
	ar rcs ../libportable.a *.o' || exit 1
} || exit 1

# =========== libpixman-1.a ===========

[ -e libpixman-1.a ] || {
PKGURL=https://cairographics.org/releases/pixman-0.38.0.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

aclocal
automake --add-missing
autoreconf -f

env CFLAGS="-I$NDK/sources/android/cpufeatures" \
LDFLAGS="-L$BUILDDIR -lportable" \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST \
--disable-arm-simd \
--disable-arm-neon \
--enable-static \
--prefix=$BUILDDIR/usr \
|| exit 1

sed -i "s/TOOLCHAIN_SUPPORTS_ATTRIBUTE_CONSTRUCTOR/DISABLE_TOOLCHAIN_SUPPORTS_ATTRIBUTE_CONSTRUCTOR/g" config.h

cd pixman
touch *.S

$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1
touch $BUILDDIR/$PKGDIR/pixman/.libs/libpixman-1.so
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 install install-am 2>&1 || exit 1

cd $BUILDDIR
#ln -sf $BUILDDIR/$PKGDIR/pixman/.libs/libpixman-1.a $BUILDDIR/libpixman-1.a
$AR rcs $BUILDDIR/libpixman-1.a $BUILDDIR/$PKGDIR/pixman/.libs/*.o || exit 1

} || exit 1

# =========== libfontenc.a ===========

[ -e libfontenc.a ] || {
PKGURL=https://cgit.freedesktop.org/xorg/lib/libfontenc/snapshot/libfontenc-1.1.3.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

[ -e configure ] || \
autoreconf -v --install \
|| exit 1

env CFLAGS="-isystem$BUILDDIR/usr/include -include strings.h" \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST \
--prefix=$BUILDDIR/usr \
--enable-static \
|| exit 1

#cp -f `which libtool` ./

$BUILDDIR/setCrossEnvironment.sh \
sh -c 'ln -sf $CC gcc'

env PATH=`pwd`:$PATH \
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1
touch src/.libs/libfontenc.so
env PATH=`pwd`:$PATH \
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 install 2>&1 || exit 1

cd $BUILDDIR
#ln -sf ../$PKGDIR/include/X11/fonts/fontenc.h X11/fonts/
#ln -sf $PKGDIR/src/.libs/libfontenc.a ./
$AR rcs libfontenc.a $PKGDIR/src/.libs/*.o || exit 1
} || exit 1

# =========== libXfont.a ===========

ln -sf $BUILDDIR/../../../../../../obj/local/$TARGET_ARCH/libfreetype.a $BUILDDIR/
ln -sf $BUILDDIR/../../../../../../obj/local/$TARGET_ARCH/libsdl_savepng.a $BUILDDIR/
ln -sf $BUILDDIR/../../../../../../obj/local/$TARGET_ARCH/libpng.a $BUILDDIR/

# =========== libXfont2.a ===========

[ -e libXfont2.a ] || {
PKGURL=https://cgit.freedesktop.org/xorg/lib/libXfont/snapshot/libXfont2-2.0.3.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

[ -e configure ] || \
autoreconf -v --install \
|| exit 1

env CFLAGS="-isystem$BUILDDIR/usr/include \
-include strings.h \
-I$BUILDDIR/../../../../../../jni/freetype/include \
-DNO_LOCALE -DOPEN_MAX=256" \
LDFLAGS="-L$BUILDDIR" \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST \
--prefix=$BUILDDIR/usr \
--enable-static \
|| exit 1

$BUILDDIR/setCrossEnvironment.sh \
sh -c 'ln -sf $CC gcc'

env PATH=`pwd`:$PATH \
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1
touch .libs/libXfont2.so
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 install 2>&1 || exit 1

cd $BUILDDIR
$AR rcs libXfont2.a $PKGDIR/src/*/.libs/*.o
} || exit 1

# =========== libXau.a ==========

[ -e libXau.a ] || {
PKGURL=https://cgit.freedesktop.org/xorg/lib/libXau/snapshot/libXau-1.0.9.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

[ -e configure ] || \
autoreconf -v --install \
|| exit 1

env CFLAGS="-isystem$BUILDDIR/usr/include \
-include strings.h" \
LDFLAGS="-L$BUILDDIR" \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST \
--prefix=$BUILDDIR/usr \
|| exit 1

#cp -f `which libtool` ./

$BUILDDIR/setCrossEnvironment.sh \
sh -c 'ln -sf $CC gcc'

env PATH=`pwd`:$PATH \
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1
touch .libs/libXau.so
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 install 2>&1 || exit 1

cd $BUILDDIR
#ln -sf $PKGDIR/.libs/libXau.a ./
$AR rcs libXau.a $PKGDIR/.libs/*.o

#ln -sf ../$PKGDIR/include/X11/Xauth.h X11/
} || exit 1

# =========== libXdmcp.a ==========

[ -e libXdmcp.a ] || {
PKGURL=https://cgit.freedesktop.org/xorg/lib/libXdmcp/snapshot/libXdmcp-1.1.2.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

[ -e configure ] || \
autoreconf -v --install \
|| exit 1

env CFLAGS="-isystem$BUILDDIR/usr/include \
-include strings.h" \
LDFLAGS="-L$BUILDDIR" \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST \
--prefix=$BUILDDIR/usr \
|| exit 1

#cp -f `which libtool` ./

$BUILDDIR/setCrossEnvironment.sh \
sh -c 'ln -sf $CC gcc'

env PATH=`pwd`:$PATH \
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1
touch .libs/libXdmcp.so
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 install 2>&1 || exit 1

cd $BUILDDIR
#ln -sf $PKGDIR/.libs/libXdmcp.a ./
$AR rcs libXdmcp.a $PKGDIR/.libs/*.o
#ln -sf ../$PKGDIR/include/X11/Xdmcp.h X11/
} || exit 1

# =========== xcbproto ===========
[ -e usr/lib/pkgconfig/xcb-proto.pc ] || {
PKGURL=https://xcb.freedesktop.org/dist/xcb-proto-1.13.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

$BUILDDIR/setCrossEnvironment.sh \
./autogen.sh --host=$TARGET_HOST --prefix=$BUILDDIR/usr \
|| exit 1
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 install 2>&1 || exit 1
cd $BUILDDIR
} || exit 1

# =========== libxcb.a ==========

[ -e libxcb.a ] || {
PKGURL=https://xcb.freedesktop.org/dist/libxcb-1.13.1.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

[ -e configure ] || \
autoreconf -v --install \
|| exit 1

env CFLAGS="-isystem$BUILDDIR/usr/include \
-include strings.h" \
LDFLAGS="-L$BUILDDIR" \
PKG_CONFIG_PATH=$BUILDDIR/usr/lib/pkgconfig \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST \
--prefix=$BUILDDIR/usr \
|| exit 1

#cp -f `which libtool` ./

$BUILDDIR/setCrossEnvironment.sh \
sh -c 'ln -sf $CC gcc'

sed -i 's/[$]MV [$]realname [$][{]realname[}]U/$CP $realname ${realname}U/g' ./libtool

env PATH=`pwd`:$PATH \
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1

for f in src/.libs/*.la; do
touch "`echo $f | sed 's/[.]la$/.so/'`"
done

$BUILDDIR/setCrossEnvironment.sh \
make -j1 V=1 install 2>&1 || exit 1

cd $BUILDDIR
#ln -sf $PKGDIR/src/.libs/libxcb.a ./
$AR rcs libxcb.a $PKGDIR/src/.libs/*.o
} || exit 1

# =========== libandroid_support.a ==========

[ -e libandroid_support.a ] || {
if echo $TARGET_ARCH | grep '64'; then
$AR rcs libandroid_support.a
else
ln -sf $NDK/sources/cxx-stl/llvm-libc++/libs/$TARGET_ARCH/libandroid_support.a ./ || exit 1
fi
cd $BUILDDIR
} || exit 1

# =========== libX11.a ==========

[ -e libX11.a ] || {
PKGURL=https://cgit.freedesktop.org/xorg/lib/libX11/snapshot/libX11-1.6.7.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

patch -p0 < ../../x11.diff || exit 1

[ -e configure ] || \
autoreconf -v --install \
|| exit 1

env CFLAGS="-isystem$BUILDDIR/usr/include \
			-isystem$BUILDDIR/../android-shmem \
			-I$BUILDDIR/.." \
LDFLAGS="-L$BUILDDIR" \
$BUILDDIR/setCrossEnvironment.sh \
LIBS="-lXau -lXdmcp -landroid_support -landroid-shmem" \
./configure \
--host=$TARGET_HOST \
--prefix=$TARGET_DIR/usr \
|| exit 1

$BUILDDIR/setCrossEnvironment.sh \
sh -c 'ln -sf $CC gcc'

echo "all install: makekeys" > src/util/Makefile
echo "makekeys:" >> src/util/Makefile
echo "	/usr/bin/gcc makekeys.c -o makekeys -I /usr/include" >> src/util/Makefile

env PATH=`pwd`:$PATH \
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1

ln -sf ../usr ./
ln -sf ../usr ./src/
ln -sf ../usr ./src/util/
ln -sf ../usr ./src/xcms/
ln -sf ../usr ./src/xkb/
ln -sf ../usr ./include/
ln -sf ../usr ./nls/
ln -sf ../usr ./man/
ln -sf ../usr ./man/xkb/
ln -sf ../usr ./specs/
ln -sf ../usr ./specs/XIM/
ln -sf ../usr ./specs/XKB/
ln -sf ../usr ./specs/libX11/
ln -sf ../usr ./specs/i18n/
ln -sf ../usr ./specs/i18n/compose/
ln -sf ../usr ./specs/i18n/framework/
ln -sf ../usr ./specs/i18n/localedb/
ln -sf ../usr ./specs/i18n/trans/

mkdir -p ./usr/share/X11
mkdir -p ./usr/share/X11/locale
mkdir -p ./usr/share/man/man3
mkdir -p ./usr/share/man/man5
mkdir -p ./usr/share/doc/libX11/XIM
mkdir -p ./usr/share/doc/libX11/XKB
mkdir -p ./usr/share/doc/libX11/libX11
mkdir -p ./usr/share/doc/libX11/i18n/compose
mkdir -p ./usr/share/doc/libX11/i18n/framework
mkdir -p ./usr/share/doc/libX11/i18n/localedb
mkdir -p ./usr/share/doc/libX11/i18n/trans

cd nls
for f in *; do
[ -d $f ] && mkdir -p ./usr/share/X11/locale/$f
done
cd ..

touch src/.libs/libX11.so
touch src/.libs/libX11-xcb.so
touch src/.libs/libX11-i18n.so
touch src/.libs/libX11-xcms.so
touch src/.libs/libX11-xkb.so

$BUILDDIR/setCrossEnvironment.sh \
make -j1 V=1 install install-am "MKDIR_P=test -d" 2>&1 || exit 1

cd $BUILDDIR
#for F in $PKGDIR/include/X11/*.h ; do
#ln -sf ../$F X11
#done

#ln -sf $PKGDIR/src/.libs/libX11.a ./
rm -f $PKGDIR/src/.libs/x11_xcb.o
$AR rcs libX11-core.a $PKGDIR/src/.libs/*.o
ln -sf $PKGDIR/src/xlibi18n/.libs/libi18n.a ./libX11-i18n.a
ln -sf $PKGDIR/src/xcms/.libs/libxcms.a ./libX11-xcms.a
ln -sf $PKGDIR/src/xkb/.libs/libxkb.a ./libX11-xkb.a

$AR -M <<EOF
CREATE libX11.a
ADDLIB libX11-core.a
ADDLIB libX11-i18n.a
ADDLIB libX11-xcms.a
ADDLIB libX11-xkb.a
SAVE
END
EOF

$AR s libX11.a
} || exit 1

# =========== libXext.a ==========

[ -e libXext.a ] || {
PKGURL=https://cgit.freedesktop.org/xorg/lib/libXext/snapshot/libXext-1.3.3.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

[ -e configure ] || \
autoreconf -v --install \
|| exit 1

env CFLAGS="-isystem$BUILDDIR/usr/include \
-include strings.h" \
LDFLAGS="-L$BUILDDIR" \
LIBS="-lxcb -lXau -lXdmcp -landroid_support" \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST \
--prefix=$BUILDDIR/usr \
|| exit 1

#cp -f `which libtool` ./

$BUILDDIR/setCrossEnvironment.sh \
sh -c 'ln -sf $CC gcc'

env PATH=`pwd`:$PATH \
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1
touch src/.libs/libXext.so
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 install 2>&1 || exit 1

cd $BUILDDIR
#ln -sf $PKGDIR/src/.libs/libXext.a ./
$AR rcs libXext.a $PKGDIR/src/.libs/*.o
#for F in $PKGDIR/include/X11/extensions/*.h ; do
#ln -sf ../$F X11/extensions/
#done
} || exit 1

# =========== libXrender.a ==========

[ -e libXrender.a ] || {
PKGURL=https://cgit.freedesktop.org/xorg/lib/libXrender/snapshot/libXrender-0.9.10.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

[ -e configure ] || \
autoreconf -v --install \
|| exit 1

env CFLAGS="-isystem$BUILDDIR/usr/include \
-include strings.h" \
LDFLAGS="-L$BUILDDIR" \
LIBS="-lxcb -lXau -lXdmcp -landroid_support" \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST \
--prefix=$BUILDDIR/usr \
|| exit 1

#cp -f `which libtool` ./

$BUILDDIR/setCrossEnvironment.sh \
sh -c 'ln -sf $CC gcc'

env PATH=`pwd`:$PATH \
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1
touch src/.libs/libXrender.so
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 install 2>&1 || exit 1

cd $BUILDDIR
#ln -sf $PKGDIR/src/.libs/libXrender.a ./
$AR rcs libXrender.a $PKGDIR/src/.libs/*.o
#for F in $PKGDIR/include/X11/extensions/*.h ; do
#ln -sf ../$F X11/extensions/
#done
} || exit 1

# =========== libXrandr.a ==========

[ -e libXrandr.a ] || {
PKGURL=https://cgit.freedesktop.org/xorg/lib/libXrandr/snapshot/libXrandr-1.5.1.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

[ -e configure ] || \
autoreconf -v --install \
|| exit 1

env CFLAGS="-isystem$BUILDDIR/usr/include \
-include strings.h" \
LDFLAGS="-L$BUILDDIR" \
LIBS="-lxcb -lXau -lXdmcp -landroid_support" \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST \
--prefix=$BUILDDIR/usr \
|| exit 1

#cp -f `which libtool` ./

$BUILDDIR/setCrossEnvironment.sh \
sh -c 'ln -sf $CC gcc'

env PATH=`pwd`:$PATH \
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1
touch src/.libs/libXrandr.so
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 install 2>&1 || exit 1

cd $BUILDDIR
#ln -sf $PKGDIR/src/.libs/libXrandr.a ./
$AR rcs libXrandr.a $PKGDIR/src/.libs/*.o
#for F in $PKGDIR/include/X11/extensions/*.h ; do
#ln -sf ../$F X11/extensions/
#done
} || exit 1

# =========== libdrm.a ==========

[ -e usr/include/libdrm/drm_fourcc.h ] || {
PKGURL=https://cgit.freedesktop.org/mesa/drm/snapshot/libdrm-2.4.99.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

[ -e configure ] || \
autoreconf -v --install \
|| exit 1

env CFLAGS="-isystem$BUILDDIR/usr/include" \
LDFLAGS="-L$BUILDDIR" \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST \
--prefix=$BUILDDIR/usr \
|| exit 1

$BUILDDIR/setCrossEnvironment.sh \
sh -c 'ln -sf $CC gcc'

$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 install-klibdrmincludeHEADERS install-libdrmincludeHEADERS 2>&1 || exit 1

cd $BUILDDIR
} || exit 1

# =========== libxkbfile.a ==========

[ -e libxkbfile.a ] || {
PKGURL=https://cgit.freedesktop.org/xorg/lib/libxkbfile/snapshot/libxkbfile-1.0.9.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

[ -e configure ] || \
autoreconf -v --install \
|| exit 1

env CFLAGS="-isystem$BUILDDIR/usr/include \
-include strings.h" \
LDFLAGS="-L$BUILDDIR" \
LIBS="-lxcb -lXau -lXdmcp -landroid_support" \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST \
--prefix=$BUILDDIR/usr \
|| exit 1

#cp -f `which libtool` ./

$BUILDDIR/setCrossEnvironment.sh \
sh -c 'ln -sf $CC gcc'

env PATH=`pwd`:$PATH \
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1
touch src/.libs/libxkbfile.so
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 install 2>&1 || exit 1

cd $BUILDDIR
#ln -sf $PKGDIR/src/.libs/libxkbfile.a ./
$AR rcs libxkbfile.a $PKGDIR/src/.libs/*.o
#for F in $PKGDIR/include/X11/extensions/*.h ; do
#ln -sf ../$F X11/extensions/
#done
} || exit 1

# =========== xkbcomp binary ==========

[ -e xkbcomp ] || {
PKGURL=https://cgit.freedesktop.org/xorg/app/xkbcomp/snapshot/xkbcomp-1.4.2.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

[ -e configure ] || \
autoreconf -v --install \
|| exit 1

env CFLAGS="-isystem$BUILDDIR/usr/include \
-include strings.h -Os -Wno-string-compare" \
LDFLAGS="-pie -L$BUILDDIR" \
LIBS="-lxcb -lXau -lXdmcp -landroid_support -lX11 -landroid-shmem" \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST \
--prefix=$TARGET_DIR/usr \
|| exit 1

#cp -f `which libtool` ./

$BUILDDIR/setCrossEnvironment.sh \
sh -c 'ln -sf $CC gcc'

env PATH=`pwd`:$PATH \
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1

cd $BUILDDIR
cp -f $PKGDIR/xkbcomp ./
$BUILDDIR/setCrossEnvironment.sh \
sh -c '$STRIP xkbcomp'

cd $BUILDDIR
} || exit 1

# =========== xkeyboard-config ==========

[ -e usr/share/X11/xkb/rules/evdev ] || {
PKGURL=https://www.x.org/releases/individual/data/xkeyboard-config/xkeyboard-config-2.26.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

$BUILDDIR/setCrossEnvironment.sh \
./autogen.sh --host=$TARGET_HOST --prefix=$BUILDDIR/usr \
|| exit 1
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 install 2>&1 || exit 1
cd $BUILDDIR
} || exit 1

# =========== libICE.a ==========

[ -e libICE.a ] || {
PKGURL=https://cgit.freedesktop.org/xorg/lib/libICE/snapshot/libICE-1.0.9.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

[ -e configure ] || \
autoreconf -v --install \
|| exit 1

#LIBS="-lxcb -lXau -lXdmcp -landroid_support" \

env CFLAGS="-isystem$BUILDDIR/usr/include \
-include strings.h" \
LDFLAGS="-L$BUILDDIR" \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST \
--prefix=$BUILDDIR/usr \
|| exit 1

#cp -f `which libtool` ./

$BUILDDIR/setCrossEnvironment.sh \
sh -c 'ln -sf $CC gcc'

env PATH=`pwd`:$PATH \
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1
touch src/.libs/libICE.so
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 install 2>&1 || exit 1

cd $BUILDDIR
#ln -sf $PKGDIR/src/.libs/libICE.a ./
$AR rcs libICE.a $PKGDIR/src/.libs/*.o

#ln -sf ../$PKGDIR/include/X11/ICE X11/
} || exit 1

# =========== libSM.a ==========

[ -e libSM.a ] || {
PKGURL=https://cgit.freedesktop.org/xorg/lib/libSM/snapshot/libSM-1.2.3.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

[ -e configure ] || \
autoreconf -v --install \
|| exit 1

#LIBS="-lxcb -lXau -lXdmcp -landroid_support" \

env CFLAGS="-isystem$BUILDDIR/usr/include \
-include strings.h" \
LDFLAGS="-L$BUILDDIR" \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST \
--prefix=$BUILDDIR/usr \
--without-libuuid \
|| exit 1

#cp -f `which libtool` ./

$BUILDDIR/setCrossEnvironment.sh \
sh -c 'ln -sf $CC gcc'

env PATH=`pwd`:$PATH \
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1
touch src/.libs/libSM.so
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 install 2>&1 || exit 1

cd $BUILDDIR
#ln -sf $PKGDIR/src/.libs/libSM.a ./
$AR rcs libSM.a $PKGDIR/src/.libs/*.o

#ln -sf ../$PKGDIR/include/X11/SM X11/
} || exit 1

# =========== libXt.a ==========

[ -e libXt.a ] || {
PKGURL=https://cgit.freedesktop.org/xorg/lib/libXt/snapshot/libXt-1.1.5.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

[ -e configure ] || \
autoreconf -v --install \
|| exit 1

env CFLAGS="-isystem$BUILDDIR/usr/include \
-include strings.h" \
LDFLAGS="-L$BUILDDIR" \
LIBS="-lxcb -lXau -lXdmcp -landroid_support" \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST \
--prefix=$TARGET_DIR/usr \
|| exit 1

$BUILDDIR/setCrossEnvironment.sh \
sh -c 'ln -sf $CC gcc'

echo "all install: makestrs" > util/Makefile
echo "makestrs:" >> util/Makefile
echo "	/usr/bin/gcc makestrs.c -o makestrs -I /usr/include" >> util/Makefile

env PATH=`pwd`:$PATH \
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1

ln -sf ../usr ./
ln -sf ../usr ./src/
ln -sf ../usr ./include/
ln -sf ../usr ./man/
ln -sf ../usr ./specs/
mkdir -p ./usr/share/doc/libXt

touch src/.libs/libXt.so

$BUILDDIR/setCrossEnvironment.sh \
make -j1 V=1 install "MKDIR_P=test -d" 2>&1 || exit 1

cd $BUILDDIR
#ln -sf $PKGDIR/src/.libs/libXt.a ./
$AR rcs libXt.a $PKGDIR/src/.libs/*.o

#for F in $PKGDIR/include/X11/*.h ; do
#ln -sf ../$F X11/
#done
} || exit 1

# =========== libXmuu.a ==========

[ -e libXmuu.a ] || {
PKGURL=https://cgit.freedesktop.org/xorg/lib/libXmu/snapshot/libXmu-1.1.2.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

[ -e configure ] || \
autoreconf -v --install \
|| exit 1

env CFLAGS="-isystem$BUILDDIR/usr/include \
-include strings.h" \
LDFLAGS="-L$BUILDDIR" \
LIBS="-lxcb -lXau -lXdmcp -landroid_support -lSM -lICE" \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST \
--prefix=$TARGET_DIR/usr \
|| exit 1

$BUILDDIR/setCrossEnvironment.sh \
sh -c 'ln -sf $CC gcc'

env PATH=`pwd`:$PATH \
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1

ln -sf ../usr ./
ln -sf ../usr ./src/
ln -sf ../usr ./include/
ln -sf ../usr ./doc/
mkdir -p ./usr/include/X11/Xmu
mkdir -p ./usr/share/doc/libXmu

touch src/.libs/libXmuu.so
touch src/.libs/libXmu.so

$BUILDDIR/setCrossEnvironment.sh \
make -j1 V=1 install "MKDIR_P=test -d" 2>&1 || exit 1

cd $BUILDDIR
#ln -sf $PKGDIR/src/.libs/libXmuu.a ./
#ln -sf $PKGDIR/src/.libs/libXmu.a ./
$AR rcs libXmuu.a $PKGDIR/src/.libs/*.o
$AR rcs libXmu.a

#ln -sf ../$PKGDIR/include/X11/Xmu X11/
} || exit 1

# =========== libxshmfence.a ==========

[ -e libxshmfence.a ] || {
PKGURL=https://cgit.freedesktop.org/xorg/lib/libxshmfence/snapshot/libxshmfence-1.3.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

patch -p0 < ../../xshmfence.diff || exit 1

[ -e configure ] || \
autoreconf -v --install \
|| exit 1

mkdir tmp

env CFLAGS="-isystem$BUILDDIR/usr/include \
-include limits.h \
-DMAXINT=INT_MAX" \
LDFLAGS="-L$BUILDDIR" \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST \
--prefix=$BUILDDIR/usr \
--with-shared-memory-dir=/proc/self/cwd/tmp \
|| exit 1

env PATH=`pwd`:$PATH \
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1
touch src/.libs/libxshmfence.so
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 install 2>&1 || exit 1

cd $BUILDDIR
$AR rcs libxshmfence.a $PKGDIR/src/.libs/*.o
} || exit 1

# =========== xhost binary ==========

[ -e xhost ] || {
PKGURL=https://cgit.freedesktop.org/xorg/app/xhost/snapshot/xhost-1.0.7.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

[ -e configure ] || \
autoreconf -v --install \
|| exit 1

env CFLAGS="-isystem$BUILDDIR/usr/include \
-include strings.h \
-Dsethostent=abs -Dendhostent=sync -Os" \
LDFLAGS="-pie -L$BUILDDIR" \
LIBS="-lxcb -lXau -lXdmcp -landroid_support -lX11 -landroid-shmem" \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST \
--prefix=$TARGET_DIR/usr \
|| exit 1

#cp -f `which libtool` ./

$BUILDDIR/setCrossEnvironment.sh \
sh -c 'ln -sf $CC gcc'

env PATH=`pwd`:$PATH \
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1

cd $BUILDDIR
cp -f $PKGDIR/xhost ./
$BUILDDIR/setCrossEnvironment.sh \
sh -c '$STRIP xhost'

cd $BUILDDIR
} || exit 1

# =========== xloadimage binary ==========

[ -e xloadimage ] || {
PKGURL=https://salsa.debian.org/debian/xloadimage/-/archive/master/xloadimage-master.tar.gz
PKGDIR=`basename --suffix=.tar.gz $PKGURL`
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
rm -rf $PKGDIR
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

for f in debian/patches/*.patch; do patch -p1 < $f ; done

chmod a+x ./configure

# ac_cv_lib_jpeg_main=no ac_cv_lib_png_main=no

env CFLAGS="-isystem$BUILDDIR/usr/include \
-isystem . \
-isystem $BUILDDIR/../../../../../../jni/jpeg/include \
-isystem $BUILDDIR/../../../../../../jni/png/include \
-Dindex=strchr \
-Drindex=strrchr \
-Os" \
LDFLAGS="-L$BUILDDIR \
-L$BUILDDIR/../../../../../../obj/local/$TARGET_ARCH \
-lX11 -lxcb -lXau -lXdmcp -lXext -lpng -landroid_support -landroid-shmem -llog -lm -lz" \
ac_cv_lib_tiff_main=no \
$BUILDDIR/setCrossEnvironment.sh \
./configure \
--host=$TARGET_HOST \
--prefix=$TARGET_DIR/usr \
|| exit 1

$BUILDDIR/setCrossEnvironment.sh \
sh -c 'ln -sf $CC gcc'

env PATH=`pwd`:$PATH \
$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1

cd $BUILDDIR
cp -f $PKGDIR/xloadimage ./
$BUILDDIR/setCrossEnvironment.sh \
sh -c '$STRIP xloadimage'

cd $BUILDDIR
} || exit 1

# =========== xsel binary ==========

[ -e xsel ] || {
PKGURL=https://github.com/kfish/xsel/archive/master.tar.gz
PKGDIR=xsel-master
echo $PKGDIR: $PKGURL
[ -e ../$PKGDIR.tar.gz ] || { curl -L $PKGURL -o $PKGDIR.tar.gz && mv $PKGDIR.tar.gz ../ ; } || rm ../$PKGDIR.tar.gz
tar xvzf ../$PKGDIR.tar.gz || exit 1
cd $PKGDIR

env CFLAGS="-isystem$BUILDDIR/usr/include -Drpl_malloc=malloc -Os" \
LDFLAGS="-pie -L$BUILDDIR" \
LIBS="-lX11 -lxcb -lXau -lXdmcp -landroid_support -landroid-shmem" \
$BUILDDIR/setCrossEnvironment.sh \
./autogen.sh --host=$TARGET_HOST \
|| exit 1

$BUILDDIR/setCrossEnvironment.sh \
make -j$NCPU V=1 2>&1 || exit 1

cd $BUILDDIR
cp -f $PKGDIR/xsel ./ || exit 1
$BUILDDIR/setCrossEnvironment.sh \
sh -c '$STRIP xsel'

cd $BUILDDIR
} || exit 1

# =========== xsdl ==========

#ln -sf $BUILDDIR/../../../../../../libs/$TARGET_ARCH/libsdl-1.2.so $BUILDDIR/libSDL.so
ln -sf $BUILDDIR/../../../../../../jni/application/sdl-config $BUILDDIR/
ln -sf $BUILDDIR/libportable.a $BUILDDIR/libpthread.a # dummy
ln -sf $BUILDDIR/libportable.a $BUILDDIR/libts.a # dummy

[ -z "$PACKAGE_NAME" ] && PACKAGE_NAME=X.org.server

# Hack for NDK r19
SYSTEM_LIBDIR=$NDK/platforms
case $TARGET_ARCH in
	arm64-v8a)   SYSTEM_LIBDIR=$NDK/platforms/android-21/arch-arm64/usr/lib;;
	armeabi-v7a) SYSTEM_LIBDIR=$NDK/platforms/android-16/arch-arm/usr/lib;;
	x86)         SYSTEM_LIBDIR=$NDK/platforms/android-16/arch-x86/usr/lib;;
	x86_64)      SYSTEM_LIBDIR=$NDK/platforms/android-21/arch-x86_64/usr/lib64;;
esac

[ -e Makefile ] && grep "`pwd`" Makefile > /dev/null || \
env CFLAGS=" -DDEBUG -Wformat \
	-isystem$BUILDDIR/usr/include \
	-isystem$BUILDDIR/../android-shmem \
	-include strings.h\
	-include linux/time.h \
	-DFNONBLOCK=O_NONBLOCK \
	-DFNDELAY=O_NDELAY \
	-D_LINUX_IPC_H \
	-Dipc_perm=debian_ipc_perm \
	-I$BUILDDIR/usr/include/pixman-1 \
	-I$BUILDDIR/../../../../../../jni/crypto/include \
	-I$BUILDDIR/../../../../../../jni/sdl-1.2/include" \
LDFLAGS="-L$BUILDDIR \
	-L$BUILDDIR/../../../../../../obj/local/$TARGET_ARCH \
	-L$SYSTEM_LIBDIR" \
PKG_CONFIG_PATH=$BUILDDIR/usr/lib/pkgconfig:$BUILDDIR/usr/share/pkgconfig \
./setCrossEnvironment.sh \
LIBS="-lfontenc -lfreetype -llog -lsdl-1.2 -lsdl_native_helpers -lGLESv1_CM -landroid-shmem -l:libcrypto.so.sdl.1.so -lz -lm -ldl -landroid -llog" \
OPENSSL_LIBS=-l:libcrypto.so.sdl.1.so \
LIBSHA1_LIBS=-l:libcrypto.so.sdl.1.so \
PATH=$BUILDDIR:$PATH \
../../configure \
--host=$TARGET_HOST \
--prefix=$TARGET_DIR/usr \
--with-xkb-output=$TARGET_DIR/tmp \
--disable-xorg --disable-dmx --disable-xvfb --disable-xnest --disable-xquartz --disable-xwin \
--disable-xephyr --disable-unit-tests \
--disable-dri --disable-dri2 --disable-glx --disable-xf86vidmode \
--enable-xsdl --enable-kdrive \
--enable-mitshm --disable-config-udev --disable-libdrm \
|| exit 1

./setCrossEnvironment.sh make -j$NCPU V=1 2>&1 || exit 1

exit 0
