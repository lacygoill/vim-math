if exists('g:autoloaded_math')
    finish
endif
let g:autoloaded_math = 1

fu! s:analyse() abort "{{{1
    let [ raw_numbers, numbers ] = s:extract_data()
    call s:calculate_metrics(raw_numbers, numbers)
    call s:report()
endfu

fu! s:calculate_metrics(raw_numbers, numbers) abort "{{{1
    let [ raw_numbers, numbers ] = [ a:raw_numbers, a:numbers ]

    let cnt = len(numbers)

    let s:metrics = {
    \                 'sum'   : str2float(s:sum_or_avg(cnt, raw_numbers, 0)),
    \                 'avg'   : str2float(s:sum_or_avg(cnt, raw_numbers, 1)),
    \                 'prod'  : str2float(s:product(cnt, raw_numbers)),
    \                 'min'   : my_lib#min(numbers),
    \                 'max'   : my_lib#max(numbers),
    \                 'count' : cnt,
    \               }

    call map(s:metrics, 's:prettify(v:val)')
    "                      │
    "                      └─ • compact notation for big/small numbers
    "                         • remove possible ending `.0`
endfu

fu! s:extract_data() abort "{{{1
    let selection = getreg('"')
    "                                       ┌─ default 2nd argument = \_s\+
    "                                       │
    let raw_numbers = filter(split(selection), 'v:val =~# s:num_pat')
    let numbers     = map(copy(raw_numbers), 'str2float(v:val)')
    "                                         │
    "                                         └─ Vim's default coercion is good enough for integers
    "                                            but not for floats:
    "
    "                                                    echo '12' + 3
    "                                                    → 15    ✔
    "
    "                                                    echo '1.2' + 3
    "                                                    → 4     ✘
    "
    "                                            … so we need to call `str2float()` to perform the right
    "                                            conversion, from a string to the float it contains.
    return [ raw_numbers, numbers ]
endfu

fu! s:get_num_pat() abort "{{{1
    let sign     = '[+-]?'
    let decimal  = '\d+\.?\d*'
    let fraction = '\.\d+'
    let exponent = '[eE]'.sign.'\d+'
    return printf('\v^%s%%(%s|%s)%%(%s)?$', sign, decimal, fraction, exponent)
endfu

let s:num_pat = s:get_num_pat()

fu! math#op(type, ...) abort "{{{1
    let cb_save  = &cb
    let sel_save = &selection
    let reg_save = [ getreg('"'), getregtype('"') ]
    try
        set cb-=unnamed cb-=unnamedplus
        set selection=inclusive

        if a:type ==# 'char'
            sil norm! `[v`]y
        elseif a:type ==# 'line'
            sil norm! '[V']y
        elseif a:type ==# 'block'
            sil exe "norm! `[\<c-v>`]y"
        elseif index(['v', 'V', "\<c-v>"], a:type) != -1
            sil norm! gvy
        elseif a:type ==# 'Ex'
            sil exe a:1.','.a:2.'y'
        else
            return ''
        endif
        call s:analyse()
    catch
        if index(['char', 'line', 'block'], a:type) != -1
            echohl ErrorMsg
            echom v:exception
            echohl NONE
        else
            return 'echoerr '.string(v:exception)
        endif
    finally
        let &cb  = cb_save
        let &sel = sel_save
        call setreg('"', reg_save[0], reg_save[1])
    endtry
    return ''
endfu

fu! s:prettify(number) abort "{{{1
    "                          ┌ use notation with exponent, if the number is too big/small
    "                         ┌┤
    return substitute(printf('%g', a:number), '\.0\+$', '', '')
    "                                          └────┤
    "                                               └ remove possible ending `.0`
    "
    "                                                 `%g` already removes non-significant zero(s),
    "                                                 but NOT if there's only one:
    "
    "                                                         123.0
    "
    "                                                 … because it characterizes a float.
endfu

fu! s:product(cnt, raw_numbers) abort "{{{1
    let product = eval(a:cnt ? join(a:raw_numbers, ' * ') : '0')

    " What are significant digits?{{{
    "
    "         http://mathworld.wolfram.com/SignificantDigits.html
    "         https://en.wikipedia.org/wiki/Significant_figures#Concise_rules
    "
    " The significant digits of a number are the digits necessary to express the
    " latter within the uncertainty of calculation.
    " Ex:
    "                     ┌ known quantity
    "         ┌───────────┤
    "         1.234 ± 0.002
    "         └───┤
    "             └ 4 significant digits
    "
    " My_definition:
    " They  are the digits  which allow you to  position the number  on the
    " “right“ ruler. What is a right ruler?
    " A ruler, such as the unit allows you to express the number as an integer,
    " without any 0 at the end.
    "
    " Non-zero digits (1-9) are always significant.
    " A `0` can be significant or not, depending on its position in the number:
    "
    "         • in a sequence of 0's at the beginning:    NOT significant
    "
    "         • somewhere between 2 non-zero digits:          significant
    "
    "         • in a sequence of 0's at the end
    "           of a number WITH a decimal point:             significant
    "
    "         • in a sequence of 0's at the end
    "           of a number WITHOUT a decimal point:      need more info
    "}}}
    " NO zero in a sequence of 0's at the beginning of a number can be significant.{{{
    " Even if it's after the decimal point.
    "
    " Why?
    " Because it doesn't help you to position the number on the ruler.  Instead,
    " it merely helps you to choose the right ruler (i.e. with the right unit).
    "}}}
    " How does more info help to determine whether a 0 at the end of a number is significant?{{{
    "
    " Additional info can specify the accuracy of the number.
    " A `0` which gives to the number an accuracy greater than the one specified
    " by this info is NOT significant.
    "
    "         1300
    "           └┤
    "            └ without additional info, you don't know whether these are significant:
    "
    "                  • they are     , if the measure is accurate to      1         unit
    "                  • they are not , if the measure is accurate to only 10 or 100 units
    "}}}
    " Don't use the expression “significant  figures“.{{{
    " Yes, it's very common, even in math, but it's also confusing.
    " In math, a figure refers to a geometric shape.
    "}}}
    " What is the number of significant digits in the result of a product?{{{
    "
    " The smallest  number of significant digits  of any number involved  in the
    " initial calculation.
    "}}}
    " What is the number of significant digits in the result of a sum?{{{
    "
    " The number  of significant digits in  the smallest number involved  in the
    " initial calculation.
    "}}}

    let significant_digits = min(map(copy(a:raw_numbers),
    \                                'strlen(substitute(v:val, ''\v^0+|\.|-'', "", "g"))')
    \                            +[10])
    "                              │
    "                              └─ never go above 10 significant digits

    let product = significant_digits > 0
    \?                printf('%.*f', significant_digits, product)
    \:                string(product)

    let product = split(product, '\zs')
    let i = 0
    for char in product
        if char !=# '-' && char !=# '.'
            let significant_digits -= 1
            if significant_digits < 0
                let product[i] = '0'
            endif
        endif
        let i += 1
    endfor
    return join(product, '')

    " Alternative:
    "         let n = significant_digits + (match(product,'-') != -1) + (match(product,'\.') != -1)
    "         return matchstr(product, '^-')
    "         \     .matchstr(product, '[0-9]\{'.significant_digits.'}')
    "         \     .substitute(matchstr(product, '[0-9]\{'.significant_digits.'}\zs.*'), '[^-.]', '0', 'g')
endfu

fu! math#put_metrics() abort "{{{1
    try
        if !exists('s:metrics')
            return 'echo "no metrics"'
        endif

        let choice = inputlist([ 'Metrics',
        \                        '1. all',
        \                        '2. sum',
        \                        '3. avg',
        \                        '4. prod',
        \                        '5. min',
        \                        '6. max',
        \                        '7. count' ])
        if choice >= 2 && choice <= 7
            let metrics = [ 'sum', 'avg', 'prod', 'min', 'max', 'count' ][choice - 2]
            let output  = s:metrics[metrics]
        elseif choice == 1
            let output = 'sum: '  .s:metrics.sum   .'   '
            \           .'avg: '  .s:metrics.avg   .'   '
            \           .'prod: ' .s:metrics.prod  .'   '
            \           .'min: '  .s:metrics.min   .'   '
            \           .'max: '  .s:metrics.max   .'   '
            \           .'count: '.s:metrics.count
        else
            return ''
        endif
        put =output
    catch
        return 'echoerr '.string(v:exception)
    endtry
    return ''
endfu

fu! s:report() abort "{{{1
    for a_metrics in [ 'sum', 'avg', 'prod', 'min', 'max', 'count'  ]
        echon printf('%s: %s   ', a_metrics, s:metrics[a_metrics])
    endfor
endfu

fu! s:sum_or_avg(cnt, raw_numbers, avg) abort "{{{1
    let sum = eval(a:cnt ? join(a:raw_numbers, ' + ') : '0')
    if a:avg
        let sum = 1.0 * sum / a:cnt
    endif

    " When you add  2 numbers in math, A  and B, A being accurate  to P1 decimal{{{
    " places,  and B  to  P2 decimal  places,  the result  must  be accurate  to
    " min(P1,P2) decimal places.
    "
    "         http://mathforum.org/library/drmath/view/58335.html
    "
    " So, if we sum several numbers with different precisions, the result should
    " be as accurate as the least accurate number:
    "
    "         avg(1.2, 3.45) = 2.325    ✘
    "         avg(1.2, 3.45) = 2.3      ✔
    "}}}
    let decimal_places = min(map(copy(a:raw_numbers),
    \                            'strlen(matchstr(v:val, ''\.\zs\d\+$''))')
    \                        +[10])
    "                          │
    "                          └─ never go above 10 digits after the decimal point

    return decimal_places > 0
    \?         printf('%.*f', decimal_places, sum)
    \:         string(sum)
endfu
