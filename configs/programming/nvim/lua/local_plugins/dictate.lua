-- Dictation: <M-v> turns continuous dictation on or off. While on, the default microphone streams into an energy
-- detector that cuts the speech at its pauses; each piece goes to a whisper-server kept loaded for the session and
-- its text lands at the cursor. Each new piece is transcribed again together with the one before, and the earlier
-- wording is corrected in place when the fuller context changes it; a piece that leaves that window is final.
-- <M-V> does the same and has the local ollama rewrite each final piece into the buffer's language ("x squared over
-- two" in a tex buffer becomes \frac{x^2}{2}); without ollama the transcript stays.
local M = {}

-- programming/nvim's mod.nu fetches this file to the same path
local MODEL_FILE = "ggml-large-v3-turbo-q5_0.bin"
local LANGUAGE = "en"
local OLLAMA_URL = "http://127.0.0.1:11434"
-- llm/ollama's 8b, LONG_CONTEXT in ollama-ensure-models.nu: at a 4k context it takes 5 GB of vram and answers in
-- under a second, where the 30b moe took 15 GB; greedy decoding keeps the same speech giving the same latex
local OLLAMA_MODEL = "qwen3-abliterated-64k"
local OLLAMA_OPTIONS = { num_ctx = 4096, temperature = 0 }
local OLLAMA_PROBE_TIMEOUT_S = "1"
local OLLAMA_TIMEOUT_S = "120"
-- it leaves the vram soon after the last dictation instead of ollama's 30 min
local OLLAMA_KEEP_ALIVE = "2m"
local CONTEXT_LINES = 30
local SAMPLE_RATE = 16000
local SIGTERM = 15
-- 30 ms frames of s16 mono
local FRAME_SAMPLES = 480
local FRAME_BYTES = FRAME_SAMPLES * 2
-- the first half second sets the noise floor; speech is a frame NOISE_FACTOR times louder, and at least MIN_LEVEL
local CALIBRATION_FRAMES = 17
local NOISE_FACTOR = 3
local MIN_LEVEL = 400
local PREROLL_FRAMES = 10
-- a piece ends after 0.7 s of quiet, is dropped under 0.3 s of speech and cut at 20 s
local END_SILENCE_FRAMES = 24
local MIN_SPEECH_FRAMES = 10
local MAX_PIECE_FRAMES = 667
-- the pieces still open to correction: the newest and the one before it
local WINDOW = 2
-- the longest a stop waits for the last pieces before it drops them
local STOP_TIMEOUT_MS = 30000
-- in rewrite mode, a pause this long with nothing queued finalizes the open pieces, so the last one is rewritten
-- without waiting for more speech
local REWRITE_IDLE_MS = 1500
local PROMPT_TAIL_CHARS = 400
local SERVER_POLL_MS = 250
local SERVER_START_TIMEOUT_MS = 60000
local REQUEST_TIMEOUT_S = "60"
local SERVER_PROBE_TIMEOUT_S = "1"
-- whisper's initial prompt biases it toward the words a coder says
local WHISPER_PROMPT = "LaTeX, Neovim, Lua, Rust, Python, Nushell, function, variable, integral, theorem, lemma, "
    .. "omega, epsilon, delta, dx wedge dy, d omega, partial, manifold, tensor, sum, product."

local NS = vim.api.nvim_create_namespace("dictate")
local session = nil

local function model_path()
    local data = vim.env.XDG_DATA_HOME or (vim.env.HOME .. "/.local/share")
    return data .. "/whisper-cpp/" .. MODEL_FILE
end

local function notify(msg, level)
    vim.notify("Dictate: " .. msg, level or vim.log.levels.INFO)
end

-- The text whisper printed, one segment per line, as one line of prose.
local function transcript(stdout)
    local parts = {}
    for line in stdout:gmatch("[^\n]+") do
        local t = vim.trim(line)
        if t ~= "" and not t:match("^%[BLANK_AUDIO%]$") then
            table.insert(parts, t)
        end
    end
    return table.concat(parts, " ")
end

-- The text around the cursor, the current line split at it.
local function context(buf, row, col)
    local first = math.max(0, row - CONTEXT_LINES)
    local before = vim.api.nvim_buf_get_lines(buf, first, row + 1, false)
    local line = before[#before] or ""
    before[#before] = line:sub(1, col)
    local after = { line:sub(col + 1) }
    vim.list_extend(after, vim.api.nvim_buf_get_lines(buf, row + 1, row + 1 + CONTEXT_LINES, false))
    return table.concat(before, "\n"), table.concat(after, "\n")
end

-- One prompt per kind of buffer: an 8b without reasoning copies whatever examples it is shown, so tex sees only tex
local TEX_RULES = {
    "Rules: write LaTeX, not words. Never repeat text that is already before or after the cursor, such as an",
    "environment's \\begin or \\end. Inside display math (\\[ \\], equation, align) output bare math with no $ at all;",
    "words inside it go in \\text{}. In align, 'new line' is \\\\ and each line aligns at &=. In prose, put math in",
    "$...$ without inner spaces. Keep every part of the speech and every symbol in it. Spoken structure becomes",
    "LaTeX commands: 'begin definition' is \\begin{definition}, 'end proof' is \\end{proof}, 'section foo' is",
    "\\section{Foo}, 'new paragraph' is a blank line. Open an environment only when the speech says 'begin', and",
    "keep every word of prose the speech has, such as a leading 'Let'.",
    "",
    "Examples:",
    "cursor inside \\[ \\]: 'x squared plus one over two' -> \\frac{x^2 + 1}{2}",
    "cursor inside \\[ \\]: 'the sum from k equals one to n of k equals n times n plus one over two'"
        .. " -> \\sum_{k=1}^{n} k = \\frac{n(n+1)}{2}",
    "cursor inside \\[ \\]: 'b equals the matrix one two three four' -> B = \\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix}",
    "cursor inside align: 'g of x equals x times x plus one, new line, equals x squared plus x'"
        .. " -> g(x) &= x(x + 1) \\\\ &= x^2 + x",
    "cursor inside a lemma: 'let n be a natural number' -> Let $n$ be a natural number.",
    "cursor in prose: 'for all epsilon greater than zero there is a delta' -> for all $\\varepsilon > 0$ there is a $\\delta$",
    "cursor in prose: 'f of x equals x squared' -> $f(x) = x^2$.",
    "cursor in prose: 'begin definition a group is a set g with an operation end definition'"
        .. " -> \\begin{definition}\nA group is a set $G$ with an operation.\n\\end{definition}",
    "cursor in prose: 'so the integral of g from a to b is zero' -> so $\\int_a^b g = 0$.",
}
local CODE_RULES = {
    "Rules: write code that completes the surrounding code, in its style and indentation. Never repeat text that is",
    "already before or after the cursor. Keep every part of the speech.",
    "",
    "Example, python inside a function: 'return the sum of x over all x in items' -> return sum(x for x in items)",
}

local DISPLAY_ENVS = { "equation", "align", "gather", "multline", "eqnarray", "displaymath" }

-- The last occurrence of a control sequence, skipping escaped ones: the \[ in a line break \\[2pt] is no opener.
local function last_at(text, plain)
    local at, from = nil, 1
    while true do
        local i = text:find(plain, from, true)
        if not i then
            return at
        end
        local slashes = #text:sub(1, i - 1):match("\\*$")
        if slashes % 2 == 0 then
            at = i
        end
        from = i + 1
    end
end

-- Whether the cursor sits in display math: an \[ or a math environment opened before it and not closed since.
local function in_display_math(before)
    local open, close = last_at(before, "\\["), last_at(before, "\\]")
    if open and (not close or close < open) then
        return true
    end
    for _, env in ipairs(DISPLAY_ENVS) do
        for _, name in ipairs({ env, env .. "*" }) do
            local b, e = last_at(before, "\\begin{" .. name .. "}"), last_at(before, "\\end{" .. name .. "}")
            if b and (not e or e < b) then
                return true
            end
        end
    end
    return false
end

-- The small model sometimes wraps display math in $ $ or \[ \] once more; the cursor already sits inside one.
local function unwrap_display(text)
    local t = vim.trim(text)
    t = t:match("^\\%[%s*(.-)%s*\\%]$") or t
    t = t:match("^%$%$%s*(.-)%s*%$%$$") or t
    local inner = t:match("^%$%s*(.-)%s*%$$")
    if inner and not inner:find("$", 1, true) then
        t = inner
    end
    return t
end

-- Buffers whose speech becomes LaTeX: tex, and those that take $...$ math or have no type yet (a scratch buffer)
local LATEX_FILETYPES = { tex = true, plaintex = true, [""] = true, text = true, markdown = true }

local function rewrite_prompt(ft, before, after, speech)
    local kind = LATEX_FILETYPES[ft] and "LaTeX" or ft
    local lines = { "Turn dictated speech into the exact text to insert at <<CURSOR>> in a " .. kind .. " buffer." }
    if kind == "LaTeX" then
        table.insert(
            lines,
            in_display_math(before) and "The cursor is inside display math." or "The cursor is in prose."
        )
    end
    vim.list_extend(lines, kind == "LaTeX" and TEX_RULES or CODE_RULES)
    vim.list_extend(lines, {
        "Output only the text: no fences, no explanation.",
        "",
        "Text before the cursor:",
        before,
        "<<CURSOR>>",
        "Text after the cursor:",
        after,
        "",
        "Dictated speech:",
        speech,
    })
    return table.concat(lines, "\n")
end

-- The environment the cursor sits in: the last \begin before it with no \end after that, or nil.
local function open_env(before)
    local env, at = nil, 0
    for pos, name in before:gmatch("()\\begin{([^}]+)}") do
        env, at = name, pos
    end
    if env and not before:find("\\end{" .. env .. "}", at, true) then
        return env
    end
    return nil
end

-- The model wraps its text in the environment the cursor already sits in; the buffer has that pair.
local function strip_env(text, before)
    local env = open_env(before)
    if not env then
        return text
    end
    local t = vim.trim(text)
    local b, e = "\\begin{" .. env .. "}", "\\end{" .. env .. "}"
    if t:sub(1, #b) == b and t:sub(-#e) == e then
        return vim.trim(t:sub(#b + 1, #t - #e))
    end
    return text
end

local GREEK = vim.split(
    "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi pi rho sigma tau upsilon phi chi psi omega",
    " "
)

-- Whisper capitalizes a sentence's first word, which the rewrite reads as \Omega; a Greek letter stays lowercase
-- unless "capital" comes right before it.
local function greek_lower(speech)
    local out = speech
    for _, name in ipairs(GREEK) do
        local cap = name:sub(1, 1):upper() .. name:sub(2)
        out = out:gsub("()%f[%a]" .. cap .. "%f[%A]", function(pos)
            local prev = out:sub(1, pos - 1):match("(%a+)%W*$")
            return (prev and prev:lower() == "capital") and cap or name
        end)
    end
    return out
end

-- The rewrite, or nil when ollama is not there; ollama answers on its socket, which starts it on demand.
local function rewrite(ft, before, after, speech, done)
    local body = vim.json.encode({
        model = OLLAMA_MODEL,
        stream = false,
        think = false,
        keep_alive = OLLAMA_KEEP_ALIVE,
        options = OLLAMA_OPTIONS,
        messages = { { role = "user", content = rewrite_prompt(ft, before, after, greek_lower(speech)) } },
    })
    vim.system({ "curl", "-sf", "-m", OLLAMA_PROBE_TIMEOUT_S, OLLAMA_URL .. "/api/version" }, {}, function(probe)
        if probe.code ~= 0 then
            done(nil)
            return
        end
        vim.system(
            { "curl", "-sf", "-m", OLLAMA_TIMEOUT_S, OLLAMA_URL .. "/api/chat", "-d", "@-" },
            { stdin = body, text = true },
            function(r)
                local ok, reply = pcall(vim.json.decode, r.stdout or "")
                local content = ok and reply.message and reply.message.content or nil
                if content and LATEX_FILETYPES[ft] then
                    content = strip_env(content, before)
                    if in_display_math(before) then
                        content = unwrap_display(content)
                    end
                end
                done(content and vim.trim(content) ~= "" and content or nil)
            end
        )
    end)
end

-- Root mean square of a frame of s16le samples.
local function frame_level(frame)
    local sum = 0
    for i = 1, #frame - 1, 2 do
        local lo, hi = frame:byte(i, i + 1)
        local v = hi * 256 + lo
        if v >= 32768 then
            v = v - 65536
        end
        sum = sum + v * v
    end
    return math.sqrt(sum / (#frame / 2))
end

-- An energy detector fed raw audio; on_piece gets each piece of speech, from its pre-roll to its trailing pause.
local function new_vad(on_piece)
    local vad = { pending = "", calibration = {}, level = nil, preroll = {}, speech = nil, voiced = 0, silent = 0 }

    local function emit()
        if vad.speech and vad.voiced >= MIN_SPEECH_FRAMES then
            on_piece(table.concat(vad.speech))
        end
        vad.speech, vad.voiced, vad.silent = nil, 0, 0
    end

    local function preroll_push(frame)
        table.insert(vad.preroll, frame)
        if #vad.preroll > PREROLL_FRAMES then
            table.remove(vad.preroll, 1)
        end
    end

    local function frame_in(frame)
        local level = frame_level(frame)
        if not vad.level then
            table.insert(vad.calibration, level)
            preroll_push(frame)
            if #vad.calibration >= CALIBRATION_FRAMES then
                local sum = 0
                for _, l in ipairs(vad.calibration) do
                    sum = sum + l
                end
                vad.level = math.max(MIN_LEVEL, sum / #vad.calibration * NOISE_FACTOR)
            end
            return
        end
        local loud = level > vad.level
        if not vad.speech then
            preroll_push(frame)
            if loud then
                vad.speech, vad.preroll, vad.voiced, vad.silent = vad.preroll, {}, 1, 0
            end
            return
        end
        table.insert(vad.speech, frame)
        if loud then
            vad.voiced, vad.silent = vad.voiced + 1, 0
        else
            vad.silent = vad.silent + 1
        end
        if vad.silent >= END_SILENCE_FRAMES or #vad.speech >= MAX_PIECE_FRAMES then
            emit()
        end
    end

    function vad.feed(data)
        vad.pending = vad.pending .. data
        local at = 1
        while #vad.pending - at + 1 >= FRAME_BYTES do
            frame_in(vad.pending:sub(at, at + FRAME_BYTES - 1))
            at = at + FRAME_BYTES
        end
        vad.pending = vad.pending:sub(at)
    end

    function vad.flush()
        emit()
    end

    return vad
end

-- A 16 kHz mono s16 WAV file around raw samples.
local function wav_bytes(pcm)
    local function u32(x)
        return string.char(
            x % 256,
            math.floor(x / 256) % 256,
            math.floor(x / 65536) % 256,
            math.floor(x / 16777216) % 256
        )
    end
    local function u16(x)
        return string.char(x % 256, math.floor(x / 256) % 256)
    end
    local n = #pcm
    return "RIFF"
        .. u32(36 + n)
        .. "WAVEfmt "
        .. u32(16)
        .. u16(1)
        .. u16(1)
        .. u32(SAMPLE_RATE)
        .. u32(SAMPLE_RATE * 2)
        .. u16(2)
        .. u16(16)
        .. "data"
        .. u32(n)
        .. pcm
end

local function words(text)
    return vim.split(vim.trim(text), "%s+", { trimempty = true })
end

local function word_key(w)
    return ((w or ""):lower():gsub("%p", ""))
end

-- The window's new text, split where the older piece ends: near its old word count, preferring the cut after the
-- word the older piece ended on and after a sentence end. Whisper gives no timestamps per piece here.
local function split_words(text, old)
    local all, prior = words(text), words(old)
    local n = #prior
    local best, best_score = math.min(n, #all), -math.huge
    for k = math.max(0, n - 2), math.min(#all, n + 2) do
        local score = -math.abs(k - n) * 0.5
        if k > 0 and word_key(all[k]) == word_key(prior[n]) then
            score = score + 2
        end
        if k > 0 and all[k]:match("[.!?]$") then
            score = score + 1
        end
        if score > best_score then
            best, best_score = k, score
        end
    end
    return table.concat(vim.list_slice(all, 1, best), " "), table.concat(vim.list_slice(all, best + 1), " ")
end

local function free_port()
    local tcp = vim.uv.new_tcp()
    tcp:bind("127.0.0.1", 0)
    local port = tcp:getsockname().port
    tcp:close()
    return port
end

local function mark_range(s, id)
    local m = vim.api.nvim_buf_get_extmark_by_id(s.buf, NS, id, { details = true })
    return m[1], m[2], m[3].end_row, m[3].end_col
end

local function cursor_at(s, row, col)
    if not vim.api.nvim_win_is_valid(s.win) or vim.api.nvim_win_get_buf(s.win) ~= s.buf then
        return false
    end
    local cursor = vim.api.nvim_win_get_cursor(s.win)
    return cursor[1] - 1 == row and cursor[2] >= col - 1
end

-- Puts text over a piece's range and stretches its extmark over the new text; the cursor follows a tail it sat at.
local function set_piece(s, piece, text)
    local row, col, end_row, end_col = mark_range(s, piece.id)
    local tail = vim.api.nvim_buf_get_extmark_by_id(s.buf, NS, s.tail, {})
    local follow = cursor_at(s, tail[1], tail[2])
    local lines = vim.split(text, "\n", { plain = true })
    vim.api.nvim_buf_set_text(s.buf, row, col, end_row, end_col, lines)
    local last_row = row + #lines - 1
    local last_col = (#lines == 1 and col or 0) + #lines[#lines]
    vim.api.nvim_buf_set_extmark(s.buf, NS, row, col, {
        id = piece.id,
        end_row = last_row,
        end_col = last_col,
        right_gravity = false,
        end_right_gravity = false,
    })
    piece.text = text
    if follow then
        tail = vim.api.nvim_buf_get_extmark_by_id(s.buf, NS, s.tail, {})
        vim.api.nvim_win_set_cursor(s.win, { tail[1] + 1, tail[2] })
    end
end

-- A new piece at the tail, a space apart from the text before it.
local function append_piece(s, text, pcm)
    local tail = vim.api.nvim_buf_get_extmark_by_id(s.buf, NS, s.tail, {})
    local row, col = tail[1], tail[2]
    local before = (vim.api.nvim_buf_get_lines(s.buf, row, row + 1, false)[1] or ""):sub(1, col)
    local prefix = (col > 0 and not before:match("%s$")) and " " or ""
    local follow = cursor_at(s, row, col)
    vim.api.nvim_buf_set_text(s.buf, row, col, row, col, { prefix })
    local start = col + #prefix
    local id = vim.api.nvim_buf_set_extmark(s.buf, NS, row, start, {
        end_row = row,
        end_col = start,
        right_gravity = false,
        end_right_gravity = false,
    })
    local piece = { id = id, pcm = pcm, text = "" }
    set_piece(s, piece, text)
    if follow then
        tail = vim.api.nvim_buf_get_extmark_by_id(s.buf, NS, s.tail, {})
        vim.api.nvim_win_set_cursor(s.win, { tail[1] + 1, tail[2] })
    end
    return piece
end

-- A piece leaves the window: its words become context for the next requests. In rewrite mode it is held: a formula
-- spoken with a pause in it spans pieces, so the rewrite takes everything held at once (flush_rewrite).
local function finalize(s, piece)
    s.final_tail = (s.final_tail .. " " .. piece.text):sub(-PROMPT_TAIL_CHARS)
    if not s.rewrite or piece.text == "" then
        -- the buffer may have been wiped while dictating
        if vim.api.nvim_buf_is_valid(s.buf) then
            vim.api.nvim_buf_del_extmark(s.buf, NS, piece.id)
        end
        return
    end
    table.insert(s.held, piece)
end

-- Rewrites the held pieces as one span, from the first one's start to the last one's end.
local function flush_rewrite(s)
    local pieces = s.held
    s.held = {}
    if #pieces == 0 or not vim.api.nvim_buf_is_valid(s.buf) then
        return
    end
    local row, col = mark_range(s, pieces[1].id)
    local _, _, end_row, end_col = mark_range(s, pieces[#pieces].id)
    local texts = {}
    for _, piece in ipairs(pieces) do
        table.insert(texts, piece.text)
        vim.api.nvim_buf_del_extmark(s.buf, NS, piece.id)
    end
    local span = {
        id = vim.api.nvim_buf_set_extmark(s.buf, NS, row, col, {
            end_row = end_row,
            end_col = end_col,
            right_gravity = false,
            end_right_gravity = true,
        }),
    }
    local before = context(s.buf, row, col)
    local _, after = context(s.buf, end_row, end_col)
    rewrite(s.ft, before, after, table.concat(texts, " "), function(text)
        vim.schedule(function()
            if text and vim.api.nvim_buf_is_valid(s.buf) then
                set_piece(s, span, text)
            end
            if vim.api.nvim_buf_is_valid(s.buf) then
                vim.api.nvim_buf_del_extmark(s.buf, NS, span.id)
            end
        end)
    end)
end

local function finalize_open(s)
    for _, piece in ipairs(s.open) do
        finalize(s, piece)
    end
    s.open = {}
    flush_rewrite(s)
end

local process_next

-- The window re-transcribed with the new piece: the older piece is corrected in place, the new one appended.
local function transcribe_piece(s, pcm, done)
    while #s.open > WINDOW - 1 do
        finalize(s, table.remove(s.open, 1))
    end
    local prev = s.open[#s.open]
    local wav = vim.fn.tempname() .. ".wav"
    local file = io.open(wav, "wb")
    file:write(wav_bytes((prev and prev.pcm or "") .. pcm))
    file:close()
    vim.system({
        "curl",
        "-sf",
        "-m",
        REQUEST_TIMEOUT_S,
        "-F",
        "file=@" .. wav,
        "-F",
        "response_format=text",
        "-F",
        "prompt=" .. vim.trim(WHISPER_PROMPT .. " " .. s.final_tail),
        ("http://127.0.0.1:%d/inference"):format(s.port),
    }, { text = true }, function(r)
        os.remove(wav)
        vim.schedule(function()
            if not s.finished and r.code ~= 0 then
                notify("whisper-server request failed (" .. r.code .. ")", vim.log.levels.ERROR)
            end
            if s.finished or r.code ~= 0 or not vim.api.nvim_buf_is_valid(s.buf) then
                done()
                return
            end
            local text = transcript(r.stdout or "")
            local fresh = text
            if prev then
                local older
                older, fresh = split_words(text, prev.text)
                -- an empty window (silence, noise) is no correction: it would erase words already dictated
                if older ~= "" and older ~= prev.text then
                    set_piece(s, prev, older)
                end
            end
            if fresh ~= "" then
                table.insert(s.open, append_piece(s, fresh, pcm))
            end
            done()
        end)
    end)
end

-- Rewrite mode: once speech pauses, the pieces still in the window are final.
local function arm_idle(s)
    s.idle_gen = (s.idle_gen or 0) + 1
    local gen = s.idle_gen
    vim.defer_fn(function()
        if session ~= s or s.idle_gen ~= gen or s.busy or #s.queue > 0 or (s.vad and s.vad.speech) then
            return
        end
        finalize_open(s)
    end, REWRITE_IDLE_MS)
end

local function stop_server(s)
    if s.server and not s.server_exited then
        s.server:kill(SIGTERM)
    end
end

local function finish_stop(s)
    if s.finished then
        return
    end
    s.finished = true
    finalize_open(s)
    stop_server(s)
    if vim.api.nvim_buf_is_valid(s.buf) then
        vim.api.nvim_buf_del_extmark(s.buf, NS, s.tail)
    end
    if session == s then
        session = nil
    end
    notify("off")
end

process_next = function(s)
    -- no server to finish with (it died or never came up): what is queued is lost, the session still ends
    if s.stopping and (s.server_exited or not s.ready) and not s.busy then
        s.queue = {}
        finish_stop(s)
        return
    end
    if s.busy or not s.ready then
        return
    end
    local pcm = table.remove(s.queue, 1)
    if not pcm then
        if s.stopping then
            finish_stop(s)
        end
        return
    end
    s.busy = true
    transcribe_piece(s, pcm, function()
        s.busy = false
        if s.rewrite and not s.stopping then
            arm_idle(s)
        end
        process_next(s)
    end)
end

local function wait_ready(s, started)
    local url = ("http://127.0.0.1:%d/"):format(s.port)
    vim.system({ "curl", "-sf", "-o", "/dev/null", "-m", SERVER_PROBE_TIMEOUT_S, url }, {}, function(r)
        vim.schedule(function()
            if s.server_exited then
                return
            end
            if r.code == 0 then
                s.ready = true
                process_next(s)
            elseif vim.uv.now() - started > SERVER_START_TIMEOUT_MS then
                notify("whisper-server did not come up", vim.log.levels.ERROR)
                s.queue = {}
                s.ready = true
                M.disable()
            else
                vim.defer_fn(function()
                    wait_ready(s, started)
                end, SERVER_POLL_MS)
            end
        end)
    end)
end

-- Starts continuous dictation at the cursor; rewrite_speech rewrites each final piece for the buffer.
function M.enable(rewrite_speech)
    if session then
        return
    end
    if vim.fn.filereadable(model_path()) == 0 then
        notify("no model at " .. model_path() .. " (dot apply programming/nvim fetches it)", vim.log.levels.ERROR)
        return
    end
    for _, exe in ipairs({ "whisper-server", "pw-record", "curl" }) do
        if vim.fn.executable(exe) == 0 then
            notify(exe .. " is not installed (dot apply --packages)", vim.log.levels.ERROR)
            return
        end
    end
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local row = cursor[1] - 1
    -- in insert mode the cursor sits before the column; in normal mode text goes after the character under it
    local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    local col = cursor[2]
    if vim.fn.mode():sub(1, 1) ~= "i" and col < #line then
        -- past the whole character: one byte on would split a multibyte one
        col = col + 1 + vim.str_utf_end(line, col + 1)
    end
    local s = {
        buf = buf,
        win = win,
        ft = vim.bo[buf].filetype,
        rewrite = rewrite_speech,
        tail = vim.api.nvim_buf_set_extmark(buf, NS, row, col, { right_gravity = true }),
        port = free_port(),
        queue = {},
        open = {},
        held = {},
        final_tail = "",
    }
    session = s
    s.server = vim.system({
        "whisper-server",
        "-m",
        model_path(),
        "--host",
        "127.0.0.1",
        "--port",
        tostring(s.port),
        "-l",
        LANGUAGE,
        "-nt",
        "--prompt",
        WHISPER_PROMPT,
    }, {}, function(r)
        s.server_exited = true
        vim.schedule(function()
            if session == s and not s.stopping then
                notify("whisper-server exited (" .. r.code .. ")", vim.log.levels.ERROR)
                s.queue = {}
                M.disable()
            end
        end)
    end)
    wait_ready(s, vim.uv.now())
    local vad = new_vad(function(pcm)
        vim.schedule(function()
            table.insert(s.queue, pcm)
            process_next(s)
        end)
    end)
    s.vad = vad
    s.recorder = vim.system({
        "pw-record",
        "-a",
        "--rate",
        tostring(SAMPLE_RATE),
        "--channels",
        "1",
        "--format",
        "s16",
        "-",
    }, {
        stdout = function(_, data)
            if data then
                vad.feed(data)
            end
        end,
    }, function(r)
        vim.schedule(function()
            if session == s and not s.stopping then
                notify("pw-record exited (" .. r.code .. ")", vim.log.levels.ERROR)
                M.disable()
            end
        end)
    end)
    notify(rewrite_speech and "on, rewriting each piece; <M-V> turns it off" or "on; <M-v> turns it off")
end

-- Stops listening; the pieces still queued are transcribed and finalized, then the server exits.
function M.disable()
    local s = session
    if not s or s.stopping then
        return
    end
    s.stopping = true
    s.recorder:kill(SIGTERM)
    s.vad.flush()
    notify("finishing")
    vim.schedule(function()
        process_next(s)
    end)
    -- a request that never answers must not keep the session alive
    vim.defer_fn(function()
        if session == s then
            M.abort()
        end
    end, STOP_TIMEOUT_MS)
end

-- Ends the session now, the queue and any open request dropped; the pieces already in the buffer stay.
function M.abort()
    local s = session
    if not s then
        return
    end
    s.stopping = true
    s.queue = {}
    s.busy = false
    s.recorder:kill(SIGTERM)
    finish_stop(s)
end

function M.toggle(rewrite_speech)
    if session and session.stopping then
        notify("stopped without the last pieces", vim.log.levels.WARN)
        M.abort()
    elseif session then
        M.disable()
    else
        M.enable(rewrite_speech)
    end
end

function M.setup()
    vim.keymap.set({ "n", "i" }, "<M-v>", function()
        M.toggle(false)
    end, { desc = "Dictate: continuous dictation on/off" })
    vim.keymap.set({ "n", "i" }, "<M-V>", function()
        M.toggle(true)
    end, { desc = "Dictate: continuous dictation on/off, rewriting into the buffer's language" })
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = vim.api.nvim_create_augroup("dictate", { clear = true }),
        callback = function()
            if session then
                session.recorder:kill(SIGTERM)
                stop_server(session)
            end
        end,
    })
end

return M
