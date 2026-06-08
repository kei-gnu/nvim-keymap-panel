-- cheatsheet.md のパーサ
-- `## セクション名` と `| キー | 説明 |` のテーブル行をセクション構造に変換する
local M = {}

---@class KeymapPanelRow
---@field key string
---@field desc string

---@class KeymapPanelSection
---@field name string
---@field rows KeymapPanelRow[]

---@param path string cheatsheet.md のパス
---@return KeymapPanelSection[]
function M.parse(path)
  path = vim.fn.expand(path)
  if vim.fn.filereadable(path) ~= 1 then return {} end

  local sections = {}
  local current
  for _, line in ipairs(vim.fn.readfile(path)) do
    local header = line:match "^##%s+(.+)"
    if header then
      current = { name = (header:gsub("`", "")), rows = {} }
      sections[#sections + 1] = current
    elseif current then
      -- セル内のエスケープ済みパイプ (\|) を退避してからセル分割する
      local escaped = line:gsub("\\|", "\1")
      local key, desc = escaped:match "^|%s*(.-)%s*|%s*(.-)%s*|%s*$"
      -- ヘッダ行 (| キー | 動作 |) と区切り行 (|---|---|) は除外
      if key and key ~= "" and key ~= "キー" and not key:match "^[%-: ]+$" then
        key = key:gsub("`", ""):gsub("\1", "|")
        desc = desc:gsub("`", ""):gsub("\1", "|")
        current.rows[#current.rows + 1] = { key = key, desc = desc }
      end
    end
  end
  return sections
end

return M
