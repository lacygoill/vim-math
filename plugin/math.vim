if exists('g:loaded_math')
    finish
endif
let g:loaded_math = 1

" Documentation {{{1

" A calculator can interpret math operators like `+`, `-`, `*`, `/`, but not our
" plugin. This is NOT a calculator, like the `bc` shell command.
"
" The plugin  merely installs an operator/command  to ANALYSE a set  of numbers,
" separated by  spaces or newlines. It  automatically adds operators  to compute
" different metrics. So, there  should be no math operator in  the text that the
" plugin analyses, ONLY numbers.

" Command {{{1

com! -bar -range AnalyseNumbers exe math#op('Ex', <line1>, <line2>)

" Mappings {{{1

nno <silent> +m     :<c-u>set opfunc=math#op<cr>g@
nno <silent> +mm    :<c-u>set opfunc=math#op<bar>exe 'norm! '.v:count1.'g@_'<cr>
xno <silent> +m     :<c-u>exe math#op('vis')<cr>

nno <silent> "?     :<c-u>exe math#put_metrics()<cr>
