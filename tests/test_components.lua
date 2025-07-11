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

	expect.equality(Component.is_component(component), true)
	expect.equality(component:get_tag(), "TestComponent")
	expect.equality(component:get_value(), "test")
	expect.equality(type(component:get_children()), "table")
	expect.equality(type(component:get_options()), "table")
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

	expect.equality(component:is_foldable(), true)
	expect.equality(component:is_folded(), false)
	expect.equality(component:is_interactive(), true)
	expect.equality(component:get_section(), "test_section")
	expect.equality(component:get_highlight(), "TestHighlight")
end

---Test UI primitive creation
---@return nil
T.test_ui_primitives = function()
	local Ui = require("neojj.lib.ui")
	local Component = require("neojj.lib.ui.component")

	-- Test text component
	local text = Ui.text("Hello World", { highlight = "String" })
	expect.equality(Component.is_component(text), true)
	expect.equality(text:get_tag(), "Text")
	expect.equality(text:get_value(), "Hello World")
	expect.equality(text:get_highlight(), "String")

	-- Test column component
	local col = Ui.col({ text }, { foldable = true })
	expect.equality(Component.is_component(col), true)
	expect.equality(col:get_tag(), "Col")
	expect.equality(#col:get_children(), 1)
	expect.equality(col:is_foldable(), true)

	-- Test row component
	local row = Ui.row({ text }, { interactive = true })
	expect.equality(Component.is_component(row), true)
	expect.equality(row:get_tag(), "Row")
	expect.equality(#row:get_children(), 1)
	expect.equality(row:is_interactive(), true)

	-- Test empty line
	local empty = Ui.empty_line()
	expect.equality(Component.is_component(empty), true)
	expect.equality(empty:get_tag(), "Text")
	expect.equality(empty:get_value(), "")
end

---Test UI helper functions
---@return nil
T.test_ui_helpers = function()
	local Ui = require("neojj.lib.ui")
	local Component = require("neojj.lib.ui.component")

	-- Test section header
	local header = Ui.section_header("Test Section", 5)
	expect.equality(Component.is_component(header), true)
	expect.equality(header:get_value(), "Test Section (5)")
	expect.equality(header:get_highlight(), "NeoJJSectionHeader")

	-- Test file item
	local file_item = Ui.file_item("M", "src/test.lua")
	expect.equality(Component.is_component(file_item), true)
	expect.equality(file_item:get_tag(), "Row")
	expect.equality(#file_item:get_children(), 3) -- status, space, path

	-- Test commit info
	local commit = Ui.commit_info("abc123", "def456", "Test commit", { name = "Test User", email = "test@example.com" })
	expect.equality(Component.is_component(commit), true)
	expect.equality(commit:get_tag(), "Col")
	expect.equality(#commit:get_children(), 4) -- change_id, commit_id, description, author

	-- Test section
	local section = Ui.section("Test Section", {
		Ui.text("Item 1"),
		Ui.text("Item 2"),
	})
	expect.equality(Component.is_component(section), true)
	expect.equality(section:get_tag(), "Col")
	expect.equality(section:is_foldable(), true)
	expect.equality(section:get_section(), "test_section")
end

---Test component with tagged constructors
---@return nil
T.test_tagged_constructors = function()
	local Ui = require("neojj.lib.ui")
	local Component = require("neojj.lib.ui.component")

	-- Test tagged column
	local TaggedCol = Ui.tagged_col("CustomCol")
	local tagged_col = TaggedCol({ Ui.text("test") }, { custom = true })
	expect.equality(Component.is_component(tagged_col), true)
	expect.equality(tagged_col:get_tag(), "Col")
	expect.equality(tagged_col:get_options().tag, "CustomCol")
	expect.equality(tagged_col:get_options().custom, true)

	-- Test tagged row
	local TaggedRow = Ui.tagged_row("CustomRow")
	local tagged_row = TaggedRow({ Ui.text("test") }, { custom = true })
	expect.equality(Component.is_component(tagged_row), true)
	expect.equality(tagged_row:get_tag(), "Row")
	expect.equality(tagged_row:get_options().tag, "CustomRow")

	-- Test tagged text
	local TaggedText = Ui.tagged_text("CustomText")
	local tagged_text = TaggedText("test", { custom = true })
	expect.equality(Component.is_component(tagged_text), true)
	expect.equality(tagged_text:get_tag(), "Text")
	expect.equality(tagged_text:get_options().tag, "CustomText")
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

	expect.equality(Component.is_component(nested), true)
	expect.equality(nested:get_tag(), "Col")
	expect.equality(#nested:get_children(), 3)

	-- Test nested children
	local row_child = nested:get_children()[2]
	expect.equality(Component.is_component(row_child), true)
	expect.equality(row_child:get_tag(), "Row")
	expect.equality(#row_child:get_children(), 2)

	local col_child = nested:get_children()[3]
	expect.equality(Component.is_component(col_child), true)
	expect.equality(col_child:get_tag(), "Col")
	expect.equality(#col_child:get_children(), 2)
end

---Test component with_tag constructor
---@return nil
T.test_with_tag_constructor = function()
	local Component = require("neojj.lib.ui.component")
	local Ui = require("neojj.lib.ui")

	-- Test with_tag constructor
	local CustomComponent = Component.with_tag("CustomTag")
	local component = CustomComponent({ Ui.text("test") }, { foldable = true })

	expect.equality(Component.is_component(component), true)
	expect.equality(component:get_tag(), "CustomTag")
	expect.equality(component:is_foldable(), true)
end

---Test component validation
---@return nil
T.test_component_validation = function()
	local Component = require("neojj.lib.ui.component")

	-- Test non-component objects
	expect.equality(Component.is_component(nil), false)
	expect.equality(Component.is_component("string"), false)
	expect.equality(Component.is_component(123), false)
	expect.equality(Component.is_component({}), false)
	expect.equality(Component.is_component({ tag = nil }), false)

	-- Test valid component
	local valid_component = { tag = "Test", children = {}, options = {} }
	setmetatable(valid_component, Component)
	expect.equality(Component.is_component(valid_component), true)
end

return T
