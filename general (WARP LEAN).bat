@echo off
chcp 65001 > nul
:: 65001 - UTF-8
::
:: WARP LEAN - minimal-overhead profile for "games via Cloudflare WARP".
::
:: Why it exists: zapret is only needed to get the WARP (MASQUE/QUIC) handshake through DPI.
:: The classic general*.bat profiles hand EVERY packet of TCP 80/443/2053-2096/8443 and
:: UDP 443/19294-19344/50000-50100 to winws in user space, in both directions - including
:: all the traffic that is already inside the tunnel (the WARP virtual adapter is visible
:: to WinDivert). That costs CPU time and adds queueing jitter to every game packet.
::
:: This profile uses a full custom WinDivert filter (--wf-raw) that lets the kernel pass
:: everything else straight through and diverts ONLY:
::   - outbound UDP,
::   - to Cloudflare WARP address ranges (162.159.0.0/16, 188.114.96.0/22, 2606:4700::/32),
::   - on the WARP ports (443 + fallbacks 500,1701,4443,4500,8095,8443),
::   - whose first payload byte is a QUIC long header (>= 0xC0: Initial/Handshake).
:: Short-header QUIC packets (all tunnel data after the handshake) never reach winws.
::
:: NOTE: keep exclamation marks out of this file - the launcher runs with delayed expansion enabled.
:: NOTE: it does not touch TCP settings (no "netsh ... timestamps"), because there are no TCP rules.

set "BIN=%~dp0bin\"
cd /d "%BIN%"

set "WFRAW=not impostor and not loopback and outbound and udp and udp.PayloadLength>=1 and udp.Payload[0]>=0xC0 and ((ip.DstAddr>=162.159.0.0 and ip.DstAddr<=162.159.255.255) or (ip.DstAddr>=188.114.96.0 and ip.DstAddr<=188.114.99.255) or (ipv6.DstAddr>=2606:4700:: and ipv6.DstAddr<=2606:4700:ffff:ffff:ffff:ffff:ffff:ffff)) and (udp.DstPort==443 or udp.DstPort==500 or udp.DstPort==1701 or udp.DstPort==4443 or udp.DstPort==4500 or udp.DstPort==8095 or udp.DstPort==8443)"

start "zapret: %~n0" /min "%BIN%winws.exe" --wf-raw="%WFRAW%" ^
--filter-udp=443 --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="%BIN%quic_initial_www_google_com.bin" --new ^
--filter-udp=500,1701,4443,4500,8095,8443 --dpi-desync=fake --dpi-desync-repeats=12 --dpi-desync-any-protocol=1 --dpi-desync-fake-unknown-udp="%BIN%ACTIVE_GAME_UDP.bin" --dpi-desync-cutoff=n2
