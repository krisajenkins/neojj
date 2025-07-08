---@type table
local T = MiniTest.new_set()
local expect = MiniTest.expect

---Test Component creation and basic functionality
---@return nil
T.test_component_creation = function()
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

	expect(Component.is_component(component)).to_be(true)
	expect(component:get_tag()).to_be("TestComponent")
	expect(component:get_value()).to_be("test")
	expect(type(component:get_children())).to_be("table")
	expect(type(component:get_options())).to_be("table")
end

---Test component options
---@return nil
T.test_component_options = function()
	local Component = require("neojj.lib.ui.component")

	local TestComponent = Component.new(function(props)
		return {
			tag = "TestComponent",
			children = {},
			options = {
				foldable = true,
				folded = false,
				interactive = true,
				section = "test_section",
				highlight = "TestHighlight",
			},
			value = props.value,
		}
	end)

	local component = TestComponent({ value = "test" })

	expect(component:is_foldable()).to_be(true)
	expect(component:is_folded()).to_be(false)
	expect(component:is_interactive()).to_be(true)
	expect(component:get_section()).to_be("test_section")
	expect(component:get_highlight()).to_be("TestHighlight")
end

---Test UI primitive creation
---@return nil
T.test_ui_primitives = function()
	local Ui = require("neojj.lib.ui")
	local Component = require("neojj.lib.ui.component")

	-- Test text component
	local text = Ui.text("Hello World", { highlight = "String" })
	expect(Component.is_component(text)).to_be(true)
	expect(text:get_tag()).to_be("Text")
	expect(text:get_value()).to_be("Hello World")
	expect(text:get_highlight()).to_be("String")

	-- Test column component
	local col = Ui.col({ text }, { foldable = true })
	expect(Component.is_component(col)).to_be(true)
	expect(col:get_tag()).to_be("Col")
	expect(#col:get_children()).to_be(1)
	expect(col:is_foldable()).to_be(true)

	-- Test row component
	local row = Ui.row({ text }, { interactive = true })
	expect(Component.is_component(row)).to_be(true)
	expect(row:get_tag()).to_be("Row")
	expect(#row:get_children()).to_be(1)
	expect(row:is_interactive()).to_be(true)

	-- Test empty line
	local empty = Ui.empty_line()
	expect(Component.is_component(empty)).to_be(true)
	expect(empty:get_tag()).to_be("Text")
	expect(empty:get_value()).to_be("")
end

---Test UI helper functions
---@return nil
T.test_ui_helpers = function()
	local Ui = require("neojj.lib.ui")
	local Component = require("neojj.lib.ui.component")

	-- Test section header
	local header = Ui.section_header("Test Section", 5)
	expect(Component.is_component(header)).to_be(true)
	expect(header:get_value()).to_be("Test Section (5)")
	expect(header:get_highlight()).to_be("NeoJJSectionHeader")

	-- Test file item
	local file_item = Ui.file_item("M", "src/test.lua")
	expect(Component.is_component(file_item)).to_be(true)
	expect(file_item:get_tag()).to_be("Row")
	expect(#file_item:get_children()).to_be(3) -- status, space, path

	-- Test commit info
	local commit = Ui.commit_info("abc123", "def456", "Test commit", { name = "Test User", email = "test@example.com" })
	expect(Component.is_component(commit)).to_be(true)
	expect(commit:get_tag()).to_be("Col")
	expect(#commit:get_children()).to_be(4) -- change_id, commit_id, description, author

	-- Test section
	local section = Ui.section("Test Section", {
		Ui.text("Item 1"),
		Ui.text("Item 2"),
	})
	expect(Component.is_component(section)).to_be(true)
	expect(section:get_tag()).to_be("Col")
	expect(section:is_foldable()).to_be(true)
	expect(section:get_section()).to_be("test_section")
end

---Test component with tagged constructors
---@return nil
T.test_tagged_constructors = function()
	local Ui = require("neojj.lib.ui")
	local Component = require("neojj.lib.ui.component")

	-- Test tagged column
	local TaggedCol = Ui.tagged_col("CustomCol")
	local tagged_col = TaggedCol({ Ui.text("test") }, { custom = true })
	expect(Component.is_component(tagged_col)).to_be(true)
	expect(tagged_col:get_tag()).to_be("Col")
	expect(tagged_col:get_options().tag).to_be("CustomCol")
	expect(tagged_col:get_options().custom).to_be(true)

	-- Test tagged row
	local TaggedRow = Ui.tagged_row("CustomRow")
	local tagged_row = TaggedRow({ Ui.text("test") }, { custom = true })
	expect(Component.is_component(tagged_row)).to_be(true)
	expect(tagged_row:get_tag()).to_be("Row")
	expect(tagged_row:get_options().tag).to_be("CustomRow")

	-- Test tagged text
	local TaggedText = Ui.tagged_text("CustomText")
	local tagged_text = TaggedText("test", { custom = true })
	expect(Component.is_component(tagged_text)).to_be(true)
	expect(tagged_text:get_tag()).to_be("Text")
	expect(tagged_text:get_options().tag).to_be("CustomText")
end

---Test nested component structures
---@return nil
T.test_nested_components = function()
	local Ui = require("neojj.lib.ui")
	local Component = require("neojj.lib.ui.component")

	-- Create a nested structure
	local nested = Ui.col({
		Ui.text("Header"),
		Ui.row({
			Ui.text("Left"),
			Ui.text("Right"),
		}),
		Ui.col({
			Ui.text("Nested item 1"),
			Ui.text("Nested item 2"),
		}),
	})

	expect(Component.is_component(nested)).to_be(true)
	expect(nested:get_tag()).to_be("Col")
	expect(#nested:get_children()).to_be(3)

	-- Test nested children
	local row_child = nested:get_children()[2]
	expect(Component.is_component(row_child)).to_be(true)
	expect(row_child:get_tag()).to_be("Row")
	expect(#row_child:get_children()).to_be(2)

	local col_child = nested:get_children()[3]
	expect(Component.is_component(col_child)).to_be(true)
	expect(col_child:get_tag()).to_be("Col")
	expect(#col_child:get_children()).to_be(2)
end

---Test component with_tag constructor
---@return nil
T.test_with_tag_constructor = function()
	local Component = require("neojj.lib.ui.component")
	local Ui = require("neojj.lib.ui")

	-- Test with_tag constructor
	local CustomComponent = Component.with_tag("CustomTag")
	local component = CustomComponent({ Ui.text("test") }, { foldable = true })

	expect(Component.is_component(component)).to_be(true)
	expect(component:get_tag()).to_be("CustomTag")
	expect(component:is_foldable()).to_be(true)
end

---Test component validation
---@return nil
T.test_component_validation = function()
	local Component = require("neojj.lib.ui.component")

	-- Test non-component objects
	expect(Component.is_component(nil)).to_be(false)
	expect(Component.is_component("string")).to_be(false)
	expect(Component.is_component(123)).to_be(false)
	expect(Component.is_component({})).to_be(false)
	expect(Component.is_component({ tag = nil })).to_be(false)

	-- Test valid component
	local valid_component = { tag = "Test", children = {}, options = {} }
	setmetatable(valid_component, Component)
	expect(Component.is_component(valid_component)).to_be(true)
end

return T
