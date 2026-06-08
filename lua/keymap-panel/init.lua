-- 右サイドに常駐するキーマップ一覧パネル
--   - cheatsheet.md の基礎キー（静的） + 自作 keymap（動的検出）を表示する
--   - :KeymapPanel [open|close|toggle|refresh]
local cheatsheet = require "keymap-panel.cheatsheet"
local detector = require "keymap-panel.detector"

local M = {}

M.config = {
  width = 34,
  key_width = 12,
  auto_open = true, -- 起動時に自動で開く
  -- 基礎キーの静的データ（symlink 経由で ~/dotfiles/nvim/cheatsheet.md）
  cheatsheet = vim.fn.stdpath "config" .. "/cheatsheet.md",
  -- 自作 keymap のスキャン対象（stdpath("config") からの相対パス）
  scan = { "init.lua", "lua/config", "lua/plugins", "lua/polish.lua" },
  -- 動的検出の対象モード
  modes = { "n", "v", "i", "t" },
  custom_section = "自作キーマップ (動的)",
}

-- バッファは全タブで共有し、ウィンドウはタブごとに持つ（タブ=作業スペース運用）
local state = { buf = nil }

-- カレントタブ (または指定タブ) のパネルウィンドウを返す。
-- パネルのウィンドウにファイルが開かれた直後 (filetype が変わる) でも追跡できるよう、
-- filetype ではなくウィンドウローカル変数でマークして判定する
local function panel_win(tab)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab or 0)) do
    if vim.w[w].keymap_panel then return w end
  end
end
local ns = vim.api.nvim_create_namespace "keymap_panel"

-- 表示幅節約のための短縮表記
local function shorten(key) return (key:gsub("<Space>", "<Sp>"):gsub("<[Ll]eader>", "<Sp>")) end

-- cheatsheet と動的検出の重複排除用の正規化
-- 表記ゆれ (<Space>tt / <Sp>tt, <Ctrl>r / <C-R> 等) をベストエフォートで吸収する
local function norm(key)
  key = key:lower()
  key = key:gsub("<space>", "␣"):gsub("<leader>", "␣"):gsub("<sp>", "␣")
  key = key:gsub("<ctrl>", "<c-"):gsub("<shift>", "<s-"):gsub("<meta>", "<m-")
  return (key:gsub("[<>%-%s]", ""))
end

-- 表示幅 max に収まるように切り詰める（マルチバイト対応）
local function truncate(s, max)
  if max <= 0 then return "" end
  if vim.fn.strdisplaywidth(s) <= max then return s end
  local out = ""
  for _, ch in ipairs(vim.fn.split(s, [[\zs]])) do
    if vim.fn.strdisplaywidth(out .. ch) > max - 1 then break end
    out = out .. ch
  end
  return out .. "…"
end

---@param width integer 描画に使うウィンドウ幅
---@return string[] lines
---@return { line: integer, s: integer, e: integer, hl: string }[] highlights
local function build(width)
  local cfg = M.config
  local lines, hls = {}, {}
  local norm_seen = {}

  -- パネル自身の操作ヒント
  for _, hint in ipairs { "  q:閉じる R:更新 <Sp>k:開閉", "  <C-h>/<C-l>:ウィンドウ移動" } do
    lines[#lines + 1] = hint
    hls[#hls + 1] = { line = #lines - 1, s = 0, e = #hint, hl = "KeymapPanelMuted" }
  end

  local function section(name)
    if #lines > 0 then lines[#lines + 1] = "" end
    local header = " ■ " .. name
    lines[#lines + 1] = header
    hls[#hls + 1] = { line = #lines - 1, s = 0, e = #header, hl = "KeymapPanelSection" }
  end

  local function row(key, desc)
    key = shorten(key)
    desc = desc or ""
    local kw = cfg.key_width
    if vim.fn.strdisplaywidth(key) > kw then
      -- キーが長い場合は2行に分ける
      local l = "  " .. key
      lines[#lines + 1] = l
      hls[#hls + 1] = { line = #lines - 1, s = 2, e = #l, hl = "KeymapPanelKey" }
      lines[#lines + 1] = "    " .. truncate(desc, width - 5)
    else
      local pad = string.rep(" ", kw - vim.fn.strdisplaywidth(key) + 1)
      lines[#lines + 1] = "  " .. key .. pad .. truncate(desc, width - 3 - kw)
      hls[#hls + 1] = { line = #lines - 1, s = 2, e = 2 + #key, hl = "KeymapPanelKey" }
    end
  end

  -- 静的セクション: cheatsheet.md
  for _, sec in ipairs(cheatsheet.parse(cfg.cheatsheet)) do
    section(sec.name)
    for _, r in ipairs(sec.rows) do
      norm_seen[norm(r.key)] = true
      row(r.key, r.desc)
    end
  end

  -- 動的セクション: 自作 keymap（cheatsheet 掲載済みは除外）
  section(cfg.custom_section)
  local shown = 0
  for _, e in ipairs(detector.collect(cfg)) do
    if not norm_seen[norm(e.lhs)] then
      row(e.mode ~= "n" and (e.mode .. " " .. e.lhs) or e.lhs, e.desc)
      shown = shown + 1
    end
  end
  if shown == 0 then lines[#lines + 1] = "  (cheatsheet 掲載分のみ)" end

  return lines, hls
end

local function ensure_buf()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then return state.buf end
  local buf = vim.api.nvim_create_buf(false, true) -- nobuflisted な scratch バッファ
  vim.bo[buf].filetype = "keymap-panel"
  vim.keymap.set("n", "q", M.close, { buffer = buf, nowait = true, desc = "Close keymap panel" })
  vim.keymap.set("n", "R", M.refresh, { buffer = buf, nowait = true, desc = "Refresh keymap panel" })
  state.buf = buf
  return buf
end

function M.refresh()
  local buf = ensure_buf()
  -- パネルが開いていれば実際のウィンドウ幅で描画する（手動リサイズに追従）
  local pw = panel_win()
  local width = pw and vim.api.nvim_win_get_width(pw) or M.config.width
  local lines, hls = build(width)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(buf, ns, h.line, h.s, { end_col = h.e, hl_group = h.hl })
  end
end

function M.open()
  if panel_win() then return end -- カレントタブに開いていれば何もしない (他タブとは独立)
  local buf = ensure_buf()
  M.refresh()
  local prev = vim.api.nvim_get_current_win()
  vim.cmd("silent botright vertical sbuffer " .. buf)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, M.config.width)
  local wo = vim.wo[win]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.wrap = false
  wo.list = false
  wo.cursorline = false
  wo.winfixwidth = true
  wo.winbar = " 󰌌 Keymaps"
  vim.w[win].keymap_panel = true
  -- フォーカスは奪わない。prev は開く処理中の autocmd 連鎖で閉じられている場合があるため
  -- 検証してから戻す（headless でファイルを開くと必ず無効だった）。無効ならパネル以外の
  -- 通常ウィンドウへ移し、フォーカスがパネルに居座るのを防ぐ
  if vim.api.nvim_win_is_valid(prev) then
    vim.api.nvim_set_current_win(prev)
  else
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if
        w ~= win
        and vim.api.nvim_win_get_config(w).relative == ""
        and vim.bo[vim.api.nvim_win_get_buf(w)].filetype ~= "neo-tree"
      then
        vim.api.nvim_set_current_win(w)
        break
      end
    end
  end
end

function M.close()
  local w = panel_win()
  if w then
    pcall(vim.api.nvim_win_close, w, true) -- 最後のウィンドウだと閉じられないため pcall
  end
end

-- 全タブのパネルを閉じる (auto-session の pre_save_cmds から呼ぶ)
function M.close_all()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.w[w].keymap_panel then pcall(vim.api.nvim_win_close, w, true) end
  end
end

-- 画面の左→右の並び順で通常ウィンドウ（float 除く）を取得する
local function ordered_wins()
  local wins = {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == "" then wins[#wins + 1] = w end
  end
  table.sort(wins, function(a, b)
    local pa, pb = vim.api.nvim_win_get_position(a), vim.api.nvim_win_get_position(b)
    if pa[2] ~= pb[2] then return pa[2] < pb[2] end -- 列位置
    return pa[1] < pb[1] -- 同列なら行位置
  end)
  return wins
end

-- neo-tree ⇔ エディタ ⇔ パネルをバッファ移動 (<Sp>]) と同じ感覚で左右に巡回する
-- （端で折り返し。パネルが閉じていても通常ウィンドウ間の移動として機能する）
---@param dir 1|-1 1: 右へ / -1: 左へ
function M.focus_move(dir)
  local wins = ordered_wins()
  if #wins < 2 then return end
  local cur = vim.api.nvim_get_current_win()
  local idx = 1
  for i, w in ipairs(wins) do
    if w == cur then
      idx = i
      break
    end
  end
  vim.api.nvim_set_current_win(wins[((idx - 1 + dir) % #wins) + 1])
end

function M.focus_next() M.focus_move(1) end
function M.focus_prev() M.focus_move(-1) end

function M.toggle()
  if panel_win() then
    M.close()
  else
    M.open()
  end
end

-- neo-tree の非同期構築が終わるのを待ってから開く（自動オープン用）。
-- 構築中 (neo-tree-popup 表示中) に開くとファイルウィンドウがパネルに乗っ取られる
-- race があるため、TabNewEntered / auto-session post_save からはこちらを使う。
-- neo-tree が開けない場合 (cwd 外ファイルのタブ等) も最大 2 秒で諦めてパネルだけ開く
function M.open_when_tree_ready()
  local tab = vim.api.nvim_get_current_tabpage()
  local tries = 0
  local function poll()
    tries = tries + 1
    -- タブが閉じられた / 別タブへ移動済みなら何もしない (誤ったタブに開かない)
    if not vim.api.nvim_tabpage_is_valid(tab) or vim.api.nvim_get_current_tabpage() ~= tab then return end
    local building, has_tree = false, false
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local ft = vim.bo[vim.api.nvim_win_get_buf(w)].filetype
      if ft == "neo-tree-popup" then building = true end
      if ft == "neo-tree" then has_tree = true end
    end
    if (building or not has_tree) and tries < 20 then return vim.defer_fn(poll, 100) end
    M.open()
  end
  vim.defer_fn(poll, 100)
end

---@param opts? table
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  vim.api.nvim_set_hl(0, "KeymapPanelSection", { fg = "#bd93f9", bold = true, default = true })
  vim.api.nvim_set_hl(0, "KeymapPanelKey", { fg = "#50fa7b", default = true })
  vim.api.nvim_set_hl(0, "KeymapPanelMuted", { fg = "#6272a4", default = true })

  vim.api.nvim_create_user_command("KeymapPanel", function(cmd)
    local action = cmd.args ~= "" and cmd.args or "toggle"
    if M[action] then M[action]() end
  end, {
    nargs = "?",
    complete = function() return { "open", "close", "close_all", "toggle", "refresh", "focus_next", "focus_prev" } end,
    desc = "Keymap panel",
  })

  local group = vim.api.nvim_create_augroup("keymap_panel", { clear = true })

  if M.config.auto_open then
    -- auto-session の復元（VimEnter 中の `silent only`）でパネルが閉じられないよう、
    -- 全 VimEnter 処理が終わった後に vim.schedule で開く
    if vim.v.vim_did_enter == 1 then
      vim.schedule(M.open)
    else
      vim.api.nvim_create_autocmd("VimEnter", {
        group = group,
        once = true,
        callback = function() vim.schedule(M.open) end,
      })
    end
  end

  -- パネルのウィンドウで通常ファイルが開かれてしまった場合（パネルにフォーカスしたまま
  -- neo-tree / Telescope / :e 等でファイルを開いたとき）、パネルを復元して
  -- ファイルは中央のエディタウィンドウで開き直す
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(args)
      local pw = vim.api.nvim_get_current_win()
      if not vim.w[pw].keymap_panel then return end
      local buf = args.buf
      if buf == state.buf or vim.bo[buf].filetype == "keymap-panel" then return end
      vim.schedule(function()
        if not (vim.api.nvim_win_is_valid(pw) and vim.api.nvim_buf_is_valid(buf)) then return end
        if vim.api.nvim_win_get_buf(pw) ~= buf then return end -- 既に解消済み
        -- パネルのバッファを戻す
        vim.api.nvim_win_set_buf(pw, ensure_buf())
        vim.api.nvim_win_set_width(pw, M.config.width)
        -- サイドバー以外のエディタウィンドウ（左から最初のもの）で開き直す
        local target
        for _, w in ipairs(ordered_wins()) do
          if w ~= pw and vim.bo[vim.api.nvim_win_get_buf(w)].filetype ~= "neo-tree" then
            target = w
            break
          end
        end
        if target then
          vim.api.nvim_set_current_win(target)
          vim.api.nvim_win_set_buf(target, buf)
        else
          -- エディタウィンドウが無ければパネルの左に新規作成する
          vim.api.nvim_open_win(buf, true, { split = "left", win = pw })
          vim.api.nvim_win_set_width(pw, M.config.width)
        end
      end)
    end,
  })

  -- 手動リサイズに追従して説明文の切り詰め幅を再計算する
  local resize_pending = false
  vim.api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = function()
      if resize_pending then return end
      for _, w in ipairs(vim.v.event.windows or {}) do
        if vim.api.nvim_win_is_valid(w) and vim.w[w].keymap_panel then
          resize_pending = true
          vim.schedule(function()
            resize_pending = false
            M.refresh()
          end)
          return
        end
      end
    end,
  })

  -- 遅延ロードされた plugin が追加した keymap を反映する
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "LazyLoad",
    callback = function()
      if panel_win() then vim.schedule(M.refresh) end
    end,
  })

  -- 最後の通常ウィンドウを :q したときにパネルだけが残って終了できなくなるのを防ぐ
  -- （neo-tree の close_if_last_window 相当。サイドバー系のみ残るならパネルを閉じる）
  vim.api.nvim_create_autocmd("QuitPre", {
    group = group,
    callback = function()
      local function is_sidebar(win)
        local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
        return ft == "keymap-panel" or ft == "neo-tree"
      end
      local cur = vim.api.nvim_get_current_win()
      if is_sidebar(cur) then return end
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if w ~= cur and vim.api.nvim_win_get_config(w).relative == "" and not is_sidebar(w) then
          return -- 他に通常ウィンドウが残るなら何もしない
        end
      end
      M.close()
    end,
  })
end

return M
