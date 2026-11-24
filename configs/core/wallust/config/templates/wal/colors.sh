wallpaper='{wallpaper}'

background='{background}'
foreground='{foreground}'
cursor='{cursor}'

color0='{color0}'
color1='{color1}'
color2='{color2}'
color3='{color3}'
color4='{color4}'
color5='{color5}'
color6='{color6}'
color7='{color7}'
color8='{color8}'
color9='{color9}'
color10='{color10}'
color11='{color11}'
color12='{color12}'
color13='{color13}'
color14='{color14}'
color15='{color15}'

# guarded so a nested shell does not append the same options and entries again
if [ -z "$WAL_SHELL_COLORS" ]; then
    export WAL_SHELL_COLORS=1
    export FZF_DEFAULT_OPTS="
    $FZF_DEFAULT_OPTS
    --color fg:-1,bg:-1,hl:12,fg+:0,bg+:12,hl+:0,gutter:-1
    --color info:8,prompt:10,spinner:12,pointer:0,marker:10,header:11,border:8,separator:8,scrollbar:8
"
    export LS_COLORS="${{LS_COLORS}}:su=30;41:ow=30;42:st=30;44:"
fi
