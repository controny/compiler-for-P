## Changes
** Scanner **
1. Set corresponding `yylval` before returning tokens.
2. Detect `Opt_D`.
** Parser **
1. Use pseudo-variable to present the value returned by the actions.
2. Add some auxiliary global variables and functions.

## Abilities
* Construct symbol tables and check whether there is any redeclaration.

## Platform
Linux

## How to run
```
make
./parser [input file]
```