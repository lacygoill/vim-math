if exists('g:loaded_math')
    finish
endif
let g:loaded_math = 1

" Command {{{1

com! -bar -range AnalyseNumbers exe math#op('Ex', <line1>, <line2>)

" Mappings {{{1

nno <silent> +m     :<c-u>set opfunc=math#op<cr>g@
nno <silent> +mm    :<c-u>set opfunc=math#op<bar>exe 'norm! '.v:count1.'g@_'<cr>
xno <silent> +m     :<c-u>exe math#op(visualmode())<cr>

nno <silent> "?     :<c-u>exe math#put_metrics()<cr>
