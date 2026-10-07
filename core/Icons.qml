pragma Singleton

//  Nerd Font glyph table (FontAwesome range, MesloLGS NF Mono).
//  One place for every icon so nothing drifts apart.

import QtQuick
import Quickshell

Singleton {
    readonly property string bell:             "\uF0F3"
    readonly property string bellSlash:        "\uF1F6"
    readonly property string wifi:             "\uF1EB"
    //  Wi-Fi strength set (Material range, k4-proven on MesloLGS NF)
    readonly property string wifi0:            String.fromCodePoint(0xF092D)
    readonly property string wifi1:            String.fromCodePoint(0xF091F)
    readonly property string wifi2:            String.fromCodePoint(0xF0922)
    readonly property string wifi3:            String.fromCodePoint(0xF0925)
    readonly property string wifi4:            String.fromCodePoint(0xF0928)
    readonly property string wifiOff:          String.fromCodePoint(0xF05AA)
    readonly property string bluetooth:        "\uF293"
    readonly property string batteryFull:      "\uF240"
    readonly property string batteryThreeQ:    "\uF241"
    readonly property string batteryHalf:      "\uF242"
    readonly property string batteryQuarter:   "\uF243"
    readonly property string batteryEmpty:     "\uF244"
    readonly property string bolt:             "\uF0E7"
    readonly property string plug:             "\uF1E6"
    readonly property string volumeHigh:       "\uF028"
    readonly property string volumeLow:        "\uF027"
    readonly property string volumeMute:       "\uF026"
    readonly property string mic:              "\uF130"
    readonly property string micSlash:         "\uF131"
    readonly property string moon:             "\uF186"
    readonly property string sun:              "\uF185"
    readonly property string lock:             "\uF023"
    readonly property string power:            "\uF011"
    readonly property string logout:           "\uF2F5"
    readonly property string gear:             "\uF013"
    readonly property string sliders:          "\uF1DE"
    readonly property string calendar:         "\uF073"
    readonly property string clock:            "\uF017"
    readonly property string camera:           "\uF030"
    readonly property string video:            "\uF03D"
    readonly property string terminal:         "\uF120"
    readonly property string search:           "\uF002"
    readonly property string close:            "\uF00D"
    readonly property string plus:             "\uF067"
    readonly property string check:            "\uF00C"
    readonly property string chevronLeft:      "\uF053"
    readonly property string chevronRight:     "\uF054"
    readonly property string chevronDown:      "\uF078"
    readonly property string trash:            "\uF1F8"
    readonly property string play:             "\uF04B"
    readonly property string pause:            "\uF04C"
    readonly property string forward:          "\uF051"
    readonly property string backward:         "\uF048"
    readonly property string music:            "\uF001"
    readonly property string image:            "\uF03E"
    readonly property string chip:             "\uF2DB"
    readonly property string chart:            "\uF080"
    readonly property string hdd:              "\uF0A0"
    readonly property string server:           "\uF233"
    readonly property string cubes:            "\uF1B3"
    readonly property string robot:            "\uF544"
    readonly property string tasks:            "\uF0AE"
    readonly property string user:             "\uF007"
    readonly property string circle:           "\uF111"
    readonly property string window:           "\uF2D0"
    readonly property string plane:            "\uF072"
    readonly property string circleCheck:      "\uF058"
    readonly property string warning:          "\uF12A"
    readonly property string arrowUp:          "\uF062"
    readonly property string arrowDown:        "\uF063"
    readonly property string folder:           "\uF07B"
    readonly property string download:         "\uF019"
    readonly property string desktop:          "\uF108"
    readonly property string cloud:            "\uF0C2"
    readonly property string spinner:          "\uF110"
    readonly property string refresh:          "\uF021"
    //  r28: focus timer + launcher calculator
    readonly property string hourglass:        "\uF252"
    readonly property string copy:             "\uF0C5"
    readonly property string stopwatch:        "\uF2E2"

    //  Bluetooth device categories (FontAwesome range)
    readonly property string headphones:       "\uF025"
    readonly property string phone:            "\uF10B"
    readonly property string mouseIcon:        "\uF245"
    readonly property string keyboard:         "\uF11C"
    readonly property string speaker:          "\uF028"
    readonly property string watch:            "\uF2E1"
    readonly property string gamepad:          "\uF11B"
    readonly property string laptop:           "\uF109"
    readonly property string printer:          "\uF02F"
    readonly property string tv:               "\uF26C"

    //  r16: distro identity, not Apple. `distro()` maps the os-release
    //  ID (then ID_LIKE) to a Nerd Font linux logo; unknown distros get
    //  Tux. Icons stays pure data — pass SysMon.osId / SysMon.osIdLike.
    function distro(id, like) {
        const t = (String(id || "") + " " + String(like || "")).toLowerCase()
        if (t.indexOf("arch") >= 0)     return String.fromCodePoint(0xF303)   // arch / omarchy / artix-adjacent
        if (t.indexOf("manjaro") >= 0)  return String.fromCodePoint(0xF31A)
        if (t.indexOf("endeavour") >= 0)return String.fromCodePoint(0xF322)
        if (t.indexOf("artix") >= 0)    return String.fromCodePoint(0xF31D)
        if (t.indexOf("void") >= 0)     return String.fromCodePoint(0xF31C)
        if (t.indexOf("nixos") >= 0)    return String.fromCodePoint(0xF313)
        if (t.indexOf("ubuntu") >= 0)   return String.fromCodePoint(0xF31B)
        if (t.indexOf("debian") >= 0)   return String.fromCodePoint(0xF306)
        if (t.indexOf("devuan") >= 0)   return String.fromCodePoint(0xF307)
        if (t.indexOf("mint") >= 0)     return String.fromCodePoint(0xF30E)
        if (t.indexOf("fedora") >= 0)   return String.fromCodePoint(0xF30A)
        if (t.indexOf("suse") >= 0)     return String.fromCodePoint(0xF314)
        if (t.indexOf("redhat") >= 0 || t.indexOf("rhel") >= 0) return String.fromCodePoint(0xF316)
        if (t.indexOf("gentoo") >= 0)   return String.fromCodePoint(0xF30D)
        if (t.indexOf("slackware") >= 0)return String.fromCodePoint(0xF319)
        if (t.indexOf("alpine") >= 0)   return String.fromCodePoint(0xF300)
        return "\uF17C"   // Tux — always resolvable
    }
    //  r7 extras: stats / power / wallpaper / about
    readonly property string leaf:             "\uF06C"
    readonly property string balance:          "\uF24E"
    readonly property string gauge:            "\uF0E4"
    readonly property string upload:           "\uF093"
    readonly property string thermometer:      "\uF2C7"
    readonly property string info:             "\uF05A"
    readonly property string pin:              "\uF276"
    readonly property string wind:             "\uF72E"
    readonly property string drop:             "\uF043"
    readonly property string memory:           "\uF538"
    readonly property string layer:            "\uF2D2"
    readonly property string bellBadge:        "\uF0A2"
    readonly property string palette:          "\uF043"
    readonly property string gradient:         "\uF58B"
    readonly property string devices:          "\uF6C0"
    readonly property string location:         "\uF041"

    function wifiIcon(level) {
        const icons = [wifi0, wifi1, wifi2, wifi3, wifi4]
        return icons[Math.max(0, Math.min(4, level))]
    }

    function btDeviceIcon(icon) {
        const s = icon ? icon : ""
        if (s.indexOf("headset") !== -1 || s.indexOf("headphone") !== -1) return headphones
        if (s.indexOf("phone") !== -1)    return phone
        if (s.indexOf("mouse") !== -1)    return mouseIcon
        if (s.indexOf("keyboard") !== -1) return keyboard
        if (s.indexOf("speaker") !== -1 || s.indexOf("audio") !== -1) return speaker
        if (s.indexOf("watch") !== -1)    return watch
        if (s.indexOf("gaming") !== -1 || s.indexOf("joystick") !== -1) return gamepad
        if (s.indexOf("computer") !== -1 || s.indexOf("laptop") !== -1) return laptop
        if (s.indexOf("printer") !== -1)  return printer
        if (s.indexOf("video") !== -1 || s.indexOf("tv") !== -1) return tv
        return devices
    }

    function batteryIcon(pct, charging) {
        if (charging)
            return bolt
        if (pct > 85) return batteryFull
        if (pct > 55) return batteryThreeQ
        if (pct > 30) return batteryHalf
        if (pct > 15) return batteryQuarter
        return batteryEmpty
    }

    function volumeIcon(pct, muted) {
        if (muted || pct <= 0)
            return volumeMute
        if (pct < 45)
            return volumeLow
        return volumeHigh
    }
}
