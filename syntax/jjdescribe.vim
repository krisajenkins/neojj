" Vim syntax file for jjdescribe filetype
" Language: JJ Describe Buffer
" Maintainer: NeoJJ Plugin
" Last Change: 2024

if exists("b:current_syntax")
  finish
endif

" Comments (help text starting with #)
syn match jjDescribeComment "^#.*$"

" Command keybindings in help text
syn match jjDescribeKeybinding "\v\<[^>]+\>" contained containedin=jjDescribeComment

" Command names in help text (:w, :wq, etc.)
syn match jjDescribeCommand "\v:[a-zA-Z!]+" contained containedin=jjDescribeComment

" Section headers in help text
syn match jjDescribeSection "^# [A-Z][a-z]*:$" contained containedin=jjDescribeComment

" Link to existing highlight groups
hi def link jjDescribeComment NeoJJHelpText
hi def link jjDescribeKeybinding Special
hi def link jjDescribeCommand Statement
hi def link jjDescribeSection NeoJJSectionHeader

let b:current_syntax = "jjdescribe"