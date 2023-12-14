#!/bin/sh

CURRENTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DSTDIR="$CURRENTDIR/shared"
cd "$DSTDIR"



# downloadto <url> <target>
downloadto() {
	curl -Lo "$2" "$1" && echo >> "$2"
}

# writedomain <repo> <src> <dst>
writedomain() {
	cat <<-EOF > "$3"
		{
		  "__Source__": "$1",
		  "__last_modified__": "$(date -u '+%F %T %Z')",
		  "version": 1,
		  "rules": [
		    {
		      "domain": [
	EOF
	sed -En 's|^|        "|; s|$|",|; p' "$2" >> "$3"
	sed -i '${s|,$||}' "$3"
	cat <<-EOF >> "$3"
		      ],
		      "domain_suffix": [
	EOF
	sed -En 's|^|        ".|; s|$|",|; p' "$2" >> "$3"
	sed -i '${s|,$||}' "$3"
	cat <<-EOF >> "$3"
		      ]
		    }
		  ]
		}
	EOF
}

push() {
	cd "$1" # github runner not support pushd
}

pop() {
	cd .. # github runner not support popd
}

update_ipcidr() {
	push 01
	# China IP
	## IPv4
	IPv4='IPv4.tmp'
	downloadto 'https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt' ipip.tmp
	downloadto 'https://raw.githubusercontent.com/metowolf/iplist/master/data/special/china.txt' cz88.tmp
	downloadto 'https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt' coipv4.tmp
	## Merge IPv4
	cat ipip.tmp cz88.tmp coipv4.tmp | sort -u > "$IPv4"
	sed -i '/#.*/d; /^\s*$/d; s|\s||g' "$IPv4"
	sort -n -t'.' -k1,1 -k2,2 -k3,3 -k4,4 "$IPv4" -o "$IPv4"

	## IPv6
	IPv6='IPv6.tmp'
	downloadto 'https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china6.txt' coipv6.tmp
	downloadto 'http://www.ipdeny.com/ipv6/ipaddresses/aggregated/cn-aggregated.zone' ipdeny6.tmp && sed -Ei 's|(:0{1,4})+/|::/|' ipdeny6.tmp
	## Merge IPv6
	cat coipv6.tmp ipdeny6.tmp | sort -u > "$IPv6"
	sed -i '/^#/d; /^\s*$/d; s|\s||g' "$IPv6"

	# Merge IPv4 IPv6
	ChinaIP='ChinaIP.json'
	cat <<-EOF > $ChinaIP
		{
		  "__ipv4__": {
		    "ipip": "https://github.com/17mon/china_ip_list/blob/master/china_ip_list.txt",
		    "cz88": "https://github.com/metowolf/iplist/blob/master/data/special/china.txt",
		    "coip": "https://github.com/gaoyifan/china-operator-ip/blob/ip-lists/china.txt"
		  },
		  "__ipv6__": {
		    "deny6": "http://www.ipdeny.com/ipv6/ipaddresses/aggregated/cn-aggregated.zone",
		    "coip6": "https://github.com/gaoyifan/china-operator-ip/blob/ip-lists/china6.txt"
		  },
		  "__last_modified__": "$(date -u '+%F %T %Z')",
		  "version": 1,
		  "rules": [
		    {
		      "ip_cidr": [
	EOF
	sed -En 's|^|        "|; s|$|",|; p' "$IPv4" >> $ChinaIP
	sed -En 's|^|        "|; s|$|",|; p' "$IPv6" >> $ChinaIP
	sed -i '${s|,$||}' $ChinaIP
	cat <<-EOF >> $ChinaIP
		      ]
		    }
		  ]
		}
	EOF

	# Cleanup
	rm -f *.tmp
	pop
}

update_cndomain() {
	push 01
	# China Domain
	## China Domain Modified
	#SRC='ChinaDomainModified.tmp'
	#DST='ChinaDomainModified.json'
	#downloadto 'https://raw.githubusercontent.com/muink/dnsmasq-china-tool/list/accelerated-domains.china.conf' "$SRC"
	#sed -i 's|#.*||g; /^\s*$/d; s|\s||g' "$SRC"
	#sed -Ei "s|/[0-9]+(\.[0-9]+){3}$||; s|^server=/||" "$SRC"
	#sort -u "$SRC" -o "$SRC"
	#writedomain "https://github.com/muink/dnsmasq-china-tool/blob/list/accelerated-domains.china.conf" "$SRC" "$DST"

	## China Domain Modified 2
	SRC='ChinaDomainModified2.tmp'
	DST='ChinaDomainModified2.json'
	downloadto 'https://raw.githubusercontent.com/muink/dnsmasq-china-tool/list/accelerated-domains2.china.conf' "$SRC"
	sed -i 's|#.*||g; /^\s*$/d; s|\s||g' "$SRC"
	sed -Ei "s|/[0-9]+(\.[0-9]+){3}$||; s|^server=/||" "$SRC"
	sort -u "$SRC" -o "$SRC"
	writedomain "https://github.com/muink/dnsmasq-china-tool/blob/list/accelerated-domains2.china.conf" "$SRC" "$DST"

	## China Domain
	SRC='ChinaDomain.tmp'
	DST='ChinaDomain.json'
	downloadto 'https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf' "$SRC"
	sed -i 's|#.*||g; /^\s*$/d; s|\s||g' "$SRC"
	sed -Ei "s|/[0-9]+(\.[0-9]+){3}$||; s|^server=/||" "$SRC"
	sort -u "$SRC" -o "$SRC"
	writedomain "https://github.com/felixonmars/dnsmasq-china-list/blob/master/accelerated-domains.china.conf" "$SRC" "$DST"

	# Cleanup
	rm -f *.tmp
	pop
}

update_gfwdomain() {
	push 01
	# GFW Domain
	## GFWList
	SRC='gfwlist.tmp'
	DST='gfwlist.json'
	downloadto 'https://raw.githubusercontent.com/cokebar/gfwlist2dnsmasq/master/gfwlist2dnsmasq.sh' gfwlist2dnsmasq.sh
	bash gfwlist2dnsmasq.sh -o "$SRC"
	sed -i 's|#.*||g; /^\s*$/d; s|\s||g' "$SRC"
	sed -Ei "s|/[0-9]+(\.[0-9]+){3}$||; s|^server=/||" "$SRC"
	sort -u "$SRC" -o "$SRC"
	writedomain "https://github.com/gfwlist/gfwlist/blob/master/gfwlist.txt" "$SRC" "$DST"

	# Cleanup
	rm -f gfwlist2dnsmasq.sh
	rm -f *.tmp
	pop
}

updatev2rayrulesdat() {
	push v2ray-rules-dat
	# v2ray-rules-dat
	SRC='direct-list.tmp'
	DST='direct-list.json'
	downloadto 'https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/direct-list.txt' "$SRC"
	sed -i 's|#.*||g; /^\s*$/d; s|\s||g' "$SRC"
	sort -u "$SRC" -o "$SRC"
	sed -En 's|^full:(.+)$|\1|p' "$SRC" > "${SRC%.*}.full.tmp" #&& sed -i '/^full:/d' "$SRC"
	grep -E '^[a-zA-Z0-9\.-]+$' "$SRC" > "${SRC%.*}.suffix.tmp" #&& sed -Ei '/^[a-zA-Z0-9\.-]+$/d' "$SRC"
	sed -En 's|^regexp:(.+)$|\1|;s|\\|\\\\|gp' "$SRC" > "${SRC%.*}.regexp.tmp" #&& sed -i '/^regexp:/d' "$SRC"
	cat <<-EOF > "$DST"
		{
		  "__Source__": "https://github.com/Loyalsoldier/v2ray-rules-dat/tree/release/direct-list.txt",
		  "__last_modified__": "$(date -u '+%F %T %Z')",
		  "version": 1,
		  "rules": [
		    {
		      "domain": [
	EOF
	sed -En 's|^|        "|; s|$|",|; p' "${SRC%.*}.full.tmp" >> "$DST"
	sed -i '${s|,$||}' "$DST"
	cat <<-EOF >> "$DST"
		      ],
		      "domain_suffix": [
	EOF
	sed -En 's|^|        ".|; s|$|",|; p' "${SRC%.*}.suffix.tmp" >> "$DST"
	sed -i '${s|,$||}' "$DST"
	cat <<-EOF >> "$DST"
		      ],
		      "domain_regex": [
	EOF
	sed -En 's|^|        "|; s|$|",|; p' "${SRC%.*}.regexp.tmp" >> "$DST"
	sed -i '${s|,$||}' "$DST"
	cat <<-EOF >> "$DST"
		      ]
		    }
		  ]
		}
	EOF

	downloadto 'https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/reject-list.txt' reject-list.tmp
	downloadto 'https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/win-spy.txt' win-spy.tmp
	downloadto 'https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/win-update.txt' win-update.tmp
	downloadto 'https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/win-extra.txt' win-extra.tmp
	for f in reject-list.tmp win-spy.tmp win-update.tmp win-extra.tmp; do
		sed -i 's|#.*||g; /^\s*$/d; s|\s||g' "$f"
		sort -u "$f" -o "$f"
		writedomain "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/${f%.*}.txt" "$f" "${f%.*}.json"
	done

	# Cleanup
	rm -f *.tmp
	pop
}



update_ipcidr
update_cndomain
update_gfwdomain
updatev2rayrulesdat
