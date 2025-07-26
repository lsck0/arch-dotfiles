lua require("init")

"auto file reload
set autoread
au CursorHold * checktime

" show whitespace
set list listchars=tab:>\ ,trail:-,eol:↲

" make tabline transparent
highlight WinSeparator guibg=NONE guifg=#141414 ctermbg=NONE ctermfg=8
highlight BufferCurrent guibg=NONE guibg=NONE ctermbg=NONE ctermfg=NONE
highlight BufferOffset guibg=NONE guibg=NONE ctermbg=NONE ctermfg=NONE
highlight BufferVisible guibg=NONE guibg=NONE ctermbg=NONE ctermfg=NONE
highlight StatusLine guibg=NONE guibg=NONE ctermbg=NONE ctermfg=NONE

" copilot suggestion color
highlight CopilotSuggestion guifg=#910367 ctermfg=8

" VIMTEX settings
filetype plugin indent on
syntax enable
let g:vimtex_view_general_viewer = "okular"
