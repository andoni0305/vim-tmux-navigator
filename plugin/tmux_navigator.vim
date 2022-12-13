" Maps <C-h/j/k/l> to switch vim splits in the given direction. If there are
" no more windows in that direction, forwards the operation to tmux.
" Additionally, <C-\> toggles between last active vim splits/tmux panes.

if exists("g:loaded_tmux_navigator") || &cp || v:version < 700
  finish
endif
let g:loaded_tmux_navigator = 1
let g:yabai_integration = 1

let s:yabai_direction_from_direction = {'h': 'west', 'j': 'south', 'k': 'north', 'l': 'east'}

function! s:VimNavigate(direction)
  try
    execute 'wincmd ' . a:direction
  catch
    echohl ErrorMsg | echo 'E11: Invalid in command-line window; <CR> executes, CTRL-C quits: wincmd k' | echohl None
  endtry
endfunction

function! s:YabaiCommand(args)
  let cmd = 'yabai -m ' . a:args
  let l:x=&shellcmdflag
  let &shellcmdflag='-c'
  let retval=system(cmd)
  let &shellcmdflag=l:x
  return retval
endfunction

function! s:YabaiNavigate(direction)
     call s:YabaiCommand('window --focus ' . s:yabai_direction_from_direction[a:direction])
endfunction

function! s:YabaiAwareNavigate(direction)
    let nr = winnr()
    call s:VimNavigate(a:direction)
    let at_tab_page_edge = (nr == winnr())
    if l:at_tab_page_edge
         call s:YabaiNavigate(a:direction)
    endif
endfunction

if !get(g:, 'tmux_navigator_no_mappings', 0)
  noremap <silent> <c-h> :<C-U>TmuxNavigateLeft<cr>
  noremap <silent> <c-j> :<C-U>TmuxNavigateDown<cr>
  noremap <silent> <c-k> :<C-U>TmuxNavigateUp<cr>
  noremap <silent> <c-l> :<C-U>TmuxNavigateRight<cr>
  noremap <silent> <c-\> :<C-U>TmuxNavigatePrevious<cr>
endif

if empty($TMUX)
    if exists("g:yabai_integration")
        command! TmuxNavigateLeft call s:YabaiAwareNavigate('h')
        command! TmuxNavigateDown call s:YabaiAwareNavigate('j')
        command! TmuxNavigateUp call s:YabaiAwareNavigate('k')
        command! TmuxNavigateRight call s:YabaiAwareNavigate('l')
    else
        command! TmuxNavigateLeft call s:VimNavigate('h')
        command! TmuxNavigateDown call s:VimNavigate('j')
        command! TmuxNavigateUp call s:VimNavigate('k')
        command! TmuxNavigateRight call s:VimNavigate('l')

    endif
    command! TmuxNavigatePrevious call s:VimNavigate('p')

    finish
endif



command! TmuxNavigateLeft call s:TmuxAwareNavigate('h')
command! TmuxNavigateDown call s:TmuxAwareNavigate('j')
command! TmuxNavigateUp call s:TmuxAwareNavigate('k')
command! TmuxNavigateRight call s:TmuxAwareNavigate('l')
command! TmuxNavigatePrevious call s:TmuxAwareNavigate('p')

if !exists("g:tmux_navigator_save_on_switch")
  let g:tmux_navigator_save_on_switch = 0
endif

if !exists("g:tmux_navigator_disable_when_zoomed")
  let g:tmux_navigator_disable_when_zoomed = 0
endif

if !exists("g:tmux_navigator_preserve_zoom")
  let g:tmux_navigator_preserve_zoom = 0
endif

if !exists("g:tmux_navigator_no_wrap")
  let g:tmux_navigator_no_wrap = 0
endif


let s:pane_position_from_direction = {'h': 'left', 'j': 'bottom', 'k': 'top', 'l': 'right'}

function! s:TmuxOrTmateExecutable()
  return (match($TMUX, 'tmate') != -1 ? 'tmate' : 'tmux')
endfunction

function! s:TmuxVimPaneIsZoomed()
  return s:TmuxCommand("display-message -p '#{window_zoomed_flag}'") == 1
endfunction

function! s:TmuxSocket()
  " The socket path is the first value in the comma-separated list of $TMUX.
  return split($TMUX, ',')[0]
endfunction

function! s:TmuxCommand(args)
  let cmd = s:TmuxOrTmateExecutable() . ' -S ' . s:TmuxSocket() . ' ' . a:args
  let l:x=&shellcmdflag
  let &shellcmdflag='-c'
  let retval=system(cmd)
  let &shellcmdflag=l:x
  return retval
endfunction

function! s:TmuxCheckForPaneInDirection(direction)
    return s:TmuxCommand('display-message -p "#{pane_at_' . s:pane_position_from_direction[a:direction] . '}"')
endfunction

function! s:TmuxNavigatorProcessList()
  echo s:TmuxCommand("run-shell 'ps -o state= -o comm= -t ''''#{pane_tty}'''''")
endfunction
command! TmuxNavigatorProcessList call s:TmuxNavigatorProcessList()

let s:tmux_is_last_pane = 0
augroup tmux_navigator
  au!
  autocmd WinEnter * let s:tmux_is_last_pane = 0
augroup END

function! s:NeedsVitalityRedraw()
  return exists('g:loaded_vitality') && v:version < 704 && !has("patch481")
endfunction

function! s:ShouldForwardNavigationBackToTmux(tmux_last_pane, at_tab_page_edge)
  if g:tmux_navigator_disable_when_zoomed && s:TmuxVimPaneIsZoomed()
    return 0
  endif
  return a:tmux_last_pane || a:at_tab_page_edge
endfunction

function! s:TmuxAwareNavigate(direction)
  let nr = winnr()
  let tmux_last_pane = (a:direction == 'p' && s:tmux_is_last_pane)
  if !tmux_last_pane
    call s:VimNavigate(a:direction)
  endif
  let at_tab_page_edge = (nr == winnr())
  " Forward the switch panes command to tmux if:
  " a) we're toggling between the last tmux pane;
  " b) we tried switching windows in vim but it didn't have effect.
  if s:ShouldForwardNavigationBackToTmux(tmux_last_pane, at_tab_page_edge)
    if g:tmux_navigator_save_on_switch == 1
      try
        update " save the active buffer. See :help update
      catch /^Vim\%((\a\+)\)\=:E32/ " catches the no file name error
      endtry
    elseif g:tmux_navigator_save_on_switch == 2
      try
        wall " save all the buffers. See :help wall
      catch /^Vim\%((\a\+)\)\=:E141/ " catches the no file name error
      endtry
    endif
    " if yabai is enabled jump out of vim and do a yabai jump in direction
    let is_pane_in_direction = s:TmuxCheckForPaneInDirection(a:direction) == 0
    if g:yabai_integration == 1 && l:is_pane_in_direction != 1
        silent call s:YabaiNavigate(a:direction)
        return
    endif

    let args = 'select-pane -t ' . shellescape($TMUX_PANE) . ' -' . tr(a:direction, 'phjkl', 'lLDUR')

    if g:tmux_navigator_preserve_zoom == 1
      let l:args .= ' -Z'
    endif
    if g:tmux_navigator_no_wrap == 1
      let args = 'if -F "#{pane_at_' . s:pane_position_from_direction[a:direction] . '}" "" "' . args . '"'
    endif
    silent call s:TmuxCommand(args)
    if s:NeedsVitalityRedraw()
      redraw!
    endif
    let s:tmux_is_last_pane = 1
  else
    let s:tmux_is_last_pane = 0
  endif
endfunction
