#!/bin/bash
# Installs the idle switch-off: every 5 minutes the machine looks at itself, and after three looks in a row with nobody
# logged in, no container, build or check running and no load, it powers off. A stopped instance is not billed for
# processors or memory (its disk still is). Starting it again is `gcloud compute instances start`.
set -e
sudo tee /usr/local/bin/opsis-idle-stop >/dev/null <<'SCRIPT'
#!/bin/bash
count=/run/opsis-idle-count
# what the machine is doing, or "" for nothing: a run under way (tools/cloud/run.sh's state file), a login, a container
# or build process, or load
busy() {
    for state in /home/*/opsis/logs/state; do
        # a run that never wrote "done" (the machine rebooted under it) stops counting after 3 hours
        [ -f "$state" ] && [ "$(cat "$state")" != done ] && [ -n "$(find "$state" -mmin -180)" ] && { echo "run: $(cat "$state")"; return; }
    done
    who | grep -q . && { echo "login"; return; }
    # a copy or command over SSH under way (gcloud compute ssh/scp have no terminal, so `who` misses them): a build's
    # upload took 15 minutes with nothing else running, and the machine powered off under it (2026-10-16)
    ss -Htn state established '( sport = :22 )' | grep -q . && { echo "ssh"; return; }
    # Tacit's test computer (tacit-packages tools/vm touches its `last` on every command): in use while driven in the
    # last hour; one left running stops counting after that
    [ -n "$(find /home/*/tacit-vm/last -mmin -60 2>/dev/null)" ] && pgrep -x qemu-system-x86 >/dev/null && { echo "test computer"; return; }
    local p
    p=$(pgrep -f 'opsis-(setup|run)|containerd-shim|ninja|clang|cargo|autoninja|gclient|automate-git' | head -1)
    [ -n "$p" ] && { echo "process $(tr '\0' ' ' < /proc/$p/cmdline | cut -c1-60)"; return; }
    awk '{ exit !($1 >= 0.5) }' /proc/loadavg && { echo "load $(cut -d' ' -f1 /proc/loadavg)"; return; }
    echo ""
}
doing=$(busy)
if [ -n "$doing" ]; then
    echo 0 > $count
    logger "opsis-idle-stop: busy ($doing)"
else
    n=$(( $(cat $count 2>/dev/null || echo 0) + 1 ))
    echo $n > $count
    logger "opsis-idle-stop: idle, $n of 3"
    [ $n -ge 3 ] && { logger "opsis-idle-stop: idle for 15 minutes, powering off"; systemctl poweroff; }
fi
exit 0
SCRIPT
sudo chmod +x /usr/local/bin/opsis-idle-stop
sudo tee /etc/systemd/system/opsis-idle-stop.service >/dev/null <<'UNIT'
[Unit]
Description=Power the machine off when it has been idle for 15 minutes
[Service]
Type=oneshot
ExecStart=/usr/local/bin/opsis-idle-stop
UNIT
sudo tee /etc/systemd/system/opsis-idle-stop.timer >/dev/null <<'UNIT'
[Unit]
Description=Look for idleness every 5 minutes
[Timer]
OnBootSec=10min
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable -q --now opsis-idle-stop.timer
systemctl list-timers opsis-idle-stop.timer --no-pager | sed -n 2p
