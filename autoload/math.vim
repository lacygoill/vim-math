if exists('g:autoloaded_math')
    finish
endif
let g:autoloaded_math = 1

" Init {{{1

import {Catch, Opfunc} from 'lg.vim'
import {Max, Min} from 'lg/math.vim'
const s:SID = execute('fu s:Opfunc')->matchstr('\C\<def\s\+\zs<SNR>\d\+_')

fu s:get_num_pat() abort
    let sign = '[+-]\='
    let decimal = '\d\+\.\=\d*'
    let fraction = '\.\d\+'
    let exponent = '[eE]' .. sign .. '\d\+'
    return printf('^%s\%%(%s\|%s\)\%%(%s\)\=$', sign, decimal, fraction, exponent)
endfu

const s:NUM_PAT = s:get_num_pat()

fu s:calculate_metrics(raw_numbers, numbers) abort "{{{1
    let [raw_numbers, numbers] = [a:raw_numbers, a:numbers]

    let cnt = len(numbers)

    let s:metrics = {
        \   'sum': s:sum_or_avg(cnt, raw_numbers, 0)->str2float(),
        \   'avg': s:sum_or_avg(cnt, raw_numbers, 1)->str2float(),
        \   'prod': s:product(cnt, raw_numbers)->str2float(),
        \   'min': s:Min(numbers),
        \   'max': s:Max(numbers),
        \   'count': cnt,
        \ }

    call map(s:metrics, {_, v -> s:prettify(v)})
    "                              │
    "                              └ * scientific notation for big/small numbers
    "                                * remove possible ending `.0`
endfu

fu s:extract_data() abort "{{{1
    let selection = getreg('"')
    "                                ┌ default 2nd argument = \_s\+
    "                                │
    let raw_numbers = split(selection)->filter({_, v -> v =~# s:NUM_PAT})
    let numbers = copy(raw_numbers)->map({_, v -> str2float(v)})
    "                                             │
    "                                             └ Vim's default coercion is good enough for integers
    "                                               but not for floats:
    "
    "                                               echo '12' + 3
    "                                               15    ✔~
    "
    "                                               echo '1.2' + 3
    "                                               4     ✘~
    "
    "                                         ... so we need to call `str2float()` to perform the right
    "                                         conversion, from a string to the float it contains.
    return [raw_numbers, numbers]
endfu

fu math#op() abort "{{{1
    let &opfunc = s:SID .. 'Opfunc'
    let g:opfunc = {
        \ 'core': 'math#op_core',
        \ }
    return 'g@'
endfu

fu math#op_core(type) abort
    let [raw_numbers, numbers] = s:extract_data()
    call s:calculate_metrics(raw_numbers, numbers)
    " The cursor may  be moved to another  line when we use  the operator.  When
    " that  happens, it  may  cause  a redraw,  especially  when  we repeat  the
    " operator with the dot command.
    "
    " A redraw will erase the message, so we delay the report to be sure it will
    " always be visible.
    call timer_start(0, {-> s:report()})
endfu

fu s:prettify(number) abort "{{{1
    "              ┌ use scientific notation if the number is too big/small
    "              ├┐
    return printf('%g', a:number)->substitute('\.0\+$', '', '')
    "                                          ├────┘
    "                                          └ remove possible ending `.0`
    "
    "                                            `%g` does NOT remove it:
    "
    "                                                    123.0
    "
    "                                            ... because it characterizes a float.
endfu

fu s:product(cnt, raw_numbers) abort "{{{1
    let floats = copy(a:raw_numbers)->filter({_, v -> v =~# '[.]'})
    let integers = copy(a:raw_numbers)->filter({_, v -> v !~# '[.]'})

    " if there's only integers, no need to process the product
    " compute and return immediately
    if empty(floats)
        return eval(a:cnt ? join(a:raw_numbers, ' * ') : '0')
    endif

    "     ┌ used to compute the product of integers and floats separately
    "     │
    let l:Partial_product = { numbers -> eval(
        \     len(numbers) == 0
        \   ?     '1'
        \   : len(numbers) == 1
        \   ?     numbers[0]
        \   : join(numbers, ' * ')
        \ )}

    let integers_product = Partial_product(integers)
    let floats_product = Partial_product(floats)

    let significant_digits = (map(floats, {_, v ->
        \ substitute(v, '^0\+\|[.+-]', '', 'g')->strlen()}) + [10])->min()
        "                                                      │
        "                                                      └ never go above 10 significant digits

    let floats_product = significant_digits > 0
        \ ?        printf('%.*f', significant_digits, floats_product)
        \ :        string(floats_product)

    let floats_product = split(floats_product, '\zs')
    let i = 0
    for char in floats_product
        if char isnot# '-' && char isnot# '.'
            if significant_digits <= 0
                let floats_product[i] = '0'
            elseif significant_digits == 1
                " If the next digit after  the last significant digit is greater
                " than 4, round it up.  As an example, suppose we have a product
                " with 3 significant digits:
                "
                "           ┌ smaller than 4
                "           │
                "       1.232    →    1.23
                "       1.238    →    1.24
                "           │
                "           └ greater than 4
                let floats_product[i] = (eval(floats_product[i])
                    \ + (get(floats_product, i + 1, 0) <= 4 ? 0 : 1))
                    \ ->string()
            endif
            let significant_digits -= 1
        endif
        let i += 1
    endfor
    return (join(floats_product, '')->eval() * integers_product)->string()
endfu

fu math#put_metrics() abort "{{{1
    try
        if !exists('s:metrics')
            return 'echo "no metrics"'
        endif

        let choices =<< trim END
            Metrics
            1. all
            2. sum
            3. avg
            4. prod
            5. min
            6. max
            7. count
        END
        let choice = inputlist(choices)
        if choice >= 2 && choice <= 7
            let metrics =<< trim END
                sum
                avg
                prod
                min
                max
                count
            END
            let metrics = metrics[choice - 2]
            let output = s:metrics[metrics]
        elseif choice == 1
            let output = printf('sum: %s   avg: %s   prod: %s   min: %s   max: %s   count: %s',
                \ s:metrics.sum,
                \ s:metrics.avg,
                \ s:metrics.prod,
                \ s:metrics.min,
                \ s:metrics.max,
                \ s:metrics.count)
        else
            return ''
        endif
        call append('.', output)
    catch
        return s:Catch()
    endtry
endfu

fu s:report() abort "{{{1
    for a_metrics in ['sum', 'avg', 'prod', 'min', 'max', 'count']
        echon printf('%s: %s   ', a_metrics, s:metrics[a_metrics])
    endfor
endfu

fu s:sum_or_avg(cnt, raw_numbers, avg) abort "{{{1
    let sum = eval(a:cnt ? join(a:raw_numbers, ' + ') : '0')
    if a:avg
        let sum = (a:cnt != 0 ? 1.0 * sum / a:cnt : 0)
    endif

    " RULE: The result of a sum should be as accurate as the least accurate number.{{{
    "
    " When you add  2 numbers in math, A  and B, A being accurate  to P1 decimal
    " places,  and B  to  P2 decimal  places,  the result  must  be accurate  to
    " min(P1,P2) decimal places.
    "
    " http://mathforum.org/library/drmath/view/58335.html
    "
    " So, if we sum several numbers with different precisions, the result should
    " be as accurate as the least accurate number:
    "
    "     avg(1.2, 3.45) = 2.325    ✘
    "     avg(1.2, 3.45) = 2.3      ✔
    "}}}
    let decimal_places = (copy(a:raw_numbers)
        \ ->map({_, v -> matchstr(v, '\.\zs\d\+$')->strlen()}) + [10])->min()
        "                                                         │
        "                                                         └ never go above 10 digits after the decimal point

    return decimal_places > 0
        \ ?     printf('%.*f', decimal_places, sum)
        \ :     round(sum)->float2nr()->printf('%d')
endfu
