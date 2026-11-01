@echo off
chcp 65001 > nul
:: 65001 - UTF-8
::
:: LEAN variant of "general (ALT9).bat" (generated).
:: Same UDP desync rules as the original profile; its TCP rules are dropped because the LEAN
:: capture filter never delivers TCP packets to winws. Only QUIC-handshake packets sent to
:: Cloudflare WARP addresses are diverted (see "general (WARP LEAN).bat" for details).
:: Keep exclamation marks out of this file - the launcher runs with delayed expansion enabled.

for %%I in ("%~dp0..") do set "ROOT=%%~fI\"
cd /d "%ROOT%"
call service.bat load_game_filter
call service.bat load_user_lists
echo:

set "BIN=%ROOT%bin\"
set "LISTS=%ROOT%lists\"
cd /d "%BIN%"

set "WFRAW=not impostor and not loopback and outbound and udp and udp.PayloadLength>=1 and udp.Payload[0]>=0xC0 and ((ip.DstAddr>=162.159.0.0 and ip.DstAddr<=162.159.255.255) or (ip.DstAddr>=188.114.96.0 and ip.DstAddr<=188.114.99.255) or (ipv6.DstAddr>=2606:4700:: and ipv6.DstAddr<=2606:4700:ffff:ffff:ffff:ffff:ffff:ffff)) and (udp.DstPort==443 or udp.DstPort==500 or udp.DstPort==1701 or udp.DstPort==4443 or udp.DstPort==4500 or udp.DstPort==8095 or udp.DstPort==8443)"

start "zapret: %~n0" /min "%BIN%winws.exe" --wf-raw="%WFRAW%" ^
--filter-udp=443 --hostlist="%LISTS%list-general.txt" --hostlist="%LISTS%list-general-user.txt" --hostlist-exclude="%LISTS%list-exclude.txt" --hostlist-exclude="%LISTS%list-exclude-user.txt" --ipset-exclude="%LISTS%ipset-exclude.txt" --ipset-exclude="%LISTS%ipset-exclude-user.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="%BIN%quic_initial_www_google_com.bin" --new ^
--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-fake-discord="%BIN%ACTIVE_DISCORD_UDP.bin" --dpi-desync-fake-stun="%BIN%ACTIVE_DISCORD_UDP.bin" --dpi-desync-repeats=6 --new ^
--filter-udp=443 --ipset="%LISTS%ipset-all.txt" --hostlist-exclude="%LISTS%list-exclude.txt" --hostlist-exclude="%LISTS%list-exclude-user.txt" --ipset-exclude="%LISTS%ipset-exclude.txt" --ipset-exclude="%LISTS%ipset-exclude-user.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="%BIN%quic_initial_www_google_com.bin" --new ^
--filter-udp=%GameFilterUDP% --ipset="%LISTS%ipset-all.txt" --ipset-exclude="%LISTS%ipset-exclude.txt" --ipset-exclude="%LISTS%ipset-exclude-user.txt" --dpi-desync=fake --dpi-desync-repeats=12 --dpi-desync-any-protocol=1 --dpi-desync-fake-unknown-udp="%BIN%ACTIVE_GAME_UDP.bin" --dpi-desync-cutoff=n2
