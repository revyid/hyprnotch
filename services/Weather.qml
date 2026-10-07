pragma Singleton

//  Weather, via Open-Meteo.
//
//  No API key and no account: fetched with curl, parsed as JSON. The
//  location is guessed from IP the first time — approximate, so it lands
//  on the nearest big city — and from then on whatever you search for
//  wins, persisted to ~/.local/state/hyprnotch/weather.json.
//
//  The codes are the WMO codes Open-Meteo returns; the map below turns
//  them into glyph + description, with day and night variants where it
//  makes sense. Glyphs are the Nerd Font weather range, same codepoints
//  k4 renders on the same font.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: weather

    readonly property string stateFile: Quickshell.env("HOME") + "/.local/state/hyprnotch/weather.json"

    // ── location ──────────────────────────────────────────────────
    property string place: ""
    property string region: ""
    property real latitude: 0
    property real longitude: 0
    property bool located: false

    // ── data ──────────────────────────────────────────────────────
    property var current: null      // { temp, feels, humidity, precip, wind, code, isDay }
    property var hourly: []         // [{ hour, temp, code, rain, isDay }]
    property var daily: []          // [{ date, code, max, min }]
    property string updated: ""

    property bool loading: false
    property string error: ""

    // city search results
    property var matches: []
    property bool searching: false

    readonly property bool ready: current !== null

    // ── WMO codes → glyph + description ──────────────────────────
    readonly property var codes: ({
        0:  { d: 0xE30D, n: 0xE32B, t: "Clear" },
        1:  { d: 0xE30D, n: 0xE32B, t: "Mostly clear" },
        2:  { d: 0xE302, n: 0xE37E, t: "Partly cloudy" },
        3:  { d: 0xE312, n: 0xE312, t: "Overcast" },
        45: { d: 0xE303, n: 0xE346, t: "Fog" },
        48: { d: 0xE303, n: 0xE346, t: "Freezing fog" },
        51: { d: 0xE30B, n: 0xE328, t: "Light drizzle" },
        53: { d: 0xE31B, n: 0xE31B, t: "Drizzle" },
        55: { d: 0xE31B, n: 0xE31B, t: "Heavy drizzle" },
        56: { d: 0xE3AD, n: 0xE3AD, t: "Freezing drizzle" },
        57: { d: 0xE3AD, n: 0xE3AD, t: "Heavy freezing drizzle" },
        61: { d: 0xE308, n: 0xE325, t: "Light rain" },
        63: { d: 0xE318, n: 0xE318, t: "Rain" },
        65: { d: 0xE318, n: 0xE318, t: "Heavy rain" },
        66: { d: 0xE3AD, n: 0xE3AD, t: "Freezing rain" },
        67: { d: 0xE3AD, n: 0xE3AD, t: "Heavy freezing rain" },
        71: { d: 0xE30A, n: 0xE327, t: "Light snow" },
        73: { d: 0xE31A, n: 0xE31A, t: "Snow" },
        75: { d: 0xE31A, n: 0xE31A, t: "Heavy snow" },
        77: { d: 0xE31A, n: 0xE31A, t: "Snow grains" },
        80: { d: 0xE309, n: 0xE326, t: "Showers" },
        81: { d: 0xE319, n: 0xE319, t: "Showers" },
        82: { d: 0xE319, n: 0xE319, t: "Heavy showers" },
        85: { d: 0xE30A, n: 0xE327, t: "Snow showers" },
        86: { d: 0xE31A, n: 0xE31A, t: "Heavy snow showers" },
        95: { d: 0xE30F, n: 0xE32A, t: "Thunderstorm" },
        96: { d: 0xE314, n: 0xE314, t: "Thunderstorm with hail" },
        99: { d: 0xE314, n: 0xE314, t: "Thunderstorm with heavy hail" }
    })

    function icon(code, isDay) {
        const entry = codes[code]
        if (!entry)
            return String.fromCodePoint(0xE374)   // weather not available
        return String.fromCodePoint(isDay === false ? entry.n : entry.d)
    }

    function describe(code) {
        const entry = codes[code]
        return entry ? entry.t : "No data"
    }

    // ── queries ───────────────────────────────────────────────────
    function refresh() {
        if (!located)
            return

        loading = true
        error = ""
        forecast.command = ["curl", "-s", "--max-time", "15",
            "https://api.open-meteo.com/v1/forecast"
            + "?latitude=" + latitude
            + "&longitude=" + longitude
            + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,"
            + "precipitation,weather_code,wind_speed_10m"
            + "&hourly=temperature_2m,weather_code,precipitation_probability"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
            + "&timezone=auto&forecast_days=6&forecast_hours=24"]
        forecast.running = true
    }

    function locate() {
        loading = true
        ipLookup.running = true
    }

    function search(query) {
        const q = query.trim()
        if (q.length < 2) {
            matches = []
            return
        }

        searching = true
        geocode.command = ["curl", "-s", "--max-time", "12",
            "https://geocoding-api.open-meteo.com/v1/search"
            + "?name=" + encodeURIComponent(q) + "&count=6&language=en&format=json"]
        geocode.running = true
    }

    function setPlace(name, area, lat, lon) {
        place = name
        region = area
        latitude = lat
        longitude = lon
        located = true
        matches = []
        save()
        refresh()
    }

    // ── persistence ───────────────────────────────────────────────
    function save() {
        stateView.setText(JSON.stringify({
            place: place, region: region,
            latitude: latitude, longitude: longitude
        }, null, 2))
    }

    function load() {
        const raw = stateView.text()
        if (raw.length === 0) {
            locate()          // first time: guess from IP
            return
        }

        let s
        try {
            s = JSON.parse(raw)
        } catch (e) {
            locate()
            return
        }

        if (s.latitude === undefined || s.longitude === undefined) {
            locate()
            return
        }

        place = s.place || ""
        region = s.region || ""
        latitude = s.latitude
        longitude = s.longitude
        located = true
        refresh()
    }

    FileView { id: stateView; path: weather.stateFile; blockLoading: true }

    Process {
        //  the state lives in ~/.local/state/hyprnotch, which may not exist yet
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/hyprnotch"]
        running: true
        onExited: weather.load()
    }

    Process {
        id: ipLookup
        command: ["curl", "-s", "--max-time", "10", "https://ipwho.is/"]

        stdout: StdioCollector {
            onStreamFinished: {
                let d
                try {
                    d = JSON.parse(this.text)
                } catch (e) {
                    weather.error = "Could not locate by IP"
                    weather.loading = false
                    return
                }

                if (!d.success) {
                    weather.error = "Could not locate by IP"
                    weather.loading = false
                    return
                }

                weather.setPlace(d.city || "", d.region || d.country || "",
                                 d.latitude, d.longitude)
            }
        }
    }

    Process {
        id: geocode

        stdout: StdioCollector {
            onStreamFinished: {
                weather.searching = false
                let d
                try {
                    d = JSON.parse(this.text)
                } catch (e) {
                    weather.matches = []
                    return
                }

                const found = []
                const list = d.results || []
                for (let i = 0; i < list.length; ++i) {
                    found.push({
                        name: list[i].name,
                        region: [list[i].admin1, list[i].country]
                            .filter(function (x) { return !!x }).join(" · "),
                        latitude: list[i].latitude,
                        longitude: list[i].longitude
                    })
                }
                weather.matches = found
            }
        }

        onExited: weather.searching = false
    }

    Process {
        id: forecast

        stdout: StdioCollector {
            onStreamFinished: {
                weather.loading = false

                let d
                try {
                    d = JSON.parse(this.text)
                } catch (e) {
                    weather.error = "Unreadable service response"
                    return
                }

                if (!d.current) {
                    weather.error = "No data for this location"
                    return
                }

                weather.error = ""
                weather.current = {
                    temp: Math.round(d.current.temperature_2m),
                    feels: Math.round(d.current.apparent_temperature),
                    humidity: d.current.relative_humidity_2m,
                    precip: d.current.precipitation,
                    wind: Math.round(d.current.wind_speed_10m),
                    code: d.current.weather_code,
                    isDay: d.current.is_day === 1
                }
                weather.updated = d.current.time.substring(11, 16)

                // ── hourly: starting from now, every other hour
                const hours = []
                if (d.hourly && d.hourly.time) {
                    const now = d.current.time.substring(0, 13)
                    let start = d.hourly.time.indexOf(now + ":00")
                    if (start < 0)
                        start = 0

                    for (let i = start; i < d.hourly.time.length && hours.length < 7; i += 2) {
                        hours.push({
                            hour: d.hourly.time[i].substring(11, 16),
                            temp: Math.round(d.hourly.temperature_2m[i]),
                            code: d.hourly.weather_code[i],
                            rain: d.hourly.precipitation_probability[i],
                            //  the hourly slot has no is_day: derive it
                            isDay: parseInt(d.hourly.time[i].substring(11, 13)) >= 7
                                && parseInt(d.hourly.time[i].substring(11, 13)) < 21
                        })
                    }
                }
                weather.hourly = hours

                // ── daily
                const days = []
                if (d.daily && d.daily.time) {
                    for (let j = 0; j < d.daily.time.length; ++j) {
                        days.push({
                            date: d.daily.time[j],
                            code: d.daily.weather_code[j],
                            max: Math.round(d.daily.temperature_2m_max[j]),
                            min: Math.round(d.daily.temperature_2m_min[j])
                        })
                    }
                }
                weather.daily = days
            }
        }

        onExited: function (code) {
            weather.loading = false
            if (code !== 0 && weather.current === null)
                weather.error = "Could not connect"
        }
    }

    //  Open-Meteo updates every quarter hour; asking more often only
    //  makes traffic, not fresh data.
    Timer {
        interval: 900000
        repeat: true
        running: weather.located
        onTriggered: weather.refresh()
    }
}
