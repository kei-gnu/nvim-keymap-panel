-- 自作 keymap の動的検出
-- 2つの戦略を併用する:
--   A. 設定ファイル (lua/config 等) を正規表現でスキャンして (mode, lhs) を抽出し、
--      実際に有効なマップ (nvim_get_keymap) と突き合わせる
--      → rhs が文字列のマップ (`:bnext<CR>` 等) も拾える
--   B. nvim_get_keymap の Lua callback を debug.getinfo で辿り、
--      定義元が設定ディレクトリ配下のものを拾う
--      → plugin spec の config 内など、スキャンの正規表現で拾えない形式も拾える
local M = {}

local MODE_ORDER = { n = 1, v = 2, x = 3, s = 4, o = 5, i = 6, t = 7, c = 8 }

-- stdpath("config") とその symlink 解決先 (~/dotfiles/nvim)
local function config_roots()
  local roots = {}
  local cfg = vim.fn.fnamemodify(vim.fn.stdpath "config", ":p"):gsub("/+$", "")
  roots[#roots + 1] = cfg
  local resolved = vim.fn.resolve(cfg)
  if resolved ~= cfg then roots[#roots + 1] = resolved end
  return roots
end

local function in_config(source, roots)
  if not source or source == "" then return false end
  local path = vim.fn.fnamemodify((source:gsub("^@", "")), ":p")
  for _, root in ipairs(roots) do
    if vim.startswith(path, root .. "/") then return true end
  end
  return false
end

-- "<Leader>cc" 等の表記を実際のキーコード (bytes) に変換する
-- nvim_replace_termcodes は <Leader> を展開しないため先に置換する
local function to_raw(lhs)
  local leader = vim.g.mapleader or "\\"
  local localleader = vim.g.maplocalleader or "\\"
  lhs = lhs:gsub("<[Ll]eader>", function() return leader end)
  lhs = lhs:gsub("<[Ll]ocal[Ll]eader>", function() return localleader end)
  return vim.api.nvim_replace_termcodes(lhs, true, true, true)
end

-- 1行から (modes, lhs) を抽出する。対象は以下の典型形のみ（完全な Lua パースはしない）:
--   vim.keymap.set("n", "<lhs>", ...) / map("n", "<lhs>", ...)
--   vim.keymap.set({ "n", "v" }, "<lhs>", ...)
local function parse_line(line)
  if line:match "^%s*%-%-" then return end -- コメント行
  local head = line:match "keymap%.set%((.*)" or line:match "%f[%w]map%((.*)"
  if not head then return end

  local mode_list, rest = {}, nil
  local modes = head:match [=[^%s*["'](%a+)["']]=]
  if modes then
    mode_list[1] = modes
    rest = head:match [[^%s*["']%a+["']%s*,%s*(.*)]]
  else
    local tbl
    tbl, rest = head:match [[^%s*(%b{})%s*,%s*(.*)]]
    if not tbl then return end
    for m in tbl:gmatch [=[["'](%a+)["']]=] do
      mode_list[#mode_list + 1] = m
    end
  end
  if not rest or #mode_list == 0 then return end

  local lhs = rest:match [[^["'](..-)["']%s*,]]
  if not lhs then return end
  return mode_list, lhs
end

---@class KeymapPanelEntry
---@field mode string
---@field lhs string keytrans 済みの表示用 lhs
---@field desc string

---@param opts { scan?: string[], modes?: string[] }
---@return KeymapPanelEntry[]
function M.collect(opts)
  opts = opts or {}
  local roots = config_roots()
  local modes = opts.modes or { "n", "v", "i", "t" }

  -- mode ごとの有効マップを lhsraw (bytes) で引けるようにキャッシュ
  local cache = {}
  local function mode_maps(mode)
    if not cache[mode] then
      local t = {}
      for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
        if m.lhsraw then t[m.lhsraw] = m end
        if m.lhsrawalt then t[m.lhsrawalt] = m end
        t[m.lhs] = m
      end
      cache[mode] = t
    end
    return cache[mode]
  end

  local seen, entries = {}, {}
  local function add(mode, raw, map)
    local key = mode .. "\0" .. raw
    if seen[key] then return end
    seen[key] = true
    local desc = map.desc or (type(map.rhs) == "string" and map.rhs) or ""
    entries[#entries + 1] = { mode = mode, lhs = vim.fn.keytrans(raw), desc = desc }
  end

  -- A. 設定ファイルのスキャン
  local cfg = vim.fn.stdpath "config"
  local files = {}
  for _, rel in ipairs(opts.scan or {}) do
    local path = cfg .. "/" .. rel
    if vim.fn.isdirectory(path) == 1 then
      vim.list_extend(files, vim.fn.globpath(path, "**/*.lua", false, true))
    elseif vim.fn.filereadable(path) == 1 then
      files[#files + 1] = path
    end
  end
  for _, file in ipairs(files) do
    local ok, flines = pcall(vim.fn.readfile, file)
    for _, line in ipairs(ok and flines or {}) do
      local mode_list, lhs = parse_line(line)
      if mode_list then
        local raw = to_raw(lhs)
        for _, mode in ipairs(mode_list) do
          local m = mode_maps(mode)[raw]
          if m then add(mode, raw, m) end -- 実際に有効なマップのみ載せる
        end
      end
    end
  end

  -- B. Lua callback の定義元から検出
  for _, mode in ipairs(modes) do
    for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
      if m.callback then
        local info = debug.getinfo(m.callback, "S")
        if info and in_config(info.source, roots) then add(mode, m.lhsraw or m.lhs, m) end
      end
    end
  end

  table.sort(entries, function(a, b)
    local ma, mb = MODE_ORDER[a.mode] or 99, MODE_ORDER[b.mode] or 99
    if ma ~= mb then return ma < mb end
    return a.lhs < b.lhs
  end)
  return entries
end

return M
