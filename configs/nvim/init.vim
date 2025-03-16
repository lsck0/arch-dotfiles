lua require("init")

" copilot suggestion color
highlight CopilotSuggestion guifg=#910367 ctermfg=8

" window sep styling
highlight WinSeparator guibg=NONE guifg=#141414 ctermbg=NONE ctermfg=8

" make tabline transparent
highlight BufferCurrent guibg=NONE guibg=NONE ctermbg=NONE ctermfg=NONE
highlight BufferVisible guibg=NONE guibg=NONE ctermbg=NONE ctermfg=NONE

highlight StatusLine guibg=NONE guibg=NONE ctermbg=NONE ctermfg=NONE
highlight BufferOffset guibg=NONE guibg=NONE ctermbg=NONE ctermfg=NONE

" show whitespace
set list listchars=tab:>\ ,trail:-,eol:↲

" VIMTEX settings
filetype plugin indent on
syntax enable
let g:vimtex_view_general_viewer = "okular"

"auto file reload
set autoread
au CursorHold * checktime
