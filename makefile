ta:
	clear && forge test -vv --match-contract Test

t:
	clear && forge test -vvvv --match-contract ALMTest --match-test "test_swap_price_down"
tl:
	clear && forge test -vv --match-contract ALMTest --match-test "test_swap_price_down"

spell:
	clear && cspell "**/*.*"