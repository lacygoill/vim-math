vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# Init {{{1

import {Catch, Opfunc} from 'lg.vim'
import {Max, Min} from 'lg/math.vim'
const SID: string = execute('fu Opfunc')->matchstr('\C\<def\s\+\zs<SNR>\d\+_')

def GetNumPat(): string
    var sign: string = '[+-]\='
    var decimal: string = '\d\+\.\=\d*'
    var fraction: string = '\.\d\+'
    var exponent: string = '[eE]' .. sign .. '\d\+'
    return printf('^%s\%%(%s\|%s\)\%%(%s\)\=$', sign, decimal, fraction, exponent)
enddef

const NUM_PAT: string = GetNumPat()

# Interface {{{1
def math#op(): string #{{{2
    &opfunc = SID .. 'Opfunc'
    g:opfunc = {core: 'math#opCore'}
    return 'g@'
enddef

def math#opCore(_: any)
    var raw_numbers: list<any>
    var numbers: list<any>
    [raw_numbers, numbers] = ExtractData()
    CalculateMetrics(raw_numbers, numbers)
    # The cursor may  be moved to another  line when we use  the operator.  When
    # that  happens, it  may  cause  a redraw,  especially  when  we repeat  the
    # operator with the dot command.
    #
    # A redraw will erase the message, so we delay the report to be sure it will
    # always be visible.
    timer_start(0, () => Report())
enddef

def math#Ex(lnum1: number, lnum2: number) #{{{2
    var unnamed_save: dict<any> = getreginfo('"')
    var zero_save: dict<any> = getreginfo('0')
    try
        exe 'sil :' .. lnum1 .. ',' .. lnum2 .. 'y'
        math#opCore('')
    finally
        setreg('"', unnamed_save)
        setreg('0', zero_save)
    endtry
enddef

def math#putMetrics() #{{{2
    try
        if metrics == {}
            echo 'No metrics'
            return
        endif

        var choices: list<string> =<< trim END
            Metrics
            1. all
            2. sum
            3. avg
            4. prod
            5. min
            6. max
            7. count
        END
        var choice: number = inputlist(choices)
        var output: string
        if choice >= 2 && choice <= 7
            var what_did_we_choose: list<string> =<< trim END
                sum
                avg
                prod
                min
                max
                count
            END
            var chosen: string = what_did_we_choose[choice - 2]
            output = metrics[chosen]
        elseif choice == 1
            output = printf('sum: %s   avg: %s   prod: %s   min: %s   max: %s   count: %s',
                metrics.sum,
                metrics.avg,
                metrics.prod,
                metrics.min,
                metrics.max,
                metrics.count)
        else
            return
        endif
        append('.', output)
    catch
        Catch()
        return
    endtry
enddef
#}}}1
# Core {{{1
def CalculateMetrics(raw_numbers: list<string>, numbers: list<float>) #{{{2
    var cnt: number = len(numbers)

    metrics = {
          sum: SumOrAvg(cnt, raw_numbers, 0)->str2float(),
          avg: SumOrAvg(cnt, raw_numbers, 1)->str2float(),
          prod: Product(cnt, raw_numbers)->str2float(),
          min: Min(numbers),
          max: Max(numbers),
          count: cnt,
        }

    map(metrics, (_, v) => Prettify(v))
    #                      │
    #                      └ * scientific notation for big/small numbers
    #                        * remove possible ending `.0`
enddef

var metrics: dict<any>

def ExtractData(): list<list<any>> #{{{2
    var selection: string = getreg('"')
    #                                              ┌ default 2nd argument = \_s\+
    #                                              │
    var raw_numbers: list<string> = split(selection)
        ->filter((_, v) => v =~ NUM_PAT)
    # Vim's default coercion is good enough for integers but not for floats:{{{
    #
    #       echo '12' + 3
    #       15    ✔~
    #
    #       echo '1.2' + 3
    #       4     ✘~
    #
    # ... so we need to call `str2float()` to perform the right conversion, from
    # a string to the float it contains.
    #}}}
    var numbers: list<float> = mapnew(raw_numbers, (_, v) => str2float(v))
    return [raw_numbers, numbers]
enddef

def Prettify(number: any): string #{{{2
    #              ┌ use scientific notation if the number is too big/small
    #              ├┐
    return printf('%g', number)->substitute('\.0\+$', '', '')
    #                                        ├────┘
    #                                        └ remove possible ending `.0`
    #
    #                                          `%g` does NOT remove it:
    #
    #                                                  123.0
    #
    #                                          ... because it characterizes a float.
enddef

def Product(cnt: number, raw_numbers: list<string>): string #{{{2
    var floats: list<string> = copy(raw_numbers)->filter((_, v) => v =~ '[.]')
    var integers: list<string> = copy(raw_numbers)->filter((_, v) => v !~ '[.]')

    # if there's only integers, no need to process the product
    # compute and return immediately
    if empty(floats)
        return cnt != 0
            ? reduce(raw_numbers, (a, v) => a->str2nr() * v->str2nr(), 1)->string()
            : '0'
    endif

    var integers_product: number = reduce(integers, (a, v) => a->str2nr() * v->str2nr(), 1)
    var floats_product: float = reduce(floats, (a, v) => a * v->str2float(), 1.0)

    var significant_digits: number = (
        mapnew(floats, (_, v) =>
            substitute(v, '^0\+\|[.+-]', '', 'g')->strlen()
            # never go above 10 significant digits
        ) + [10]
    )->min()

    var string_float_product: string = significant_digits > 0
        ?        printf('%.*f', significant_digits, floats_product)
        :        string(floats_product)

    var splitted: list<string> = split(string_float_product, '\zs')
    var i: number = 0
    for char in splitted
        if char != '-' && char != '.'
            if significant_digits <= 0
                splitted[i] = '0'
            elseif significant_digits == 1
                # If the next digit after  the last significant digit is greater
                # than 4, round it up.  As an example, suppose we have a product
                # with 3 significant digits:
                #
                #           ┌ smaller than 4
                #           │
                #       1.232    →    1.23
                #       1.238    →    1.24
                #           │
                #           └ greater than 4
                splitted[i] = (eval(splitted[i])
                    + (get(splitted, i + 1, '')->str2nr() <= 4 ? 0 : 1))
                    ->string()
            endif
            significant_digits -= 1
        endif
        i += 1
    endfor
    return (join(splitted, '')->str2float() * integers_product)->string()
enddef

def Report() #{{{2
    for a_metrics in ['sum', 'avg', 'prod', 'min', 'max', 'count']
        echon printf('%s: %s   ', a_metrics, metrics[a_metrics])
    endfor
enddef

def SumOrAvg(cnt: number, raw_numbers: list<string>, avg: number): string #{{{2
    var sum: float = reduce(raw_numbers, (a, v) => a + v->str2float(), 0.0)
    if avg != 0
        sum = (cnt != 0 ? 1.0 * sum / cnt : 0.0)
    endif

    # RULE: The result of a sum should be as accurate as the least accurate number.{{{
    #
    # When you add  2 numbers in math, A  and B, A being accurate  to P1 decimal
    # places,  and B  to  P2 decimal  places,  the result  must  be accurate  to
    # min(P1,P2) decimal places.
    #
    # http://mathforum.org/library/drmath/view/58335.html
    #
    # So, if we sum several numbers with different precisions, the result should
    # be as accurate as the least accurate number:
    #
    #     avg(1.2, 3.45) = 2.325    ✘
    #     avg(1.2, 3.45) = 2.3      ✔
    #}}}
    var decimal_places: number = (mapnew(raw_numbers,
        (_, v) => matchstr(v, '\.\zs\d\+$')->strlen()) + [10])->min()
        #                                                 │
        #                                                 └ never go above 10 digits after the decimal point

    return decimal_places > 0
        ?     printf('%.*f', decimal_places, sum)
        :     round(sum)->float2nr()->printf('%d')
enddef
