#!/bin/bash

CURDIR="$(cd $(dirname $0); pwd)"
DSTDIR="$CURDIR/shared"
export PATH="$PATH:$CURDIR"

# return: $OS $ARCH
getSysinfo() {
	case "$(uname || echo $OSTYPE)" in
		Linux|linux-gnu)
			# Linux
			export OS=linux
		;;
		Darwin|darwin*)
			# Mac OSX
			export OS=darwin
		;;
		CYGWIN_NT*|cygwin)
			# POSIX compatibility layer and Linux environment emulation for Windows
			export OS=windows
		;;
		MINGW32_NT*|MINGW64_NT*|MSYS_NT*|msys)
			# Lightweight shell and GNU utilities compiled for Windows (part of MinGW)
			export OS=windows
		;;
		win32)
			# I'm not sure this can happen.
			return 1
		;;
		freebsd*)
			# Free BSD
			return 1
		;;
		*)
			# Unknown.
			unset OS
		;;
	esac
	case "$(uname -m || echo $PROCESSOR_ARCHITECTURE)" in
		x86_64|amd64|AMD64)
			export ARCH=amd64
		;;
		arm64|ARM64|aarch64|AARCH64|armv8*|ARMV8*)
			export ARCH=arm64
		;;
		*)
			# Unknown.
			unset ARCH
		;;
	esac
	[ -n "$OS" -a -n "$ARCH" ] || >&2 echo -e "Unsupported system or architecture.\n"
	[ "$OS" = "windows" -a "$ARCH" = "arm64" ] && >&2 echo -e "Unsupported system or architecture.\n"
	return 0
}

getSysinfo
[ "$OS" = "darwin" ] && SED=gsed || SED=sed
if [ -n "$OS$ARCH" ]; then
	MIHOMO=mihomo-$OS-$ARCH$([ "$OS" = "windows" ] && echo .exe)

	[ -x "$(command -v "$MIHOMO")" ] || {
		MIHOMO_VERSION=$(curl -L https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | jq -rc '.tag_name' 2>/dev/null)
		MIHOMOBALL=$MIHOMO-$MIHOMO_VERSION.$([ "$OS" = "windows" ] && echo zip || echo gz)
		curl -Lo $MIHOMOBALL "https://github.com/MetaCubeX/mihomo/releases/download/$MIHOMO_VERSION/$MIHOMOBALL"
		[ "$OS" = "windows" ] && unzip -jx $MIHOMOBALL || gzip -Nd $MIHOMOBALL
		rm -f $MIHOMOBALL 2>/dev/null
		chmod +x $MIHOMO
	}
fi


# downloadto <url> <target>
downloadto() {
	curl -Lo "$2" "$1" && echo >> "$2"
}

# payloadDomain <repo> <src> <dst>
payloadDomain() {
	cat <<-EOF > "$3"
	# Type: domain
	# Last Modified: `date -u '+%F %T %Z'`
	# Source:
	# - $1
	payload:
	EOF
	$SED -En "s|^|- '|; s|$|'|; p" "$2" >> "$3"
}

# payloadClassical <repo> <src> <dst>
payloadClassical() {
	cat <<-EOF > "$3"
	# Type: classical
	# Last Modified: `date -u '+%F %T %Z'`
	# Source:
	# - $1
	payload:
	EOF
	$SED -En "s|^(.+)|- \1|; s|^-(\s+#)| \1|; p" "$2" >> "$3"
}

# fmt2Domain <type> <src> [dst]
fmt2Domain() {
	local tmpfile=fmt2Domain.tmp

	case "$1" in
		dnsmasq)
			$SED 's|^|+.|' "$2" > $tmpfile
			;;
		list)
			# ONLY support DOMAIN and DOMAIN-SUFFIX
			grep -E "^(DOMAIN|DOMAIN-SUFFIX)," "$2" | $SED 's|^DOMAIN,||; s|^DOMAIN-SUFFIX,\.|.|; s|^DOMAIN-SUFFIX,|+.|' > $tmpfile
			;;
	esac
	[ -n "$3" ] && cp -f $tmpfile "$3" || cp -f $tmpfile "$2"
}

# convertClassical <src>
convertClassical() {
	local tmpfile_domain="${1%.*}.domain.tmp"
	local tmpfile_ipcidr="${1%.*}.ipcidr.tmp"
	local convfile="${1%.*}.conv"

	rm -f $tmpfile_domain $tmpfile_ipcidr $convfile
	rm -f "${1%.*}.*.mrs"

	for _key in $($SED 's|#.*||g;s|\(IP-CIDR\)6|\1|' "$1" | cut -f1 -d',' | sort -u); do
		case "$_key" in
			DOMAIN)
				$SED -En '/^DOMAIN,/{s|^[^,]+,([^,]+).*|\1|p}' "$1" >> $tmpfile_domain
				echo "$_key": "$(grep "^$_key," "$1" | wc -l)" >> $convfile
				;;
			DOMAIN-SUFFIX)
				$SED -En '/^DOMAIN-SUFFIX,/{s|^[^,]+,([^,]+).*|+.\1|p}' "$1" >> $tmpfile_domain
				echo "$_key": "$(grep "^$_key," "$1" | wc -l)" >> $convfile
				;;
			IP-CIDR)
				$SED -En '/^(IP-CIDR|IP-CIDR6),/{s|^[^,]+,([^,]+).*|\1|p}' "$1" >> $tmpfile_ipcidr
				echo "$_key": "$(grep "^$_key," "$1" | wc -l)" >> $convfile
				;;
			*)
				# Others
				echo "$1": "$_key" does not support conversion to binary.
				echo ::DROPED:: "$_key": "$(grep "^$_key," "$1" | wc -l)" >> $convfile
				;;
		esac
	done

	[ -f "$tmpfile_domain" ] && compilemrs $tmpfile_domain domain text
	[ -f "$tmpfile_ipcidr" ] && compilemrs $tmpfile_ipcidr ipcidr text
	return 0
}

push() {
	mkdir -p "$1" 2>/dev/null
	cd "$1" # github runner not support pushd
}

pop() {
	cd .. # github runner not support popd
}

# trim <src>
trim() {
	$SED -i 's|#.*||g; /^\s*$/d; s|\s||g' "$1"
}

# compilemrs <src> <ipcidr/domain> [src_type]
compilemrs() {
	[ -x "$(command -v "$MIHOMO")" ] && "$MIHOMO" convert-ruleset $2 ${3:-yaml} "$1" "${1%.*}.mrs"
}

update_ipcidr() {
	push 01
	# China IP
	## IPv4
	IPv4='IPv4.tmp'
	downloadto 'https://raw.githubusercontent.com/muink/route-list/release/china_ipv4.txt' "$IPv4"
	trim "$IPv4"

	## IPv6
	IPv6='IPv6.tmp'
	downloadto 'https://raw.githubusercontent.com/muink/route-list/release/china_ipv6.txt' "$IPv6"
	trim "$IPv6"

	# Merge IPv4 IPv6
	ChinaIP='ChinaIP.yml'
	cat <<-EOF > $ChinaIP
	# Type: ipcidr
	# Last Modified: `date -u '+%F %T %Z'`
	# Source:
	# - route-list: https://github.com/muink/route-list/blob/release/china_ipv4.txt
	# - route-list: https://github.com/muink/route-list/blob/release/china_ipv6.txt
	payload:
	EOF
	$SED -En "s|^|- '|; s|$|'|; p" "$IPv4" >> $ChinaIP
	$SED -En "s|^|- '|; s|$|'|; p" "$IPv6" >> $ChinaIP
	compilemrs $ChinaIP ipcidr

	# Cleanup
	rm -f *.tmp
	pop
}

update_cndomain() {
	push 01
	# China Domain
	## China Domain
	SRC='ChinaList.tmp'
	DST='ChinaList.yml'
	downloadto 'https://raw.githubusercontent.com/muink/route-list/release/china_list.txt' "$SRC"
	trim "$SRC"
	fmt2Domain dnsmasq "$SRC"

	payloadDomain "https://github.com/muink/route-list/blob/release/china_list.txt" "$SRC" "$DST"
	compilemrs "$DST" domain

	## China Domain Modified 2
	SRC='ChinaList2.tmp'
	DST='ChinaList2.yml'
	downloadto 'https://raw.githubusercontent.com/muink/route-list/release/china_list2.txt' "$SRC"
	trim "$SRC"
	fmt2Domain dnsmasq "$SRC"

	payloadDomain "https://github.com/muink/route-list/blob/release/china_list2.txt" "$SRC" "$DST"
	compilemrs "$DST" domain

	# Cleanup
	rm -f *.tmp
	pop
}

update_gfwdomain() {
	push 01
	# GFW Domain
	## GFWList
	SRC='gfwlist.tmp'
	DST='gfwlist.yml'
	downloadto 'https://raw.githubusercontent.com/muink/route-list/release/gfwlist.list' "$SRC"
	trim "$SRC"
	fmt2Domain list "$SRC"

	payloadDomain "https://github.com/muink/route-list/blob/release/gfwlist.list" "$SRC" "$DST"
	compilemrs "$DST" domain

	# Cleanup
	rm -f *.tmp
	pop
}

updatev2rayrulesdat() {
	push v2ray-rules-dat
	# v2ray-rules-dat
	downloadto 'https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/win-spy.txt' win-spy.tmp
	downloadto 'https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/win-update.txt' win-update.tmp
	downloadto 'https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/win-extra.txt' win-extra.tmp
	for f in win-spy.tmp win-update.tmp win-extra.tmp; do
		trim "$(basename $f)"
		sort -u "$(basename $f)" -o "$(basename $f)"

		payloadDomain "https://github.com/Loyalsoldier/v2ray-rules-dat/tree/release/${f%.*}.txt" "$(basename $f)" "$(basename -s.tmp $f).yml"
		compilemrs "$(basename -s.txt $f).yml" domain
	done

	# Cleanup
	rm -f *.tmp
	pop
}

updateACL4SSR() {
	push ACL4SSR
	# ACL4SSR
	downloadto 'https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/ProxyLite.list' ProxyLite.tmp
	downloadto 'https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/ProxyMedia.list' ProxyMedia.tmp
	downloadto 'https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/ChinaMedia.list' ChinaMedia.tmp
	downloadto 'https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/PrivateTracker.list' PrivateTracker.tmp
	for f in ProxyLite.tmp ProxyMedia.tmp ChinaMedia.tmp Ruleset/PrivateTracker.tmp; do
		payloadClassical "https://github.com/ACL4SSR/ACL4SSR/tree/master/Clash/${f%.*}.list" "$(basename $f)" "$(basename -s.tmp $f).yml"

		trim "$(basename $f)"
		sort -u "$(basename $f)" -o "$(basename $f)"
		convertClassical "$(basename $f)"
	done

	# Cleanup
	rm -f *.tmp
	pop
}

updateLM_Firefly() {
	push LM-Firefly
	# LM-Firefly
	downloadto 'https://raw.githubusercontent.com/LM-Firefly/Rules/master/Adblock/Adblock.list' Adblock.tmp
	downloadto 'https://raw.githubusercontent.com/LM-Firefly/Rules/master/Special/App-Activation.list' App-Activation.tmp
	downloadto 'https://raw.githubusercontent.com/LM-Firefly/Rules/master/Special/Local-LAN.list' Local-LAN.tmp
	downloadto 'https://raw.githubusercontent.com/LM-Firefly/Rules/master/Special/NTP-Service.list' NTP-Service.tmp
	downloadto 'https://raw.githubusercontent.com/LM-Firefly/Rules/master/Game.list' Game.tmp
	downloadto 'https://raw.githubusercontent.com/LM-Firefly/Rules/master/GlobalMedia.list' GlobalMedia.tmp
	downloadto 'https://raw.githubusercontent.com/LM-Firefly/Rules/master/SpeedTest.list' SpeedTest.tmp
	for f in Adblock/Adblock.tmp Special/App-Activation.tmp Special/Local-LAN.tmp Special/NTP-Service.tmp Game.tmp GlobalMedia.tmp SpeedTest.tmp; do
		payloadClassical "https://github.com/LM-Firefly/Rules/tree/master/${f%.*}.list" "$(basename $f)" "$(basename -s.tmp $f).yml"

		trim "$(basename $f)"
		sort -u "$(basename $f)" -o "$(basename $f)"
		convertClassical "$(basename $f)"
	done

	# Cleanup
	rm -f *.tmp
	pop
}



# Main
cd "$DSTDIR"
update_ipcidr
update_cndomain
update_gfwdomain
#updatev2rayrulesdat
updateACL4SSR
updateLM_Firefly
