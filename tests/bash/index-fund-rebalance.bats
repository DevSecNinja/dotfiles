#!/usr/bin/env bats
# Tests for index_fund_rebalance fish function

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	FUNCTION_PATH="$REPO_ROOT/home/dot_config/fish/functions/index_fund_rebalance.fish"
	export FUNCTION_PATH
}

run_fn() {
	fish --no-config -c "source '$FUNCTION_PATH'; index_fund_rebalance $*"
}

@test "index_fund_rebalance: function file exists" {
	[ -f "$FUNCTION_PATH" ]
}

@test "index_fund_rebalance: function file has valid syntax" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish -n "$FUNCTION_PATH"
	[ "$status" -eq 0 ]
}

@test "index_fund_rebalance: help option displays usage" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: index_fund_rebalance" ]]
	[[ "$output" =~ "--world" ]]
	[[ "$output" =~ "--invest" ]]
}

@test "index_fund_rebalance: short help option works" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: index_fund_rebalance" ]]
}

@test "index_fund_rebalance: fails with too few arguments" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn 100 200
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Expected 3 amounts" ]]
}

@test "index_fund_rebalance: fails with too many arguments" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn 100 200 300 400
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Expected 3 amounts" ]]
}

@test "index_fund_rebalance: rejects non-numeric amount" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn 100 abc 300
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Amounts must be non-negative numbers" ]]
}

@test "index_fund_rebalance: rejects negative amount" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn 100 -50 300
	[ "$status" -ne 0 ]
}

@test "index_fund_rebalance: rejects zero holdings with no investment" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn 0 0 0
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Nothing to allocate" ]]
}

@test "index_fund_rebalance: rejects invalid invest amount" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn --invest foo 7800 1200 1000
	[ "$status" -eq 1 ]
	[[ "$output" =~ "--invest amount must be a non-negative number" ]]
}

@test "index_fund_rebalance: rejects percentages that do not sum to 100" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn --world-pct 80 --em-pct 12 --smallcap-pct 10 7800 1200 1000
	[ "$status" -eq 1 ]
	[[ "$output" =~ "must sum to 100" ]]
}

@test "index_fund_rebalance: on-target holdings all HOLD" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn 7800 1200 1000
	[ "$status" -eq 0 ]
	hold_lines=$(echo "$output" | grep -c "HOLD")
	[ "$hold_lines" -eq 3 ]
}

@test "index_fund_rebalance: verdict says on target when within 1 percentage point" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn 7800 1200 1000
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Verdict: on target" ]]
	[[ "$output" =~ "no need to rebalance" ]]
}

@test "index_fund_rebalance: verdict says off target when drift exceeds 1 point" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn 9000 500 500
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Verdict: off target" ]]
	[[ "$output" =~ "rebalance as shown above" ]]
}

@test "index_fund_rebalance: default buy-only keeps overweight fund and buys others" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn 9000 500 500
	[ "$status" -eq 0 ]
	# World is overweight; buy-only never sells it.
	[[ ! "$output" =~ "SELL" ]]
	[[ "$output" =~ "NT World Screened" ]]
	[[ "$output" =~ "HOLD" ]]
	[[ "$output" =~ "BUY" ]]
	[[ "$output" =~ "Buy-only top-up" ]]
}

@test "index_fund_rebalance: buy-only computes the fresh money needed" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	# World 9000 at 78% forces total 9000/0.78 = 11538.46; need 1538.46 fresh.
	run run_fn 9000 500 500
	[ "$status" -eq 0 ]
	[[ "$output" =~ "11538.46" ]]
	[[ "$output" =~ "1538.46" ]]
}

@test "index_fund_rebalance: --allow-sell sells overweight, buys underweight" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn --allow-sell 9000 500 500
	[ "$status" -eq 0 ]
	[[ "$output" =~ "NT World Screened" ]]
	[[ "$output" =~ "SELL €1200" ]]
	[[ "$output" =~ "BUY  €700" ]]
	[[ "$output" =~ "BUY  €500" ]]
}

@test "index_fund_rebalance: investing fresh money is buy-only" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn --allow-sell --invest 1000 7800 1200 1000
	[ "$status" -eq 0 ]
	[[ ! "$output" =~ "SELL" ]]
	[[ "$output" =~ "BUY  €780" ]]
	[[ "$output" =~ "BUY  €120" ]]
	[[ "$output" =~ "BUY  €100" ]]
	[[ "$output" =~ "new total: €11000" ]]
}

@test "index_fund_rebalance: shows default fund names and targets" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn 7800 1200 1000
	[ "$status" -eq 0 ]
	[[ "$output" =~ "NT World Screened" ]]
	[[ "$output" =~ "NT Emerging Market Screened" ]]
	[[ "$output" =~ "NT World Small Cap Low Carbon" ]]
	[[ "$output" =~ "78%" ]]
	[[ "$output" =~ "12%" ]]
	[[ "$output" =~ "10%" ]]
}

@test "index_fund_rebalance: custom currency symbol is used" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn --currency '£' 9000 500 500
	[ "$status" -eq 0 ]
	[[ "$output" =~ "£" ]]
	[[ ! "$output" =~ "€" ]]
}

@test "index_fund_rebalance: custom target percentages are honoured" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	# 60/30/10 on a 10000 total -> targets 6000/3000/1000
	run run_fn --world-pct 60 --em-pct 30 --smallcap-pct 10 6000 3000 1000
	[ "$status" -eq 0 ]
	hold_lines=$(echo "$output" | grep -c "HOLD")
	[ "$hold_lines" -eq 3 ]
}

@test "index_fund_rebalance: named amount flags work" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn --allow-sell --world 9000 --em 500 --smallcap 500
	[ "$status" -eq 0 ]
	[[ "$output" =~ "SELL €1200" ]]
	[[ "$output" =~ "BUY  €700" ]]
	[[ "$output" =~ "BUY  €500" ]]
}

@test "index_fund_rebalance: named amounts can be given in any order" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn --allow-sell --smallcap 500 --world 9000 --em 500
	[ "$status" -eq 0 ]
	[[ "$output" =~ "SELL €1200" ]]
}

@test "index_fund_rebalance: --sc is an alias for --smallcap" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn --allow-sell --world 9000 --em 500 --sc 500
	[ "$status" -eq 0 ]
	[[ "$output" =~ "SELL €1200" ]]
	[[ "$output" =~ "BUY  €700" ]]
	[[ "$output" =~ "BUY  €500" ]]
}

@test "index_fund_rebalance: --sc and --smallcap together are rejected" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn --world 9000 --em 500 --smallcap 500 --sc 500
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Use either --smallcap or --sc" ]]
}

@test "index_fund_rebalance: --sc-pct overrides the small cap target" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn --world-pct 70 --em-pct 15 --sc-pct 15 7800 1200 1000
	[ "$status" -eq 0 ]
	[[ "$output" =~ "15%" ]]
}

@test "index_fund_rebalance: partial named amounts are rejected" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn --world 9000 --em 500
	[ "$status" -eq 1 ]
	[[ "$output" =~ "provide all of --world, --em and --smallcap" ]]
}

@test "index_fund_rebalance: mixing named and positional amounts is rejected" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn --world 9000 --em 500 --smallcap 500 1000
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Do not mix named amounts with positional" ]]
}
