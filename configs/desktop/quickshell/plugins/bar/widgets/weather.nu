#!/usr/bin/env -S nu --no-config-file
# weather data for Weather.qml, one JSON object per run: forecast, radar ({radar, field}) or alerts. each reply
# carries "ok", a failed one "error". location privacy: coordinates only go into the provider requests that need them,
# every reply is checked against LEAK_KEYS before it is cached or printed, times are relative minutes (no timezone hint)

# -----------------------------------------------------------------------------
# CONSTANTS
# -----------------------------------------------------------------------------

const LOCATION_TOGGLE = "scripts/toggles/toggle-weather-location.nu"
# union of everything a provider could hand back that names or narrows the place
const LEAK_KEYS = [
    latitude longitude lat lon coords elevation timezone timezone_abbreviation sunrise sunset daylight_duration
    nearest_area location place area areadesc geocode polygon sendername sender web contact country county state city
    headline description instruction
]

const FORECAST_TIMEOUT = 12sec
const FORECAST_URL = (
    "https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}"
    + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,is_day,precipitation,cloud_cover,"
    + "wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index,surface_pressure"
    + "&hourly=temperature_2m,relative_humidity_2m,precipitation,precipitation_probability,weather_code"
    + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,"
    + "wind_speed_10m_max,uv_index_max"
    + "&timezone=auto&forecast_days=4&forecast_hours=24"
)
# reply key to open-meteo variable, in reply order; a missing value reads as 0
const FORECAST_CURRENT = {
    temp: temperature_2m feelsLike: apparent_temperature humidity: relative_humidity_2m code: weather_code isDay: is_day
    precip: precipitation cloud: cloud_cover wind: wind_speed_10m windDir: wind_direction_10m gust: wind_gusts_10m
    uv: uv_index pressure: surface_pressure
}
const FORECAST_HOURLY = {
    temp: temperature_2m humidity: relative_humidity_2m precip: precipitation pop: precipitation_probability
    code: weather_code
}
const FORECAST_DAILY = {
    code: weather_code hi: temperature_2m_max lo: temperature_2m_min precip: precipitation_sum
    pop: precipitation_probability_max windMax: wind_speed_10m_max uvMax: uv_index_max
}
# windy is not a wmo code, beaufort 6
const WINDY_KMH = 39.0

# z=7 is roughly a 400 km square
const RADAR_ZOOM = 7
const RADAR_SIZE_PX = 512
# universal blue palette, smoothed, snow separate
const RADAR_COLOUR = "4"
const RADAR_OPTIONS = "1_1"
const RADAR_HISTORY_MIN = 240
const RADAR_STEP_MIN = 10
# upstream index advances every ten minutes
const RADAR_MAX_AGE = 540sec
const RADAR_DOWNLOADS_PARALLEL = 6
const RADAR_INDEX_TIMEOUT = 12sec
const RADAR_FRAME_TIMEOUT = 15sec
const PNG_MAGIC = 0x[504E47]
# newest dwd composite lands a few minutes late
const DWD_LATENCY_S = 300
const DWD_LAT_RANGE = [47.0 55.1]
const DWD_LON_RANGE = [5.8 15.1]
const DWD_URL = "https://maps.dwd.de/geoserver/dwd/wms?"
const DWD_LAYER = "dwd:Radar_rv_product_1x1km_ger"
const RAINVIEWER_INDEX_URL = "https://api.rainviewer.com/public/weather-maps.json"
const RAINVIEWER_HOST = "https://tilecache.rainviewer.com"
# web mercator metres per pixel at the equator, zoom 0
const MERCATOR_Z0_M_PER_PX = 156543.03392
const EARTH_RADIUS_M = 6378137.0
# pi / 180
const RADIANS_PER_DEGREE = 0.017453292519943295

const FIELD_GRID = 5
const FIELD_MAX_AGE = 540sec
const FIELD_TIMEOUT = 20sec
const FIELD_URL = "https://api.open-meteo.com/v1/forecast?"
const METRES_PER_DEGREE_LAT = 111320.0
# longitude degrees shrink with latitude, capped near the poles
const FIELD_COS_MIN = 0.15

const PLACE_MAX_AGE = 30day
# widget refreshes on every hover, feeds rate-limit
const FEED_MAX_AGE = 600sec
const PLACE_TIMEOUT = 15sec
const FEED_TIMEOUT = 20sec
# zoom=8 is county level, never street level
const NOMINATIM_URL = (
    "https://nominatim.openstreetmap.org/reverse?format=jsonv2&addressdetails=1&zoom=8&accept-language=en"
    + "&lat={lat}&lon={lon}"
)
# nominatim refuses requests without a user agent
const NOMINATIM_USER_AGENT = "arch-dotfiles-quickshell/1.0 (personal desktop shell)"
const FEED_URL = "https://feeds.meteoalarm.org/api/v1/warnings/feeds-{slug}"
const FEED_SLUGS = {
    at: austria ba: bosnia-herzegovina be: belgium bg: bulgaria ch: switzerland cy: cyprus cz: czechia de: germany
    dk: denmark ee: estonia es: spain fi: finland fr: france gb: united-kingdom gr: greece hr: croatia hu: hungary
    ie: ireland il: israel is: iceland it: italy lt: lithuania lu: luxembourg lv: latvia md: moldova me: montenegro
    mk: north-macedonia mt: malta nl: netherlands no: norway pl: poland pt: portugal ro: romania rs: serbia se: sweden
    si: slovenia sk: slovakia ua: ukraine
}
# generic admin words stripped so area names match by token
const AREA_WORDS_GENERIC = [
    kreis landkreis stadt stadtkreis county city region province provincia departement district council borough
    comune gemeente kommune and of the und de la le les der die das en y
]
const AREA_TOKEN_LENGTH_MIN = 4
# what nfkd plus dropping combining marks did, so "Görlitz" and "Gorlitz" match
const AREA_FOLD_RULES = "::NFKD; ::[:Nonspacing Mark:] Remove;"
const ADDRESS_KEYS = [county state state_district region city municipality town province]
# yellow and up
const ALERT_LEVEL_MIN = 2
const ALERTS_COUNT_MAX = 6
const ALERT_EVENT_LENGTH_MAX = 80
const REASON_LENGTH_MAX = 120

# -----------------------------------------------------------------------------
# INTERNAL
# -----------------------------------------------------------------------------

def failure [error: string]: nothing -> record { {ok: false, error: $error} }

def cache-path [name: string]: nothing -> path {
    $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join quickshell $name
}

# the body like curl -s, error statuses included; null when nothing came back
def http-fetch [url: string, timeout: duration, headers: list = []]: nothing -> any {
    try { http get --raw --allow-errors --max-time $timeout --headers $headers $url } catch { null }
}

def cache-load [path: path, max_age: duration]: nothing -> any {
    if not ($path | path exists) { return null }
    let entry = ls -l $path | first
    if $entry.size > 0b and (date now) - $entry.modified < $max_age {
        try { open --raw $path | from json } catch { null }
    }
}

# atomic rename so concurrent readers never see a partial file
def file-save [path: path, body: any]: nothing -> nothing {
    mkdir ($path | path dirname)
    $body | save -f $"($path).tmp"
    mv -f $"($path).tmp" $path
}

# {source, lat, lon} from the location toggle, the texts go into urls verbatim; null without an answer
def location-resolve []: nothing -> any {
    let repo = ($env.DOTFILES? | default $env.QS_DOTFILES_DIR?
        | default ($nu.home-dir | path join projects arch-dotfiles))
    let words = try {
        ^($repo | path join $LOCATION_TOGGLE) resolve | complete | get stdout | str trim | split row -r '\s+'
    } catch { return null }
    if ($words | length) < 2 or $words.0 == "none" { return null }
    let coords = $words.1 | split row ","
    if ([$coords.0 ($coords | last)] | any {|c| try { $c | into float; false } catch { true } }) { return null }
    {source: $words.0, lat: $coords.0, lon: ($coords | last)}
}

# path of the first LEAK_KEYS key anywhere in node, null when clean
def location-leak-find [node: any, path: string = ""]: nothing -> any {
    match ($node | describe -d | get type) {
        record => {
            $node | transpose key value | each {|kv|
                if ($kv.key | str lowercase) in $LEAK_KEYS { $"($path).($kv.key)" } else {
                    location-leak-find $kv.value $"($path).($kv.key)"
                }
            } | compact | get 0?
        }
        list => {
            $node | enumerate | each {|it| location-leak-find $it.item $"($path)[($it.index)]" } | compact | get 0?
        }
        _ => null
    }
}

def reply-publish [reply: record, cache: path]: nothing -> record {
    let leak = location-leak-find $reply
    if $leak != null { return (failure $"location field leaked: ($leak)") }
    file-save $cache ($reply | to json -r)
    $reply
}

def series-pick [source: record, variables: record, index: int]: nothing -> record {
    $variables | items {|key, variable| {$key: ($source | get -o $variable | get -o $index | default 0)} } | into record
}

# relative so it cannot hint the timezone
def iso-to-minutes [value: any]: nothing -> any {
    try { ($value | into datetime) - (date now) | $in / 1min | math round } catch { null }
}

# web mercator ground resolution times image edge
def radar-span-km [lat: float]: nothing -> int {
    $RADAR_SIZE_PX * $MERCATOR_Z0_M_PER_PX * ($lat | math cos -d) / (2 ** $RADAR_ZOOM) / 1000 | math round
}

# -----------------------------------------------------------------------------
# FORECAST
# -----------------------------------------------------------------------------

def forecast-get []: nothing -> record {
    let location = location-resolve
    if $location == null { return (failure "no location") }
    let raw = http-fetch ({lat: $location.lat, lon: $location.lon} | format pattern $FORECAST_URL) $FORECAST_TIMEOUT
    if ($raw | is-empty) {
        let stale = try { open --raw (cache-path weather.json) | from json } catch { null }
        return (if $stale == null { failure "offline" } else { $stale | upsert stale true })
    }
    let d = try { $raw | from json } catch { return (failure "bad response") }
    if "current" not-in $d or "daily" not-in $d {
        let reason = $d.reason? | default "unexpected response" | into string
        return (failure ($reason | str substring ..<$REASON_LENGTH_MAX))
    }
    let hourly = $d.hourly? | default {}
    # hour only, never the full timestamp
    let hours = $hourly.time? | default [] | enumerate | each {|it|
        {h: ($it.item | str substring 11..12)} | merge (series-pick $hourly $FORECAST_HOURLY $it.index)
    }
    let today = date now | format date "%F"
    let tomorrow = (date now) + 1day | format date "%F"
    let days = $d.daily.time? | default [] | enumerate | each {|it|
        let label = if $it.item == $today { "Today" } else if $it.item == $tomorrow { "Tomorrow" } else {
            # english day names whatever the user's LC_TIME
            with-env {LC_ALL: C} { $it.item | into datetime | format date "%a" }
        }
        let day = {label: $label} | merge (series-pick $d.daily $FORECAST_DAILY $it.index)
        $day | insert windy ($day.windMax >= $WINDY_KMH)
    }
    let current = $FORECAST_CURRENT | items {|key, variable| {$key: ($d.current | get -o $variable | default 0)} }
    | into record
    let units = $d.current_units? | default {}
    reply-publish {
        ok: true
        # how the location was found, not where
        source: $location.source
        stale: false
        # day unless the provider says night
        current: ($current | update isDay ($d.current.is_day? | default 1))
        units: {
            temp: ($units.temperature_2m? | default "°C")
            wind: ($units.wind_speed_10m? | default "km/h")
            precip: ($units.precipitation? | default "mm")
        }
        hourly: $hours
        daily: $days
    } (cache-path weather.json)
}

# -----------------------------------------------------------------------------
# RADAR
# -----------------------------------------------------------------------------

# {unix_s, url, forecast} per frame from the dwd wms
def radar-plan-dwd [lat: float, lon: float]: nothing -> table {
    let x = $lon * $RADIANS_PER_DEGREE * $EARTH_RADIUS_M
    let y = ($lat / 2 + 45 | math tan -d | math ln) * $EARTH_RADIUS_M
    let half = $RADAR_SIZE_PX * $MERCATOR_Z0_M_PER_PX / (2 ** $RADAR_ZOOM) / 2
    let step_s = $RADAR_STEP_MIN * 60
    let latest = ((date now | into int) // 1_000_000_000 - $DWD_LATENCY_S) // $step_s * $step_s
    let bbox = [($x - $half) ($y - $half) ($x + $half) ($y + $half)] | each { into string --decimals 6 } | str join ","
    seq ($latest - $RADAR_HISTORY_MIN * 60) $step_s $latest | each {|unix_s|
        let query = {
            service: WMS version: "1.1.1" request: GetMap layers: $DWD_LAYER styles: "" srs: "EPSG:3857" bbox: $bbox
            width: $RADAR_SIZE_PX height: $RADAR_SIZE_PX format: "image/png" transparent: "true"
            time: ($unix_s * 1_000_000_000 | into datetime | format date "%Y-%m-%dT%H:%M:00.000Z")
        }
        {unix_s: $unix_s, url: ($DWD_URL + ($query | url build-query)), forecast: false}
    }
}

# the plan from the rainviewer index, or an error string
def radar-plan-rainviewer [lat: float, lon: float]: nothing -> any {
    let body = http-fetch $RAINVIEWER_INDEX_URL $RADAR_INDEX_TIMEOUT
    if ($body | is-empty) { return "offline" }
    try {
        let index = $body | from json
        let radar = $index.radar? | default {}
        let host = $index.host? | default $RAINVIEWER_HOST
        let tile = $"/($RADAR_SIZE_PX)/($RADAR_ZOOM)/($lat)/($lon)/($RADAR_COLOUR)/($RADAR_OPTIONS).png"
        let frames = ($radar.past? | default [] | each { {frame: $in, forecast: false} }
            | append ($radar.nowcast? | default [] | each { {frame: $in, forecast: true} }))
        let plan = $frames | last ($RADAR_HISTORY_MIN // $RADAR_STEP_MIN + 1) | each {|f|
            let url = $"($host)($f.frame.path? | default '')($tile)"
            {unix_s: ($f.frame.time? | default 0 | into int), url: $url, forecast: $f.forecast}
        }
        if ($plan | is-empty) { "bad index" } else { $plan }
    } catch { "bad index" }
}

# manifest of local frame paths; each refresh stages its own frame dir and the manifest is the switch
def radar-get []: nothing -> record {
    let manifest = cache-path radar/manifest.json
    let cached = cache-load $manifest $RADAR_MAX_AGE
    if $cached != null { return $cached }
    let location = location-resolve
    if $location == null { return (failure "no location") }
    let lat = $location.lat | into float
    let lon = $location.lon | into float

    # dwd inside germany, rainviewer elsewhere
    let in_dwd = ($lat >= $DWD_LAT_RANGE.0 and $lat <= $DWD_LAT_RANGE.1
        and $lon >= $DWD_LON_RANGE.0 and $lon <= $DWD_LON_RANGE.1)
    let plan = if $in_dwd { radar-plan-dwd $lat $lon } else { radar-plan-rainviewer $lat $lon }
    if ($plan | describe) == string { return (failure $plan) }

    let now_s = (date now | into int) // 1_000_000_000
    let radar_dir = cache-path radar
    let stage = $radar_dir | path join $"f-($now_s)"
    rm -rf $stage
    try { mkdir $stage } catch { return (failure "cache unavailable") }
    let frames = $plan | enumerate | par-each --keep-order --threads $RADAR_DOWNLOADS_PARALLEL {|it|
        let file = $stage | path join $"frame-($it.index | fill -a r -c '0' -w 2).png"
        let body = http-fetch $it.item.url $RADAR_FRAME_TIMEOUT
        # drops truncated bodies and error pages
        if ($body | describe) == binary and ($body | bytes at 0..7 | bytes index-of $PNG_MAGIC) >= 0 {
            file-save $file $body
            {file: $file, minutes: (($it.item.unix_s - $now_s) / 60 | math round), forecast: $it.item.forecast}
        }
    } | compact
    let reply = if ($frames | is-empty) { failure "no frames" } else {
        # licence condition, the attribution must be displayed
        let attribution = if $in_dwd { "Deutscher Wetterdienst" } else { "RainViewer" }
        reply-publish {ok: true, frames: $frames, spanKm: (radar-span-km $lat), attribution: $attribution} $manifest
    }
    # prune only after publishing, a failed run keeps the live generation
    let doomed = if $reply.ok { ls $radar_dir | where name =~ '/f-\d+$' and name != $stage | get name } else {
        [$stage]
    }
    $doomed | each { rm -rf $in }
    $reply
}

# wind and msl pressure on a FIELD_GRID square over the radar square, (u, v) from the top left in 0..1
def field-get []: nothing -> record {
    let cache = cache-path weather-field.json
    let cached = cache-load $cache $FIELD_MAX_AGE
    if $cached != null { return $cached }
    let location = location-resolve
    if $location == null { return (failure "no location") }
    let lat0 = $location.lat | into float
    let lon0 = $location.lon | into float

    let half_m = (radar-span-km $lat0) * 1000 / 2
    let dlat = $half_m / $METRES_PER_DEGREE_LAT
    let dlon = $half_m / ($METRES_PER_DEGREE_LAT * ([$FIELD_COS_MIN ($lat0 | math cos -d)] | math max))
    let steps = 0..<$FIELD_GRID | each { $in / ($FIELD_GRID - 1.0) }
    let points = $steps | each {|v| $steps | each {|u|
        {u: $u, v: $v, lat: ($lat0 + $dlat * (1 - 2 * $v)), lon: ($lon0 + $dlon * (2 * $u - 1))}
    } } | flatten
    let query = {
        latitude: ($points.lat | each { into string --decimals 4 } | str join ",")
        longitude: ($points.lon | each { into string --decimals 4 } | str join ",")
        # msl, surface pressure would contour the terrain
        current: "wind_speed_10m,wind_direction_10m,pressure_msl"
        timezone: auto
    }
    let payload = try { http-fetch ($FIELD_URL + ($query | url build-query)) $FIELD_TIMEOUT | from json } catch { null }
    if $payload == null { return (failure "offline") }
    if ($payload | describe -d | get type) != list or ($payload | length) != ($points | length) {
        return (failure "unexpected response")
    }

    # dir is where the wind comes from
    let cells = $points | zip $payload | each {|pair|
        let current = $pair.1.current? | default {}
        if $current.wind_speed_10m? != null and $current.wind_direction_10m? != null {
            let cell = {
                u: ($pair.0.u | math round -p 4)
                v: ($pair.0.v | math round -p 4)
                wind: ($current.wind_speed_10m | into float | math round -p 1)
                dir: (($current.wind_direction_10m | into float | math round) mod 360)
            }
            if $current.pressure_msl? == null { $cell } else {
                $cell | insert hpa ($current.pressure_msl | into float | math round -p 1)
            }
        }
    } | compact
    if ($cells | is-empty) { return (failure "no data") }

    let units = $payload.0.current_units? | default {}
    let pressures = $cells | get -o hpa | compact
    let out = {
        ok: true
        grid: $FIELD_GRID
        cells: $cells
        windUnits: ($units.wind_speed_10m? | default "km/h")
        pressureUnits: ($units.pressure_msl? | default "hPa")
    }
    let out = if ($pressures | is-empty) { $out } else {
        $out | insert pressureMin ($pressures | math min) | insert pressureMax ($pressures | math max)
    }
    reply-publish $out $cache
}

# -----------------------------------------------------------------------------
# ALERTS
# -----------------------------------------------------------------------------

# folded text -> its tokens, one uconv run for every text of a reply
def area-tokens-map [texts: list<string>]: nothing -> record {
    let texts = $texts | uniq
    let folded = $texts | str replace -ar '[\r\n]' " " | str join "\n" | ^uconv -x $AREA_FOLD_RULES | lines
    $texts | zip $folded | reduce -f {} {|pair, map|
        let tokens = $pair.1 | str lowercase | str replace -ar '[^a-z0-9 ]+' " " | split row " "
            | where { ($in | str length) >= $AREA_TOKEN_LENGTH_MIN and $in not-in $AREA_WORDS_GENERIC } | uniq
        $map | upsert $pair.0 $tokens
    }
}

# cap polygons are "lat,lon lat,lon ...", a closed ring
def polygon-contains [polygon: any, lat: float, lon: float]: nothing -> bool {
    let points = try {
        $polygon | default "" | into string | split row -r '\s+' | compact -e | each {|pair|
            let ab = $pair | split row ","
            if ($ab | length) != 2 { error make {msg: "pair"} }
            {y: ($ab.0 | into float), x: ($ab.1 | into float)}
        }
    } catch { return false }
    if ($points | length) < 4 { return false }
    $points | zip ($points | skip 1 | append $points.0) | reduce -f false {|edge, inside|
        let a = $edge.0
        let b = $edge.1
        let crosses = ($a.y > $lat) != ($b.y > $lat) and $b.y != $a.y
        if $crosses and $lon < $a.x + ($lat - $a.y) * ($b.x - $a.x) / ($b.y - $a.y) { not $inside } else { $inside }
    }
}

# parameter values look like "2; yellow; Moderate"
def alert-awareness [info: record]: nothing -> record {
    $info.parameter? | default [] | reduce -f {level: 0, colour: "", kind: ""} {|parameter, acc|
        let value = $parameter.value? | default "" | into string
        let bits = $value | split row ";" | str trim
        match ($parameter.valueName? | default "" | into string | str lowercase) {
            awareness_level => {
                $acc
                | update level {|it| if $bits.0 =~ '^\d+$' { $bits.0 | into int } else { $it.level } }
                | update colour {|it| if ($bits | length) > 1 { $bits.1 | str lowercase } else { $it.colour } }
            }
            awareness_type => { $acc | update kind (if ($bits | length) > 1 { $bits.1 } else { $value }) }
            _ => $acc
        }
    }
}

# english when the feed has it
def alert-info-pick [alert: record]: nothing -> any {
    let infos = $alert.info? | default []
    let english = $infos | where {|info|
        [$info.language?] | flatten | any { default "" | into string | str lowercase | str starts-with en }
    }
    $english | append $infos | get 0?
}

def alerts-get []: nothing -> record {
    let cache = cache-path weather-alerts.json
    let cached = cache-load $cache $FEED_MAX_AGE
    if $cached != null { return $cached }
    let location = location-resolve
    if $location == null { return (failure "no location") }
    let lat = $location.lat | into float
    let lon = $location.lon | into float

    let place_cache = cache-path weather-place.json
    if (cache-load $place_cache $PLACE_MAX_AGE) == null {
        let url = {lat: $location.lat, lon: $location.lon} | format pattern $NOMINATIM_URL
        let body = http-fetch $url $PLACE_TIMEOUT [User-Agent $NOMINATIM_USER_AGENT]
        if not ($body | is-empty) { file-save $place_cache $body }
    }
    let place = try { open --raw $place_cache | from json } catch { null }
    let address = if ($place | describe -d | get type) == record { $place.address? | default {} } else { {} }
    if ($address.country_code? | is-empty) { return (failure "no region") }
    let slug = $FEED_SLUGS | get -o $address.country_code
    if $slug == null { return {ok: true, supported: false, alerts: [], countryOthers: 0} }

    let feed_cache = cache-path weather-alerts-feed.json
    if (cache-load $feed_cache $FEED_MAX_AGE) == null {
        let body = http-fetch ({slug: $slug} | format pattern $FEED_URL) $FEED_TIMEOUT
        if not ($body | is-empty) { file-save $feed_cache $body }
    }
    let feed = try { open --raw $feed_cache | from json } catch { null }
    if ($feed | describe -d | get type) != record { return (failure "offline") }

    let infos = $feed.warnings? | default [] | each { alert-info-pick ($in.alert? | default {}) } | compact
    let address_texts = $ADDRESS_KEYS | each {|key| $address | get -o $key | default "" | into string }
    let area_texts = $infos | each { $in.area? | default [] | each { $in.areaDesc? | default "" | into string } }
    | flatten
    let tokens = area-tokens-map ($address_texts | append $area_texts)
    let mine = $address_texts | each {|text| $tokens | get $text } | flatten | uniq

    let candidates = $infos | each {|info|
        # here is a polygon hit, region only a name match
        let scope = $info.area? | default [] | reduce -f "" {|area, scope|
            let polygons = [$area.polygon?] | flatten | compact -e
            let names = $tokens | get ($area.areaDesc? | default "" | into string)
            if $scope == "here" or ($polygons | any { polygon-contains $in $lat $lon }) { "here" } else if (
                $mine | is-not-empty) and ($names | any { $in in $mine }) { "region" } else { $scope }
        }
        let ends_in = iso-to-minutes $info.expires?
        let awareness = alert-awareness $info
        # filtered before others is counted
        if ($ends_in == null or $ends_in >= 0) and $awareness.level >= $ALERT_LEVEL_MIN {
            {info: $info, scope: $scope, ends_in: $ends_in} | merge $awareness
        }
    } | compact
    let alerts = $candidates | where scope != ""
    | insert key {|c| [($c.info.event? | default "" | into string) $c.level $c.scope] } | uniq-by key | each {|c|
        # no free text, event is a short controlled phrase
        {
            event: ([$c.info.event? $c.kind "Weather warning"] | compact -e | first | into string
                | str substring ..<$ALERT_EVENT_LENGTH_MAX)
            severity: ($c.info.severity? | default "" | into string)
            urgency: ($c.info.urgency? | default "" | into string)
            certainty: ($c.info.certainty? | default "" | into string)
            level: $c.level
            colour: $c.colour
            kind: $c.kind
            scope: $c.scope
            startsIn: (iso-to-minutes ([$c.info.onset? $c.info.effective?] | compact -e | get 0?))
            endsIn: $c.ends_in
        }
    } | sort-by -c {|a, b|
        if $a.level != $b.level { $a.level > $b.level } else { $a.scope == "here" and $b.scope != "here" }
    }
    reply-publish {
        ok: true
        supported: true
        alerts: ($alerts | first $ALERTS_COUNT_MAX)
        countryOthers: ($candidates | where scope == "" | length)
    } $cache
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------

def main [command?: string] {
    let reply = match $command {
        forecast => (forecast-get)
        radar => { {radar: (radar-get), field: (field-get)} }
        alerts => { alerts-get | default [] alerts }
        _ => {
            print -e "usage: weather.nu forecast|radar|alerts"
            exit 2
        }
    }
    print ($reply | to json -r)
}
