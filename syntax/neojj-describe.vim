" Vim syntax file for neojj-describe filetype
" Language: NeoJJ Describe Buffer
" Maintainer: NeoJJ Plugin
" Last Change: 2024

if exists("b:current_syntax")
  finish
endif

" Comments (help text starting with #)
syn match neoJJDescribeComment "^#.*$"

" Command keybindings in help text
syn match neoJJDescribeKeybinding "\v\<[^>]+\>" contained containedin=neoJJDescribeComment

" Command names in help text (:w, :wq, etc.)
syn match neoJJDescribeCommand "\v:[a-zA-Z!]+" contained containedin=neoJJDescribeComment

" Section headers in help text
syn match neoJJDescribeSection "^# [A-Z][a-z]*:$" contained containedin=neoJJDescribeComment

" Link to existing highlight groups
hi def link neoJJDescribeComment NeoJJHelpText
hi def link neoJJDescribeKeybinding Special
hi def link neoJJDescribeCommand Statement
hi def link neoJJDescribeSection NeoJJSectionHeader

let b:current_syntax = "neojj-describe"