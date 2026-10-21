-- 中文设置使用 Tern 的正式设置 API；不按内置页面的行号替换文字。
local locale = require("./locales/zh-cn")
local M = {}

local common = {
	System = "跟随系统", Light = "浅色", Dark = "深色",
	on = "开启", off = "关闭", auto = "自动", system = "跟随系统",
	always = "始终", never = "从不", allow = "允许", ask = "先询问",
}

local function display(value)
	if value == nil or value == tern.json.null then return "自动 / 未设置" end
	if value == true then return "开启" end
	if value == false then return "关闭" end
	if type(value) == "table" then return tern.json.encode(value) end
	return tostring(value)
end

local function translated(entry, value)
	local text = display(value)
	return (entry.choices and entry.choices[text]) or common[text] or text
end

local function report(cx, message, err)
	cx:toast("error", message, tostring(err))
end

local function pick(cx, options, callback)
	cx:pick(options):next(function(item, err, fresh)
		if err then report(fresh, "无法打开中文设置", err)
		elseif item then callback(item, fresh) end
	end)
end

local function apply(cx, key, value)
	local ok, result = pcall(function() return cx.settings:set(key, value) end)
	if ok then
		cx:toast("info", "已保存：" .. locale.settings[key].label, "实际值：" .. display(result))
		if M.on_saved then M.on_saved(cx) end
	else
		report(cx, "设置未保存，原值保持不变", result)
	end
end

local function edit(cx, key, entry, description)
	local value = cx.settings:get(key)
	local choices = {}
	if description.type == "boolean" then
		choices = {
			{ label = "开启", value = true, current = value == true },
			{ label = "关闭", value = false, current = value == false },
		}
	elseif description.enum then
		for _, option in ipairs(description.enum) do
			table.insert(choices, { label = translated(entry, option), detail = option,
				value = option, current = value == option })
		end
	end
	if #choices > 0 then
		if description.nullable then
			table.insert(choices, { label = "自动 / 未设置", clear = true, current = value == nil })
		end
		pick(cx, { items = choices, placeholder = entry.label .. "：选择新值", action = "保存" }, function(item, fresh)
			apply(fresh, key, if item.clear then nil else item.value)
		end)
		return
	end

	local hint = entry.label
	if description.type == "integer" or description.type == "number" then
		hint ..= "：输入数字"
		if description.range then
			hint ..= "（" .. tostring(description.range.min) .. "～" .. tostring(description.range.max) .. "）"
		end
	elseif description.type == "string" then
		hint ..= "：输入文字；清空保存为空字符串"
	else
		hint ..= "：输入 JSON（字符串需双引号）"
	end
	local initial = if value == nil then "null" else
		(if description.type == "string" then tostring(value) else tern.json.encode(value))
	cx:prompt({ value = initial, placeholder = hint, action = "检查修改" }):next(function(text, err, fresh)
		if err then report(fresh, "无法编辑设置", err); return end
		if text == nil then return end
		local proposed = text
		if description.type ~= "string" then
			local ok, decoded = pcall(tern.json.decode, text)
			if not ok then report(fresh, "输入格式不正确，未修改设置", decoded); return end
			proposed = decoded
			if (description.type == "integer" or description.type == "number") and not (description.nullable and proposed == tern.json.null) then
				if type(proposed) ~= "number" or (description.type == "integer" and proposed % 1 ~= 0) then
					fresh:toast("error", "请输入有效" .. (if description.type == "integer" then "整数" else "数字")); return
				end
			end
		end
		pick(fresh, { placeholder = "确认修改：" .. entry.label, action = "确认", items = {
			{ label = "保存修改", detail = display(value) .. " → " .. display(proposed), save = true },
			{ label = "取消，保留原值" },
		} }, function(item, latest)
			if item.save then apply(latest, key, if proposed == tern.json.null then nil else proposed) end
		end)
	end)
end

local function inspect(cx, key, entry)
	local ok, description = pcall(function() return cx.settings:describe(key) end)
	if not ok then report(cx, "此版本不支持该设置", description); return end
	local current = cx.settings:get(key)
	pick(cx, { placeholder = entry.label .. " · " .. entry.description, action = "选择", items = {
		{ label = "修改设置", detail = "当前：" .. translated(entry, current), edit = true },
		{ label = "恢复默认值", detail = translated(entry, description.default), reset = true },
		{ label = "阅读完整中文说明", detail = entry.description, explain = true },
		{ label = "原始设置键：" .. key, detail = "类型：" .. description.type },
	} }, function(item, fresh)
		if item.edit then edit(fresh, key, entry, description)
		elseif item.reset then
			pick(fresh, { placeholder = "确认恢复：" .. entry.label, action = "确认", items = {
				{ label = "恢复默认值", detail = translated(entry, description.default), reset = true },
				{ label = "取消，保留原值" },
			} }, function(choice, latest)
				if choice.reset then apply(latest, key, if description.default == tern.json.null then nil else description.default) end
			end)
		elseif item.explain then
			fresh.docs:new_note(entry.label .. " · 中文设置说明", "# " .. entry.label .. "\n\n" .. entry.description
				.. "\n\n- 设置键：`" .. key .. "`\n- 当前值：`" .. display(current)
				.. "`\n- 默认值：`" .. display(description.default) .. "`\n\n通过命令面板的“中文设置”修改此项。")
		else inspect(fresh, key, entry) end
	end)
end

function M.open(cx, group)
	local values = cx.settings:list()
	local keys = {}
	for key in pairs(values) do
		local entry = locale.settings[key]
		if entry and (not group or entry.group == group) then table.insert(keys, key) end
	end
	table.sort(keys)
	local items = {}
	for _, key in ipairs(keys) do
		local entry = locale.settings[key]
		table.insert(items, { label = entry.label .. " · " .. key .. " · " .. entry.description,
			detail = translated(entry, values[key]), key = key })
	end
	if #items == 0 then cx:toast("error", "此版本没有可用的中文设置项"); return end
	pick(cx, { items = items, placeholder = "中文设置：输入中文、英文键名或功能搜索", action = "查看 / 修改" }, function(item, fresh)
		inspect(fresh, item.key, locale.settings[item.key])
	end)
end

function M.register()
	tern.command({ id = "settings_zh", title = "中文设置：搜索全部设置…", group = "中文设置", run = function(cx) M.open(cx) end })
	for _, group in ipairs(locale.groups) do
		tern.command({ id = "settings_zh_" .. group.id, title = "中文设置：" .. group.label .. "…", group = "中文设置",
			run = function(cx) M.open(cx, group.id) end })
	end
end

M.apply = apply
M.edit = edit

return M
