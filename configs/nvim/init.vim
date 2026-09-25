lua require("init")

" show whitespace
set list listchars=tab:>\ ,trail:-,eol:↲

" make tabline transparent
highlight WinSeparator guibg=NONE guifg=#141414 ctermbg=NONE ctermfg=8
highlight BufferCurrent guibg=NONE guifg=NONE ctermbg=NONE ctermfg=NONE
highlight BufferOffset guibg=NONE guifg=NONE ctermbg=NONE ctermfg=NONE
highlight BufferVisible guibg=NONE guifg=NONE ctermbg=NONE ctermfg=NONE
highlight StatusLine guibg=NONE guifg=NONE ctermbg=NONE ctermfg=NONE

" filetype detection + syntax (vimtex settings live in lua/languages/latex.lua)
filetype plugin indent on
syntax enable
