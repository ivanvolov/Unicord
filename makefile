ta:
	clear && forge test -vv --match-contract Test
t:
	clear && forge test -vvvv --match-contract ALMTest --match-test "test_swap_price_up"
tl:
	clear && forge test -vv --match-contract ALMTest --match-test "test_swap_price_up"

spell:
	clear && cspell "**/*.*"