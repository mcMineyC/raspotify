#!/bin/sh

if [ "$INSIDE_DOCKER_CONTAINER" != "1" ]; then
	echo "Must be run in docker container"
	exit 1
fi

set -e

now() {
	date -u +%s.%N
}

duration_since() {
	duration_secs=$(echo "$(now) - $1" | bc)

	hours=$(echo "$duration_secs / 3600" | bc)
	remaining_secs=$(echo "$duration_secs - ($hours * 3600)" | bc)

	mins=$(echo "$remaining_secs / 60" | bc)
	secs=$(echo "$remaining_secs - ($mins * 60)" | bc)

	if [ "$((mins + hours))" -eq 0 ]; then
		echo """$secs""s"
	elif [ "$hours" -eq 0 ]; then
		echo """$mins""m ""$secs""s"
	else
		echo """$hours""h ""$mins""m ""$secs""s"
	fi
}

packages() {
	echo "Build $ARCHITECTURE packages..."

	START_PACKAGES=$(now)

	cd /mnt/raspotify

	if [ ! -d librespot ]; then
		# Use a vendored version of librespot.
		# https://github.com/librespot-org/librespot does not regularly or
		# really ever update their dependencies on released versions.
		# https://github.com/librespot-org/librespot/pull/1068
		echo "Get https://github.com/JasonLG1979/librespot/tree/raspotify..."
		git clone https://github.com/JasonLG1979/librespot
		cd librespot
		git checkout raspotify
		cd /mnt/raspotify
	fi

	DOC_DIR="raspotify/usr/share/doc/raspotify"

	if [ ! -d "$DOC_DIR" ]; then
		echo "Copy copyright & readme files..."
		mkdir -p "$DOC_DIR"
		cp -v LICENSE "$DOC_DIR/copyright"
		cp -v readme "$DOC_DIR/readme"
		cp -v librespot/LICENSE "$DOC_DIR/librespot.copyright"
	fi

	cd librespot

	# Get the git rev of librespot for .deb versioning
	LIBRESPOT_VER="$(git describe --tags "$(git rev-list --tags --max-count=1)" 2>/dev/null || echo unknown)"
	LIBRESPOT_HASH="$(git rev-parse HEAD | cut -c 1-7 2>/dev/null || echo unknown)"

	echo "Build Librespot binary..."
	cargo build --jobs "$(nproc)" --profile raspotify --target "$BUILD_TARGET" --no-default-features --features "alsa-backend pulseaudio-backend"

	echo "Copy Librespot binary to package root..."
	cd /mnt/raspotify

	cp -v /build/"$BUILD_TARGET"/raspotify/librespot raspotify/usr/bin

	# Compute final package version + filename for Debian control file
	DEB_PKG_VER="${RASPOTIFY_GIT_VER}~librespot.${LIBRESPOT_VER}-${LIBRESPOT_HASH}"
	DEB_PKG_NAME="raspotify_${DEB_PKG_VER}_${ARCHITECTURE}.deb"

	# https://www.debian.org/doc/debian-policy/ch-controlfields.html#installed-size
	# "The disk space is given as the integer value of the estimated installed size
	# in bytes, divided by 1024 and rounded up."
	INSTALLED_SIZE="$((($(du -bs raspotify --exclude=raspotify/DEBIAN/control | cut -f 1) + 2048) / 1024))"

	echo "Generate Debian control..."
	export DEB_PKG_VER
	export INSTALLED_SIZE
	envsubst <control.debian.tmpl >raspotify/DEBIAN/control

	echo "Build Raspotify deb..."
	dpkg-deb -b raspotify "$DEB_PKG_NAME"

	PACKAGE_SIZE="$(du -bs "$DEB_PKG_NAME" | cut -f 1)"
	BUILD_TIME=$(duration_since "$START_PACKAGES")

	echo "Raspotify package built as:  $DEB_PKG_NAME"
	echo "Estimated package size:      $PACKAGE_SIZE (Bytes)"
	echo "Estimated installed size:    $INSTALLED_SIZE (KiB)"
	echo "Build time:                  $BUILD_TIME"

	START_AWIZ=$(now)

	if [ ! -d asound-conf-wizard ]; then
		echo "Get https://github.com/JasonLG1979/asound-conf-wizard..."
		git clone https://github.com/JasonLG1979/asound-conf-wizard.git
	fi

	cd asound-conf-wizard

	echo "Build asound-conf-wizard deb..."
	cargo-deb --profile default --target "$BUILD_TARGET" -- --jobs "$(nproc)"

	cd /build/"$BUILD_TARGET"/debian

	AWIZ_DEB_PKG_NAME=$(ls -1 -- *.deb)

	echo "Copy asound-conf-wizard deb to raspotify root..."
	cp -v "$AWIZ_DEB_PKG_NAME" /mnt/raspotify

	cd /mnt/raspotify

	INSTALLED_SIZE=$(dpkg -f "$AWIZ_DEB_PKG_NAME" Installed-Size)
	PACKAGE_SIZE="$(du -bs "$AWIZ_DEB_PKG_NAME" | cut -f 1)"
	BUILD_TIME=$(duration_since "$START_AWIZ")

	echo "asound-conf-wizard package built as:  $AWIZ_DEB_PKG_NAME"
	echo "Estimated package size:               $PACKAGE_SIZE (Bytes)"
	echo "Estimated installed size:             $INSTALLED_SIZE (KiB)"
	echo "Build time:                           $BUILD_TIME"

	BUILD_TIME=$(duration_since "$START_PACKAGES")

	echo "$ARCHITECTURE packages build time: $BUILD_TIME"
}

build_armhf() {
	ARCHITECTURE="armhf"
	BUILD_TARGET="armv7-unknown-linux-gnueabihf"
	packages
}

build_arm64() {
	ARCHITECTURE="arm64"
	BUILD_TARGET="aarch64-unknown-linux-gnu"
	packages
}

build_amd64() {
	ARCHITECTURE="amd64"
	BUILD_TARGET="x86_64-unknown-linux-gnu"
	packages
}

build_all() {
	build_armhf
	build_arm64
	build_amd64
}

START_BUILDS=$(now)

cd /mnt/raspotify

# Get the git rev of raspotify for .deb versioning
RASPOTIFY_GIT_VER="$(git describe --tags "$(git rev-list --tags --max-count=1)" 2>/dev/null || echo unknown)"
RASPOTIFY_HASH="$(git rev-parse HEAD | cut -c 1-7 2>/dev/null || echo unknown)"

echo "Build Raspotify $RASPOTIFY_GIT_VER~$RASPOTIFY_HASH..."

case $ARCHITECTURE in
"armhf")
	build_armhf
	;;
"arm64")
	build_arm64
	;;
"amd64")
	build_amd64
	;;
"all")
	build_all
	;;
esac

# Perm fixup. Not needed on macOS, but is on Linux
chown -R "$PERMFIX_UID:$PERMFIX_GID" /mnt/raspotify 2>/dev/null || true

BUILD_TIME=$(duration_since "$START_BUILDS")

echo "Total packages build time: $BUILD_TIME"
