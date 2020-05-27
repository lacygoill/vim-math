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

com -bar -range AnalyseNumbers call math#op(<line1>, <line2>)

" Mappings {{{1

nno <expr><unique> -m  math#op()
nno <expr><unique> -mm math#op()..'_'
xno <expr><unique> -m  math#op()

nno <silent><unique> "?  :<c-u>call math#put_metrics()<cr>
