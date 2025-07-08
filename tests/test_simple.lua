---Simple test for JJ status UI
---@type table
local T = MiniTest.new_set()

---Test basic component creation
---@return nil
T.test_basic_component = function()
	local Component = require("neojj.lib.ui.component")

	-- Test component factory
	local TestComponent = Component.new(function(props)
		return {
			tag = "TestComponent",
			children = props.children or {},
			options = props.options or {},
			value = props.value,
		}
	end)

	local component = TestComponent({ value = "test" })

	-- Basic assertions
	if not Component.is_component(component) then
		error("Component should be identified as a component")
	end

	if component:get_tag() ~= "TestComponent" then
		error("Component tag should be 'TestComponent'")
	end

	if component:get_value() ~= "test" then
		error("Component value should be 'test'")
	end

	print("✓ Basic component creation works")
end

---Test UI primitives
---@return nil
T.test_ui_primitives = function()
	local Ui = require("neojj.lib.ui")
	local Component = require("neojj.lib.ui.component")

	-- Test text component
	local text = Ui.text("Hello World")
	if not Component.is_component(text) then
		error("Text should be a component")
	end

	if text:get_tag() ~= "Text" then
		error("Text tag should be 'Text'")
	end

	if text:get_value() ~= "Hello World" then
		error("Text value should be 'Hello World'")
	end

	-- Test column component
	local col = Ui.col({ text })
	if not Component.is_component(col) then
		error("Column should be a component")
	end

	if col:get_tag() ~= "Col" then
		error("Column tag should be 'Col'")
	end

	if #col:get_children() ~= 1 then
		error("Column should have 1 child")
	end

	print("✓ UI primitives work")
end

---Test status UI creation
---@return nil
T.test_status_ui = function()
	local StatusUI = require("neojj.buffers.status.ui")

	-- Create test UI
	local components = StatusUI.create_test_ui()

	if #components == 0 then
		error("Status UI should create components")
	end

	print("✓ Status UI creation works")
end

---Test buffer creation
---@return nil
T.test_buffer_creation = function()
	local Buffer = require("neojj.lib.buffer")

	-- Create a test buffer
	local buffer = Buffer.new({
		name = "test-buffer",
		filetype = "test",
		modifiable = false,
	})

	if not buffer:is_valid() then
		error("Buffer should be valid")
	end

	if buffer:get_name() ~= "test-buffer" then
		error("Buffer name should be 'test-buffer'")
	end

	-- Clean up
	buffer:close()

	print("✓ Buffer creation works")
end

---Test highlight setup
---@return nil
T.test_highlights = function()
	local Highlights = require("neojj.highlights")

	-- Setup highlights
	Highlights.setup()

	-- Test file status highlight mapping
	local hl = Highlights.get_file_status_highlight("M")
	if hl ~= "NeoJJFileModified" then
		error("Modified file highlight should be 'NeoJJFileModified'")
	end

	local hl2 = Highlights.get_file_status_highlight("A")
	if hl2 ~= "NeoJJFileAdded" then
		error("Added file highlight should be 'NeoJJFileAdded'")
	end

	print("✓ Highlights work")
end

return T
