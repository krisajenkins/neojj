" Filetype detection for NeoJJ plugin
" This ensures that buffers with jjdescribe filetype get proper syntax highlighting

" The describe buffer filetype is already set in lua/neojj/buffers/describe/init.lua
" This file ensures that if the filetype is manually set or restored, it's recognized
autocmd BufRead,BufNewFile * if &filetype == 'jjdescribe' | setfiletype jjdescribe | endif