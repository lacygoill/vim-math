if exists('g:autoloaded_math')
    finish
endif
let g:autoloaded_math = 1

" Init {{{1

fu s:get_num_pat() abort
    let sign     = '[+-]\='
    let decimal  = '\d\+\.\=\d*'
    let fraction = '\.\d\+'
    let exponent = '[eE]'..sign..'\d\+'
    return printf('^%s\%%(%s\|%s\)\%%(%s\)\=$', sign, decimal, fraction, exponent)
endfu

const s:NUM_PAT = s:get_num_pat()

fu s:analyse() abort "{{{1
    let [raw_numbers, numbers] = s:extract_data()
    call s:calculate_metrics(raw_numbers, numbers)
    " The cursor may be moved to another line when we use the operator.
    " When that  happens, it may cause  a redraw, especially when  we repeat the
    " operator with the dot command.
    "
    " A redraw will erase the message, so we delay the report to be sure it will
    " always be visible.
    call timer_start(0, {_ -> s:report()})
endfu

fu s:calculate_metrics(raw_numbers, numbers) abort "{{{1
    let [raw_numbers, numbers] = [a:raw_numbers, a:numbers]

    let cnt = len(numbers)

    let s:metrics = {
    \                 'sum'   : str2float(s:sum_or_avg(cnt, raw_numbers, 0)),
    \                 'avg'   : str2float(s:sum_or_avg(cnt, raw_numbers, 1)),
    \                 'prod'  : str2float(s:product(cnt, raw_numbers)),
    \                 'min'   : lg#math#min(numbers),
    \                 'max'   : lg#math#max(numbers),
    \                 'count' : cnt,
    \               }

    call map(s:metrics, {_,v -> s:prettify(v)})
    "                             │
    "                             └ * scientific notation for big/small numbers
    "                               * remove possible ending `.0`
endfu

fu s:extract_data() abort "{{{1
    let selection = getreg('"')
    "                                       ┌ default 2nd argument = \_s\+
    "                                       │
    let raw_numbers = filter(split(selection), {_,v -> v =~# s:NUM_PAT})
    let numbers     = map(copy(raw_numbers), {_,v -> str2float(v)})
    "                                                │
    "                                                └ Vim's default coercion is good enough for integers
    "                                                  but not for floats:
    "
    "                                                  echo '12' + 3
    "                                                  15    ✔~
    "
    "                                                  echo '1.2' + 3
    "                                                  4     ✘~
    "
    "                                            … so we need to call `str2float()` to perform the right
    "                                            conversion, from a string to the float it contains.
    return [raw_numbers, numbers]
endfu

fu math#op(type, ...) abort "{{{1
    let cb_save  = &cb
    let sel_save = &selection
    let reg_save = ['"', getreg('"'), getregtype('"')]
    try
        set cb-=unnamed cb-=unnamedplus
        set selection=inclusive

        if a:type is# 'char'
            sil norm! `[v`]y
        elseif a:type is# 'line'
            sil norm! '[V']y
        elseif a:type is# 'block'
            sil exe "norm! `[\<c-v>`]y"
        elseif a:type is# 'vis'
            sil norm! gvy
        elseif a:type is# 'Ex'
            sil exe a:1..','..a:2..'y'
        else
            return ''
        endif
        call s:analyse()
    catch
        return lg#catch_error()
    finally
        let &cb  = cb_save
        let &sel = sel_save
        call call('setreg', reg_save)
    endtry
endfu

fu s:prettify(number) abort "{{{1
    "                         ┌ use scientific notation if the number is too big/small
    "                         ├┐
    return substitute(printf('%g', a:number), '\.0\+$', '', '')
    "                                          ├────┘
    "                                          └ remove possible ending `.0`
    "
    "                                            `%g` does NOT remove it:
    "
    "                                                    123.0
    "
    "                                            … because it characterizes a float.
endfu

fu s:product(cnt, raw_numbers) abort "{{{1
    let floats   = filter(copy(a:raw_numbers), {_,v -> v =~# '[.]'})
    let integers = filter(copy(a:raw_numbers), {_,v -> v !~# '[.]'})

    " if there's only integers, no need to process the product
    " compute and return immediately
    if empty(floats)
        return eval(a:cnt ? join(a:raw_numbers, ' * ') : '0')
    endif

    "     ┌ used to compute the product of integers and floats separately
    "     │
    let l:Partial_product = { numbers -> eval(
    \                                            len(numbers) == 0
    \                                          ?     '1'
    \                                          : len(numbers) == 1
    \                                          ?     numbers[0]
    \                                          : join(numbers, ' * ')
    \                                        )
    \                       }

    let integers_product = l:Partial_product(integers)
    let floats_product   = l:Partial_product(floats)

    let significant_digits = min(map(floats,
        \ {_,v -> strlen(substitute(v, '^0\+\|[.+-]', '', 'g'))}) + [10])
        "                                                         │
        "                                                         └ never go above 10 significant digits

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
                " than 4, round it up. As an  example, suppose we have a product
                " with 3 significant digits:
                "
                "           ┌ smaller than 4
                "           │
                "       1.232    →    1.23
                "       1.238    →    1.24
                "           │
                "           └ greater than 4
                let floats_product[i] = string(eval(floats_product[i])+(get(floats_product, i+1, 0) <= 4
                \                                                       ?    0
                \                                                       :    1))
            endif
            let significant_digits -= 1
        endif
        let i += 1
    endfor
    return string(eval(join(floats_product, '')) * integers_product)
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
            \                    s:metrics.sum,
            \                    s:metrics.avg,
            \                    s:metrics.prod,
            \                    s:metrics.min,
            \                    s:metrics.max,
            \                    s:metrics.count)
        else
            return ''
        endif
        call append('.', output)
    catch
        return lg#catch_error()
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
    let decimal_places = min(map(copy(a:raw_numbers),
        \     {_,v -> strlen(matchstr(v, '\.\zs\d\+$'))}) + [10])
        "                                                    │
        "                                                    └ never go above 10 digits after the decimal point

    return decimal_places > 0
       \ ?     printf('%.*f', decimal_places, sum)
       \ :     printf('%d', float2nr(round(sum)))
endfu
