syntax on
set number	        " Show line numbers
set linebreak	        " Break lines at word (requires Wrap lines)
set showbreak=↳	        " Wrap-broken line prefix
"set textwidth=100	" Line wrap (number of cols)
set showmatch	        " Highlight matching brace
set visualbell	        " Use visual bell (no beeping)
set mouse=a
 
set hlsearch	        " Highlight all search results
set smartcase	        " Enable smart-case search
set ignorecase	        " Always case-insensitive
set incsearch	        " Searches for strings incrementally
 
set autoindent	        " Auto-indent new lines
set expandtab	        " Use spaces instead of tabs
set shiftwidth=4        " Number of auto-indent spaces
set smartindent	        " Enable smart-indent
set smarttab	        " Enable smart-tabs
set softtabstop=4       " Number of spaces per Tab
 
"" Advanced
set ruler	        " Show row and column ruler information
 
set autochdir	        " Change working directory to open buffer
set autowriteall	" Auto-write all file changes
 
set undolevels=1000	        " Number of undo levels
set backspace=indent,eol,start	" Backspace behaviour

autocmd Filetype html setlocal ts=2 sts=2 sw=2
autocmd Filetype ruby setlocal ts=2 sts=2 sw=2
"" Java Script
autocmd FileType javascript set formatprg=prettier\ --stdin
autocmd Filetype javascript setlocal ts=2 sts=2 sw=2

"" Golang
autocmd Filetype go setlocal ts=4 sts=4 sw=2
 
"" Plugins 
call plug#begin('~/.local/share/nvim/plugged')

Plug 'tpope/vim-sensible'
Plug 'fatih/vim-go'
Plug 'vim-scripts/L9'
Plug 'vim-scripts/FuzzyFinder'
Plug 'reedes/vim-pencil'

" On Demand
Plug 'scrooloose/nerdtree', { 'on': 'NERDTreeToggle' }

call plug#end() 

augroup pencil
  autocmd!
  autocmd FileType markdown,mkd call pencil#init()
augroup END
