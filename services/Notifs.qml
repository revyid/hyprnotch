pragma Singleton

//  Notifications — HyprNotch IS the notification daemon.
//
//  Quickshell's NotificationServer claims org.freedesktop.Notifications,
//  so as long as mako / dunst / swaync are NOT running, every banner
//  renders inside the island pill (start.sh kills them for you).
//
//  History entries are WRAPPER objects: they keep the live notification
//  (with dismiss() / actions) when one exists, or a synthetic shell for
//  internal toasts — the UI pipeline treats both identically.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Singleton {
    id: notifs

    readonly property int maxHistory: 50
    property var history: []             //  wrapper objects, newest first
    property var banners: []             //  currently on screen, newest first
    property int unseen: 0

    readonly property bool dnd: Config.get("notifications.dnd", false)
    readonly property int duration: Math.max(2, Config.get("notifications.duration", 5)) * 1000
    readonly property int maxBanners: Config.get("notifications.maxVisible", 3)

    //  ── server ────────────────────────────────────────────────────
    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true
        onNotification: function (notification) {
            notification.tracked = true
            notifs.push(notification)
        }
    }

    function push(n) {
        const entry = wrap(n)
        history = [entry].concat(history.slice(0, maxHistory - 1))
        if (!dnd) {
            unseen += 1
            if (banners.length < maxBanners) {
                banners = [entry].concat(banners)
            }
        }
    }

    //  Internal toast (plugins, shell feedback) through the same pipe.
    function toast(app, summary, body) {
        const entry = wrap(null, {
            app: app || "HyprNotch",
            summary: summary || "",
            body: body || "",
            icon: ""
        })
        history = [entry].concat(history.slice(0, maxHistory - 1))
        if (!dnd && banners.length < maxBanners)
            banners = [entry].concat(banners)
    }

    function wrap(raw, synth) {
        const entry = {
            raw: raw || null,
            app: raw ? (raw.appName || "App") : (synth ? synth.app : "App"),
            summary: raw ? (raw.summary || "") : (synth ? synth.summary : ""),
            body: raw ? (raw.body || "") : (synth ? synth.body : ""),
            icon: raw ? iconFor(raw) : ((synth && synth.icon) || ""),
            time: Date.now(),
            resident: raw ? raw.resident : false,
            actions: raw ? (raw.actions || []) : []
        }

        //  Closures over `entry` instead of `this` — V4-safe.
        entry.expire = function () {
            notifs.dismissBanner(entry)
        }
        entry.dismiss = function () {
            if (entry.raw) {
                try { entry.raw.dismiss() } catch (e) { /* already gone */ }
            }
            notifs.dismissBanner(entry)
            notifs.dropFromHistory(entry)
        }
        entry.activate = function () {
            if (entry.raw) {
                const a = defaultAction(entry.raw)
                if (a) {
                    try { a.invoke() } catch (e) { console.warn("notifs: action failed:", e) }
                    if (!entry.raw.resident)
                        entry.dismiss()
                    return
                }
                launchApp(entry.raw)
            }
            notifs.dismissBanner(entry)
        }
        return entry
    }

    function defaultAction(n) {
        if (!n || !n.actions)
            return null
        for (let i = 0; i < n.actions.length; ++i)
            if (n.actions[i].identifier === "default")
                return n.actions[i]
        return null
    }

    function bodyActions(n) {
        if (!n || !n.actions)
            return []
        const out = []
        for (let i = 0; i < n.actions.length; ++i)
            if (n.actions[i].identifier !== "default")
                out.push(n.actions[i])
        return out.slice(0, 2)
    }

    function iconFor(n) {
        if (!n)
            return ""
        if (n.image && n.image.length > 0)
            return n.image
        if (n.appIcon && n.appIcon.length > 0)
            return Quickshell.iconPath(n.appIcon, true)
        return ""
    }

    function invoke(entry, action) {
        if (!entry || !action)
            return
        try { action.invoke() } catch (e) { console.warn("notifs: action failed:", e) }
        if (!entry.resident)
            entry.dismiss()
    }

    function launchApp(n) {
        const id = (n.desktopEntry || "").toLowerCase()
        if (id.length === 0)
            return
        const apps = DesktopEntries.applications.values
        for (let i = 0; i < apps.length; ++i) {
            const a = apps[i]
            const appId = String(a.id || "").toLowerCase().replace(/\.desktop$/, "")
            if (appId === id) {
                try { a.execute() } catch (e) { console.warn("notifs: launch failed:", e) }
                return
            }
        }
    }

    //  ── banner queue management ───────────────────────────────────
    function dismissBanner(entry) {
        const idx = banners.indexOf(entry)
        if (idx >= 0) {
            const copy = banners.slice()
            copy.splice(idx, 1)
            banners = copy
        }
    }

    function holdBanners()  { bannerHold = true }
    function resumeBanners() { bannerHold = false }

    property bool bannerHold: false

    function markSeen() { unseen = 0 }

    function dropFromHistory(entry) {
        const idx = history.indexOf(entry)
        if (idx >= 0) {
            const copy = history.slice()
            copy.splice(idx, 1)
            history = copy
        }
    }

    function clearAll() {
        const list = history.slice()
        for (let i = 0; i < list.length; ++i)
            if (list[i].raw) {
                try { list[i].raw.dismiss() } catch (e) { /* already gone */ }
            }
        history = []
        banners = []
        unseen = 0
    }

    function toggleDnd() {
        Config.set("notifications.dnd", !dnd)
    }

    function formatAge(ts) {
        const mins = Math.max(0, Math.round((Date.now() - ts) / 60000))
        if (mins < 1) return "now"
        if (mins < 60) return mins + "m"
        const hrs = Math.round(mins / 60)
        if (hrs < 24) return hrs + "h"
        return Math.round(hrs / 24) + "d"
    }
}
