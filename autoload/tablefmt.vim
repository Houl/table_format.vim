" Vim global plugin - Makes range/selection into neatly formatted table
" File:		tablefmt.vim
" Last Change:	2017 Aug 06
" Version:	0.10
" Author:	(c) 2003, Michael Graz <mgraz.vim@plan10.com>
" Contrib:	Andy Wokula <anwoku@yahoo.de>
" License:	Vim License, see :h license

" History:
" 2017 Aug 06	multibyte support
"		some more Vim6 style code converted to Vim7
" 2015 Sep 18	make use of Vim7 features, support for UTF-8
"		format a list of strings
" 2012 Oct 14
" 2012 May 19	renamed variables
" 2009 Dec 19	fixed hasmapto(), added :sunmap
" 2009 Feb 12	changed plug maps (actually made them working!!)
" 2005 Sep 19	slightly modified by anwo

if exists('loaded_tablefmt') || &cp
    finish
endif
let loaded_tablefmt = 1

if v:version < 703
    " strwidth() is used
    echoerr 'tablefmt: Vim 7.3 is required'
    finish
endif

"----------------------------------------------------------------------
" Globals

" table mode 0 -- split at single spaces
" table mode 1 -- split at double spaces and tabs (tab is like a double space)

" table mode 0: least number of spaces for a field
" g:tablefmt_single_split_spaces = 1
if !exists('g:tablefmt_0_split')
    let g:tablefmt_0_split = 1
endif

" table mode 0: least number of spaces when joining fields:
" g:tablefmt_single_join_spaces = 1
if !exists('g:tablefmt_0_padding')
    let g:tablefmt_0_padding = 1
endif

" Table mode 1 -- split at double spaces and tabs
" g:tablefmt_double_split_spaces = 2
if !exists('g:tablefmt_1_split')
    let g:tablefmt_1_split = 2
endif

" g:tablefmt_double_join_spaces = 3
if !exists('g:tablefmt_1_padding')
    let g:tablefmt_1_padding = 2
endif

"----------------------------------------------------------------------
" Mappings

"if !hasmapto('<Plug>tablefmt_onespace')
"    map <Leader>t <Plug>tablefmt_onespace
"    ounmap <Leader>t|sunmap <Leader>t
"endif
"
"if !hasmapto('<Plug>tablefmt_twospaces')
"    map <Leader>T <Plug>tablefmt_twospaces
"    ounmap <Leader>T|sunmap <Leader>T
"endif

"----------------------------------------------------------------------
com! -bar -bang -range TableFmt :<line1>,<line2>call <sid>TablefmtCmd(<bang>0, 0)

" Internal Mappings:
nnoremap <script><silent> <Plug>(tablefmt-onespace)  :<SID>.,'}call <sid>TablefmtCmd(0, 0)<CR>
vnoremap         <silent> <Plug>(tablefmt-onespace)  "ty:call <sid>TablefmtCmd(0, 1)<CR>
nnoremap <script><silent> <Plug>(tablefmt-twospaces) :<SID>.,'}call <sid>TablefmtCmd(1, 0)<CR>
vnoremap         <silent> <Plug>(tablefmt-twospaces) "ty:call <sid>TablefmtCmd(1, 1)<CR>
" make it possible to accept a count (converted to a range) and provide a
" default range:
cnoremap <expr> <SID>.,'} getcmdpos()==1 ? ".,'}" : ""

func! tablefmt#Plug(what) "{{{
    return printf("\<Plug>(tablefmt-%s)", a:what)
endfunc "}}}


func! <Sid>TablefmtCmd(table_mode, visual_mode) range "{{{
    if a:table_mode == 0
	let space_split = g:tablefmt_0_split
	let space_padding = g:tablefmt_0_padding
    else
	let space_split = g:tablefmt_1_split
	let space_padding = g:tablefmt_1_padding
    endif
    if a:visual_mode == 0
	call tablefmt#Format(a:firstline, a:lastline, space_split, space_padding)
    else
	let line_start = a:firstline
	let line_end = line_start + strlen(substitute(@t, "[^\n]", "", "g"))
	if visualmode() == "\<C-V>"
	    " This is blockwise visual mode, so pass along the columns
	    let col_start = virtcol("'<")
	    let col_end = col_start + strpart(getregtype('t'), 1)
	    call tablefmt#Format(line_start, line_end, space_split, space_padding, 0, col_start, col_end)
	else
	    " Linewise visual, so do not pass columns
	    call tablefmt#Format(line_start, line_end-1, space_split, space_padding)
	endif
    endif
endfunc "}}}

"----------------------------------------------------------------------
" Main table functions
" Args:
"   line1
"   line2
"   space_split = 1
"   space_padding = space_split
"   max_field_length = 0
"   col_start = 0
"   col_end = 0  -- end of line

func! tablefmt#FormatRange(...) range "{{{
    call call("tablefmt#Format", [a:firstline, a:lastline] + a:000)
endfunc "}}}

func! tablefmt#Format(line_start, line_end, ...) "{{{
    let space_split = a:0>=1 && a:1>=2 ? a:1 : 1
    let space_padding = a:0>=2 ? a:2 : space_split
    let max_field_len = a:0>=3 ? a:3 : 0
    let col_start = a:0>=4 ? a:4 : 0
    let col_end = a:0>=5 ? a:5 : 0

    let field_count = 0		" number of fields found
    let least_indent = 1000	" amount to indent

    " force spaces in the text (one tab = two spaces):
    sil exec a:line_start.','.a:line_end.' s/\t/  /ge'

    " First Pass: determine
    "	* min indent
    "	* max field len for each column
    "	* number of fields
    let line_num = a:line_start
    while line_num <= a:line_end
	call s:Tokenize(line_num, space_split, col_start, col_end)
	if s:tkn_count == 0
	    " blank line
	    let line_num += 1
	    continue
	endif

	if s:tkn_indent < least_indent
	    let least_indent = s:tkn_indent
	endif

	let i = 0
	while i < s:tkn_count
	    " Get current max field length
	    if i >= field_count
		let max_len = 0
	    else
		let max_len = fld_{i}
	    endif

	    " Get current token length
	    let token_len = s:tkn_lengths[i]
	    if max_field_len > 0 && token_len > max_field_len
		let token_len = max_field_len
	    endif

	    " Should this length be saved?
	    if i >= field_count || token_len > max_len
		" This is the max token length seen so far for this field
		let fld_{i} = token_len
	    endif

	    " Update max number of fields seen
	    if i >= field_count
		let field_count = i + 1
	    endif

	    let i += 1
	endwhile

	let line_num += 1
    endwhile

    " At this point:
    " least_indent has the min indentation
    " field_count has the max field count
    " fld_0, fld_1, ... have the max field sizes

    " Determine length of result line
    let i = 0
    let line_len = 0
    while i < field_count
	let len = fld_{i}
	let line_len += len
	if i > 0
	    let line_len += space_padding
	endif
	let i += 1
    endwhile
    if line_len > col_end - col_start
	let pad_extra = space_padding
    elseif line_len < col_end - col_start
	let pad_extra = col_end - col_start - line_len
    else
	let pad_extra = 0
    endif

    " debugging
    if 0 "{{{
	echo "least_indent" least_indent
	echo "field_count" field_count
	let i = 0
	while i < field_count
	    let len = fld_{i}
	    echo "fld_" i len
	    let i += 1
	endwhile
	return
    endif "}}}

    " Blank string used for padding
    let blanks = repeat(" ", 200)

    " Build up indent string
    let indent_str = strpart(blanks, 1, least_indent)

    " Second Pass: perform alignment
    let line_num = a:line_start
    while line_num <= a:line_end
	call s:Tokenize(line_num, space_split, col_start, col_end)
	if s:tkn_count == 0
	    let line_num += 1
	    continue      " skip blank line
	endif

	" Start building string
	let str = indent_str

	let i = 0
	while i < s:tkn_count
	    " Retrieve token and length
	    let token_str = s:tkn_strings[i]
	    let token_len = s:tkn_lengths[i]

	    " Pad the token if it is not the last
	    if i+1 < s:tkn_count
		" Get max field length
		let fld_len = fld_{i}
		if fld_len > token_len
		    " Pad the token
		    let pad_len = fld_len - token_len
		    let pad_str = strpart(blanks, 1, pad_len)
		    let token_str .= pad_str
		endif
	    endif

	    " Add space between tokens
	    if i > 0
		let str .= strpart(blanks, 0, space_padding)
	    endif

	    " Add the token to the string
	    let str .= token_str

	    let i += 1
	endwhile

	" Get rest of line if just dealing with a fragment
	if col_start > 0
	    let str_len = strlen(str)
	    let str0 = getline(line_num)
	    let str = strpart(str0, 0, col_start-1) . str
	    if col_end > 0
		let pad_len = line_len - str_len + pad_extra
		let pad_str = strpart(blanks, 1, pad_len)
		let str .= pad_str . strpart(str0, col_end-1)
	    endif
	endif

	call setline(line_num, str)

	let line_num += 1
    endwhile

    if col_end > 0
	" Clean up any extra spaces added to the end of lines
	sil exec a:line_start.','.a:line_end.' substitute / \+$//e'
    endif

    unlet s:tkn_count s:tkn_indent s:tkn_lengths s:tkn_strings

    echomsg 'tablefmt: processed '.(a:line_end-a:line_start+1).' lines'
endfunc "}}}

"----------------------------------------------------------------------
" Split one line into tokens
"
" Input:
"   pattern_mode
"   0: tokens are complete words separated by a one or more spaces
"   1: tokens are groups of words separated by two or more spaces
" Output:
"   tkn_count: number of tokens found
"   tkn_indent: indentation of first token
"   tkn_str_0, tkn_str_1, ...: the actual tokens
"   tkn_len_0, tkn_len_1, ...: length of each token

func! s:Tokenize(line_num, space_split, col_start, col_end) "{{{
    let s:tkn_count = 0

    let str = getline(a:line_num)

    if a:col_start > 0 && a:col_end > 0
	let str = strpart(str, a:col_start-1, a:col_end-a:col_start)
    elseif a:col_start > 0
	let str = strpart(str, a:col_start-1)
    endif

    let s:tkn_indent = strlen(matchstr(str, '^\s*'))

    let str = substitute(str, '^\s\+', '', '')

    if a:space_split == 1
	let splitpat = ' \+'
    else
	let splitpat = '  \+'
    endif
    let s:tkn_strings = split(str, splitpat)
    let s:tkn_count = len(s:tkn_strings)
    let s:tkn_lengths = map(range(s:tkn_count), 'strwidth(s:tkn_strings[v:val])')
endfunc "}}}

" echo expand("<sfile>:t") "loaded"

" DEBUG:
com! -nargs=* -complete=command TablefmtLocal <args>
