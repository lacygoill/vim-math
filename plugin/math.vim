vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# Documentation {{{1

# A calculator can interpret math operators like `+`, `-`, `*`, `/`, but not our
# plugin.  This is *not* a calculator, like the `bc` shell command.
#
# The plugin merely installs an operator/command  to *analyse* a set of numbers,
# separated by spaces  or newlines.  It automatically adds  operators to compute
# different metrics.  So, there should be no  math operator in the text that the
# plugin analyses, *only* numbers.

# Command {{{1

com -bar -range AnalyseNumbers math#Ex(<line1>, <line2>)

# Mappings {{{1

nno <expr><unique> -m  math#op()
nno <expr><unique> -mm math#op() .. '_'
xno <expr><unique> -m  math#op()

nno <unique> "? <cmd>call math#putMetrics()<cr>
