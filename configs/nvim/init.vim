lua require("init")

" make tabline transparent
"highlight WinSeparator guibg=NONE guifg=#141414 ctermbg=NONE ctermfg=8
"highlight BufferCurrent guibg=NONE guifg=NONE ctermbg=NONE ctermfg=NONE
"highlight BufferOffset guibg=NONE guifg=NONE ctermbg=NONE ctermfg=NONE
"highlight BufferVisible guibg=NONE guifg=NONE ctermbg=NONE ctermfg=NONE
"highlight StatusLine guibg=NONE guifg=NONE ctermbg=NONE ctermfg=NONE

" show whitespace
set list listchars=tab:>\ ,trail:-,eol:↲

" auto file reload
set autoread
au CursorHold * checktime

" VIMTEX settings
filetype plugin indent on
syntax enable
let g:vimtex_view_general_viewer = "okular"
