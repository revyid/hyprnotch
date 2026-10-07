pragma Singleton

//  System monitor — REALTIME, two long-running probes.
//
//  · main probe (every 2 s): CPU % + per-core %, RAM, swap, disk,
//    temperature, battery + watts, uptime, one-shot device identity.
//  · net probe (every 1 s): download / upload rates across all
//    physical interfaces.
//
//  Both print one "KEY value" line per metric; SplitParser ingests
//  them line by line, so every property here is live without ever
//  spawning a process per sample. CPU windows are self-normalized
//  (state files, delta math) — no sleep-inside-awk, no gawk-only
//  builtins, no wall-clock needed.
//
//  History buffers feed the StatsCard charts: 60 samples at ~2 s =
//  two minutes of CPU / RAM / network, ready to plot.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: sysmon

    //  ── live values ───────────────────────────────────────────────
    property real cpuPct: 0
    property var cpuCores: []            //  per-core %
    property real memPct: 0
    property real memUsedGb: 0
    property real memTotalGb: 0
    property real swapPct: 0
    property real diskPct: 0
    property real diskUsedGb: 0
    property real diskTotalGb: 0
    property real netRxKb: 0             //  KB/s down
    property real netTxKb: 0             //  KB/s up
    property real cpuTemp: 0
    property int batteryPct: 100
    property bool batteryPresent: false
    property bool batteryCharging: false
    property real batteryWatts: 0
    property string uptime: "--"

    //  ── low-battery alerts (r28) ──────────────────────────────────
    //  One toast per threshold per discharge cycle; flags reset the
    //  moment the charger comes back. Off by default-proof: the toast
    //  goes through Notifs, which respects DND — silent hours stay
    //  silent.
    property var lowFlags: ({})
    readonly property var lowThresholds: [20, 10, 5]

    //  ── device identity (About card) ──────────────────────────────
    property string hostName: ""
    property string osName: ""
    property string osId: ""            //  "arch", "ubuntu", … (os-release ID)
    property string osIdLike: ""        //  "debian arch", … (ID_LIKE fallback)
    property string kernelVer: ""
    property string cpuModel: ""
    property string gpuModel: ""

    //  ── history for charts (60 samples ≈ 2 min) ───────────────────
    readonly property int historyLen: 60
    property var cpuHist: []
    property var memHist: []
    property var netHist: []             //  rx+tx combined, KB/s

    function pushHist(arr, v) {
        const out = arr.slice()
        out.push(v)
        while (out.length > historyLen)
            out.shift()
        return out
    }

    readonly property string tmpDir: {
        const base = Quickshell.env("TMPDIR")
        return (base && base.length > 0 ? base : "/tmp") + "/hyprnotch-stats"
    }

    //  ── main probe ────────────────────────────────────────────────
    readonly property string probe: `
mkdir -p "${tmpDir}" 2>/dev/null
S1="${tmpDir}/cpu1"; S2="${tmpDir}/cpu2"

HOST=$(hostname 2>/dev/null || head -1 /etc/hostname 2>/dev/null)
[ -n "$HOST" ] && echo "HOST $HOST"
if [ -r /etc/os-release ]; then
  . /etc/os-release 2>/dev/null
  [ -n "$PRETTY_NAME" ] && echo "OS $PRETTY_NAME"
  [ -n "$ID" ] && echo "OSID $ID $ID_LIKE"
fi
echo "KERNEL $(uname -r)"
CM=$(awk -F: '/model name/{gsub(/^ /,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null)
[ -n "$CM" ] && echo "CPUMODEL $CM"
GM=$(lspci 2>/dev/null | awk -F: '/VGA|3D controller|Display/{gsub(/^ /,"",$3); print $3; exit}')
[ -n "$GM" ] && echo "GPUMODEL $GM"

while :; do
  grep '^cpu' /proc/stat > "$S2" 2>/dev/null
  if [ -s "$S1" ]; then
    awk '
      FNR==1 { f++ }
      f==1 { i1[$1]=$5+$6; t1[$1]=$2+$3+$4+$5+$6+$7+$8; next }
      {
        d = ($5+$6) - i1[$1]
        t = ($2+$3+$4+$5+$6+$7+$8) - t1[$1]
        p = (t > 0) ? int((t-d)*100/t) : 0
        if (p < 0) p = 0; if (p > 100) p = 100
        if ($1 == "cpu") { cp = p; next }
        out = out p " "
      }
      END { print "CPU " cp+0; print "CORES " out }
    ' "$S1" "$S2" 2>/dev/null
  fi
  mv -f "$S2" "$S1" 2>/dev/null

  free -b 2>/dev/null | awk '/^Mem:/{print "MEM "$3" "$2} /^Swap:/{if($2>0)print "SWAP "$3" "$2}'
  df -B1 / 2>/dev/null | awk 'END{print "DISK "$3" "$2" "$5}' | tr -d '%'

  TZ=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -rn | head -1)
  [ -n "$TZ" ] && echo "TEMP $((TZ/1000))"

  for b in /sys/class/power_supply/BAT*; do
    [ -d "$b" ] || continue
    cap=$(cat "$b/capacity" 2>/dev/null)
    st=$(cat "$b/status" 2>/dev/null)
    [ -n "$cap" ] && {
      echo "BAT $cap $st"
      [ -r "$b/power_now" ] && echo "WATT $(($(cat "$b/power_now" 2>/dev/null || echo 0) / 1000000))"
    }
    break
  done

  echo "UP $(awk -F. '{d=int($1/86400);h=int($1%86400/3600);m=int($1%3600/60); if(d>0)printf "%dd %dh",d,h; else printf "%dh %dm",h,m}' /proc/uptime)"
  sleep 2
done`

    //  ── network probe (1 s window, exact rates) ───────────────────
    readonly property string netProbe: `
mkdir -p "${tmpDir}" 2>/dev/null
N1="${tmpDir}/net1"; N2="${tmpDir}/net2"
sum() { awk -F'[: ]+' '/:/{if($2!="lo"){rx+=$3; tx+=$11}} END{print rx+0, tx+0}' /proc/net/dev 2>/dev/null; }
while :; do
  sum > "$N2" 2>/dev/null
  if [ -s "$N1" ]; then
    read OX OT < "$N1"
    read RX TX < "$N2"
    DRX=$(( (RX-OX) )); DTX=$(( (TX-OT) ))
    [ $DRX -lt 0 ] && DRX=0
    [ $DTX -lt 0 ] && DTX=0
    echo "NET $((DRX/1024)) $((DTX/1024))"
  fi
  mv -f "$N2" "$N1" 2>/dev/null
  sleep 1
done`

    Process {
        id: mainProbe
        command: ["sh", "-c", sysmon.probe]
        running: true
        stdout: SplitParser {
            onRead: function (line) { sysmon.parse(String(line).trim()) }
        }
        stderr: SplitParser {
            onRead: function (l) {
                const s = String(l).trim()
                if (s.length > 0) console.warn("sysmon:", s)
            }
        }
    }

    Process {
        id: netProbe
        command: ["sh", "-c", sysmon.netProbe]
        running: true
        stdout: SplitParser {
            onRead: function (line) { sysmon.parse(String(line).trim()) }
        }
        stderr: SplitParser {
            onRead: function (l) {
                const s = String(l).trim()
                if (s.length > 0) console.warn("sysmon-net:", s)
            }
        }
    }

    function parse(line) {
        if (line.length === 0)
            return
        const parts = line.split(/\s+/)
        switch (parts[0]) {
        case "HOST":  hostName = parts.slice(1).join(" "); break
        case "OS":    osName = parts.slice(1).join(" "); break
        case "OSID":  osId = (parts[1] || "").toLowerCase()
                      osIdLike = parts.slice(2).join(" ").toLowerCase()
                      break
        case "KERNEL":kernelVer = parts.slice(1).join(" "); break
        case "CPUMODEL": cpuModel = parts.slice(1).join(" "); break
        case "GPUMODEL": gpuModel = parts.slice(1).join(" "); break
        case "CPU":
            cpuPct = clamp(parseInt(parts[1]))
            cpuHist = pushHist(cpuHist, cpuPct)
            break
        case "CORES":
            const cores = []
            for (let i = 1; i < parts.length; ++i) {
                const v = parseInt(parts[i])
                if (!isNaN(v)) cores.push(clamp(v))
            }
            if (cores.length > 0)
                cpuCores = cores
            break
        case "MEM":
            if (parts.length >= 3) {
                const used = parseFloat(parts[1]), total = parseFloat(parts[2])
                if (total > 0) {
                    memUsedGb = used / 1073741824
                    memTotalGb = total / 1073741824
                    memPct = Math.round(used / total * 100)
                    memHist = pushHist(memHist, memPct)
                }
            }
            break
        case "SWAP":
            if (parts.length >= 3 && parseFloat(parts[2]) > 0)
                swapPct = Math.round(parseFloat(parts[1]) / parseFloat(parts[2]) * 100)
            break
        case "DISK":
            if (parts.length >= 4) {
                diskUsedGb = parseFloat(parts[1]) / 1073741824
                diskTotalGb = parseFloat(parts[2]) / 1073741824
                diskPct = parseInt(parts[3])
            }
            break
        case "NET":
            netRxKb = Math.max(0, parseFloat(parts[1]) || 0)
            netTxKb = Math.max(0, parseFloat(parts[2]) || 0)
            netHist = pushHist(netHist, netRxKb + netTxKb)
            break
        case "TEMP":
            cpuTemp = parseFloat(parts[1]) || 0
            break
        case "BAT":
            batteryPresent = true
            batteryPct = Math.max(0, Math.min(100, parseInt(parts[1]) || 0))
            const wasCharging = batteryCharging
            batteryCharging = (parts[2] === "Charging" || parts[2] === "Full")
            if (batteryCharging && !wasCharging)
                lowFlags = ({})            //  fresh discharge cycle
            if (!batteryCharging)
                lowBatteryCheck()
            break
        case "WATT":
            batteryWatts = parseFloat(parts[1]) || 0
            break
        case "UP":
            uptime = parts.slice(1).join(" ")
            break
        }
    }

    function clamp(v) {
        return Math.max(0, Math.min(100, isNaN(v) ? 0 : v))
    }

    function lowBatteryCheck() {
        if (!batteryPresent)
            return
        for (let i = 0; i < lowThresholds.length; ++i) {
            const t = lowThresholds[i]
            if (batteryPct <= t && lowFlags[t] !== true) {
                const copy = {}
                for (const k in lowFlags) copy[k] = lowFlags[k]
                copy[t] = true
                lowFlags = copy
                Notifs.toast("Battery", batteryPct + "% remaining",
                    t <= 10 ? "plug in — running on fumes" : "find a charger soon")
            }
        }
    }

    function formatGb(v) {
        return (v >= 10 ? Math.round(v) : Math.round(v * 10) / 10) + " GB"
    }

    function formatKb(kb) {
        if (kb >= 1024)
            return (Math.round(kb / 102.4) / 10) + " MB/s"
        return Math.round(kb) + " KB/s"
    }

    function formatWatts(w) {
        return (w >= 100 ? Math.round(w) : Math.round(w * 10) / 10) + " W"
    }
}
