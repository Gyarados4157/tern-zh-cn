local locale = require("./locales/zh-cn")
local ui = tern.ui
local M = {}
local states = {}
local editor
local render

local function el(tag, text, class, children)
	return ui.el(tag, { text = text, class = class }, children)
end
local function button(label, action, class)
	return ui.el("button", { text = label, class = "zhp-button " .. (class or ""), actions = { click = action } })
end
local function value_text(value, entry)
	if value == nil or value == tern.json.null then return "自动 / 未设置" end
	if value == true then return "开启" end
	if value == false then return "关闭" end
	if type(value) == "table" then return tern.json.encode(value) end
	return (entry.choices and entry.choices[tostring(value)]) or tostring(value)
end

local function page(cx, state)
	local values = cx.settings:list()
	local nav = { el("h2", "中文设置", "zhp-brand") }
	for _, group in ipairs(locale.groups) do
		table.insert(nav, button(group.label, "zhp:group:" .. group.id, if state.group == group.id then "selected" else ""))
	end
	local group
	for _, candidate in ipairs(locale.groups) do if candidate.id == state.group then group = candidate end end
	local content = {
		el("h1", if state.query ~= "" then "搜索结果" else group.label, "zhp-title"),
		el("p", if state.query ~= "" then "搜索：" .. state.query else group.description, "zhp-lead"),
		el("div", nil, "zhp-toolbar", {
			button("搜索设置…", "zhp:search"), button("刷新当前值", "zhp:refresh"),
			button("英文原设置", "zhp:original"),
		}),
	}
	if state.query ~= "" then table.insert(content, button("清除搜索", "zhp:clear")) end
	local keys = {}
	for key in pairs(values) do
		local entry = locale.settings[key]
		if entry then
			local match = state.query ~= "" and string.find(string.lower(entry.label .. " " .. entry.description .. " " .. key), string.lower(state.query), 1, true)
			if match or (state.query == "" and entry.group == state.group) then table.insert(keys, key) end
		end
	end
	table.sort(keys)
	if #keys == 0 then table.insert(content, el("p", "没有匹配的设置。试试中文功能名称或英文设置键。", "zhp-lead")) end
	local total_pages = math.max(1, math.ceil(#keys / 40))
	state.page = math.clamp(state.page or 1, 1, total_pages)
	local pagination = function()
		return el("div", nil, "zhp-toolbar", {
			button("上一页", "zhp:prev"), el("span", "第 " .. state.page .. " / " .. total_pages .. " 页 · 共 " .. #keys .. " 项"),
			button("下一页", "zhp:next"),
		})
	end
	if total_pages > 1 then table.insert(content, pagination()) end
	for index = (state.page - 1) * 40 + 1, math.min(state.page * 40, #keys) do
		local key = keys[index]
		local entry = locale.settings[key]
		local value = values[key]
		local current = value_text(value, entry)
		local controls = {
			button(if type(value) == "boolean" then (if value then "已开启 · 点击关闭" else "已关闭 · 点击开启") else "修改…", "zhp:edit:" .. key,
				if value == true then "selected" else ""),
			button("恢复默认", "zhp:reset:" .. key),
		}
		local row = el("section", nil, "zhp-setting", {
			el("h3", entry.label, "zhp-label"), el("p", entry.description, "zhp-description"),
			el("code", key, "zhp-key"),
			el("p", "当前值：" .. current, "zhp-value"),
			el("div", nil, "zhp-controls", controls),
		})
		row.p.key = key
		table.insert(content, row)
	end
	return el("div", nil, "zhp-root", {
		el("nav", nil, "zhp-nav", nav), el("main", nil, "zhp-content", content),
	})
end

render = function(cx, pane)
	local state = states[pane]
	if state and cx.canvas:get(pane) then cx.canvas:set(pane, { view = page(cx, state) }) end
end

function M.open(cx, group)
	for _, canvas in ipairs(cx.canvas:list()) do
		if canvas.owner == tern.plugin.id and canvas.title == "中文设置" then
			states[canvas.pane] = { group = group or "general", query = "" }
			render(cx, canvas.pane)
			cx.session:focus(canvas.pane)
			return
		end
	end
	local state = { group = group or "general", query = "" }
	local pane, err = cx.canvas:open({ title = "中文设置", view = page(cx, state), how = "tab",
		about = "中文设置页。分类浏览、搜索、修改实际 Tern 设置；恢复默认前确认。" })
	if not pane then cx:toast("error", "无法打开中文设置页", err); return end
	states[pane] = state
end

function M.register(settings_editor)
	editor = settings_editor
	editor.on_saved = function(cx)
		for pane in pairs(states) do render(cx, pane) end
	end
	tern.on("canvas_action", function(ev, cx)
		if ev.owner ~= tern.plugin.id or string.sub(ev.act, 1, 4) ~= "zhp:" then return false end
		states[ev.pane] = states[ev.pane] or { group = "general", query = "" }
		local state = states[ev.pane]
		local group = string.match(ev.act, "^zhp:group:(.+)$")
		local key = string.match(ev.act, "^zhp:edit:(.+)$")
		local reset = string.match(ev.act, "^zhp:reset:(.+)$")
		if group then state.group = group; state.query = ""; state.page = 1; render(cx, ev.pane)
		elseif key and locale.settings[key] then
			local value = cx.settings:get(key)
			if type(value) == "boolean" then editor.apply(cx, key, not value)
			else editor.edit(cx, key, locale.settings[key], cx.settings:describe(key)) end
		elseif reset and locale.settings[reset] then
			local desc = cx.settings:describe(reset)
			cx:pick({ placeholder = "确认恢复：" .. locale.settings[reset].label, action = "确认", items = {
				{ label = "恢复默认值", detail = value_text(desc.default, locale.settings[reset]), reset = true },
				{ label = "取消，保留原值" },
			} }):next(function(choice, err, fresh)
				if err then fresh:toast("error", "未恢复设置", err)
				elseif choice and choice.reset then editor.apply(fresh, reset, if desc.default == tern.json.null then nil else desc.default) end
			end)
		elseif ev.act == "zhp:search" then
			cx:prompt({ value = state.query, placeholder = "搜索中文名称、说明或英文设置键", action = "搜索" }):next(function(query, err, fresh)
				if err then fresh:toast("error", "搜索未完成", err)
				elseif query ~= nil then state.query = query; state.page = 1; render(fresh, ev.pane) end
			end)
		elseif ev.act == "zhp:clear" then state.query = ""; state.page = 1; render(cx, ev.pane)
		elseif ev.act == "zhp:prev" then state.page = math.max(1, (state.page or 1) - 1); render(cx, ev.pane)
		elseif ev.act == "zhp:next" then state.page = (state.page or 1) + 1; render(cx, ev.pane)
		elseif ev.act == "zhp:original" then cx:command("preferences")
		elseif ev.act == "zhp:refresh" then render(cx, ev.pane)
		end
		return true
	end)
	tern.on("pane_closed", function(ev) states[ev.pane] = nil end)
	tern.on("focus", function(ev, cx) if states[ev.pane] then render(cx, ev.pane) end end)
	tern.command({ id = "settings_page_zh", title = "中文设置：打开设置页面…", group = "中文设置", run = function(cx) M.open(cx) end })
end

return M
