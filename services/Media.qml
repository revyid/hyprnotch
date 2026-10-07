pragma Singleton

//  Media via MPRIS: now playing card data + transport controls.
//  Picks the playing player first, otherwise the first known player.

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Singleton {
    id: media

    readonly property var player: {
        const players = Mpris.players ? Mpris.players.values : []
        for (let i = 0; i < players.length; ++i)
            if (players[i].isPlaying)
                return players[i]
        return players.length > 0 ? players[0] : null
    }

    readonly property bool hasPlayer: player !== null
    readonly property bool playing: hasPlayer && player.isPlaying
    readonly property string title: hasPlayer ? (player.trackTitle || "Unknown title") : ""
    readonly property string artist: hasPlayer ? (player.trackArtist || "") : ""
    readonly property string artUrl: hasPlayer ? (player.trackArtUrl || "") : ""

    readonly property real position: hasPlayer && player.positionSupported ? (player.position || 0) : 0
    readonly property real length: hasPlayer && player.length ? player.length : 0

    //  ── Live progress: MPRIS only announces seeks, so the bar ticks
    //  locally every second while the player reports playing, and snaps
    //  back to the real position on track change / play state change.
    property real livePosition: 0
    readonly property real progress: length > 0
        ? Math.max(0, Math.min(1, livePosition / length)) : 0

    onHasPlayerChanged: Qt.callLater(_syncLive)

    function _syncLive() {
        if (hasPlayer)
            livePosition = position
    }

    Connections {
        target: media.player
        ignoreUnknownSignals: true
        function onTrackTitleChanged() { media._syncLive() }
        function onIsPlayingChanged()  { media._syncLive() }
    }

    Timer {
        interval: 1000
        running: media.playing && media.length > 0
        repeat: true
        triggeredOnStart: false
        onTriggered: media.livePosition = Math.min(media.livePosition + 1, media.length)
    }

    function playPause() { if (hasPlayer && player.canPlay) player.togglePlaying() }
    function next()       { if (hasPlayer && player.canGoNext) player.next() }
    function previous()   { if (hasPlayer && player.canGoPrevious) player.previous() }

    //  ── Seek (r28): the media tile's progress bar is now draggable.
    //  MPRIS players expose canSeek; when they do, writing `position`
    //  moves playback, and the local ticker re-bases on the new spot
    //  immediately so the bar never snaps back.
    readonly property bool canSeek: hasPlayer && player.canSeek === true

    function seek(seconds) {
        if (!canSeek)
            return
        const target = Math.max(0, length > 0 ? Math.min(seconds, length - 1) : seconds)
        player.position = Math.round(target)
        livePosition = player.position
    }

    function formatTime(seconds) {
        const s = Math.floor(seconds)
        const m = Math.floor(s / 60), r = s % 60
        return m + ":" + (r < 10 ? "0" : "") + r
    }
}
