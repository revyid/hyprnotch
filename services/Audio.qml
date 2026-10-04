pragma Singleton

//  Audio via Pipewire: default sink volume/mute, default source (mic)
//  mute, and HUD triggering when volume changes from outside (keys,
//  mouse, other apps). Mirrors the macOS approach: change it anywhere,
//  the island shows the level.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: audio

    property int volume: 0
    property bool muted: false
    property int micVolume: 0
    property bool micMuted: false
    property bool hudOpen: false

    readonly property bool ready: _sink !== null && _sink !== undefined

    PwObjectTracker {
        objects: {
            const arr = []
            if (Pipewire.defaultAudioSink)
                arr.push(Pipewire.defaultAudioSink)
            if (Pipewire.defaultAudioSource)
                arr.push(Pipewire.defaultAudioSource)
            return arr
        }
    }

    readonly property var _sink: Pipewire.defaultAudioSink
    readonly property var _source: Pipewire.defaultAudioSource

    on_SinkChanged: Qt.callLater(_readSink)
    on_SourceChanged: Qt.callLater(_readSource)

    Connections {
        target: audio._sink ? audio._sink.audio : null
        function onVolumeChanged() { audio._readSink() }
        function onMutedChanged()  { audio._readSink() }
    }

    Connections {
        target: audio._source ? audio._source.audio : null
        function onVolumeChanged() { audio._readSource() }
        function onMutedChanged()  { audio._readSource() }
    }

    function _readSink() {
        if (!_sink || !_sink.audio)
            return
        const v = Math.round(_sink.audio.volume * 100)
        const m = _sink.audio.muted
        if (v !== volume || m !== muted) {
            volume = v
            muted = m
            _flashHud()
        }
    }

    function _readSource() {
        if (!_source || !_source.audio)
            return
        micVolume = Math.round(_source.audio.volume * 100)
        micMuted = _source.audio.muted
    }

    function setVolume(pct) {
        if (!_sink || !_sink.audio)
            return
        const p = Math.max(0, Math.min(100, pct))
        _sink.audio.volume = p / 100
        _sink.audio.muted = (p === 0)
        _flashHud()
    }

    function toggleMute() {
        if (!_sink || !_sink.audio)
            return
        _sink.audio.muted = !_sink.audio.muted
    }

    function toggleMic() {
        if (!_source || !_source.audio)
            return
        _source.audio.muted = !_source.audio.muted
    }

    Timer {
        id: hudTimer
        interval: Config.get("hud.timeout", 1600)
        onTriggered: audio.hudOpen = false
    }

    function _flashHud() {
        if (!Config.get("hud.enabled", true))
            return
        hudOpen = true
        hudTimer.restart()
    }
}
