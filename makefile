test_all:
	clear && forge test -vv
test_all_verbose:
	clear && forge test -vvvv

spell:
	clear && cspell "**/*.*"