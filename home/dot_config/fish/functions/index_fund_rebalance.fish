function index_fund_rebalance --description "Show what to buy/sell to rebalance index funds to a target spread"
    # index_fund_rebalance - Rebalance index fund holdings to a target spread
    #
    # Given the current value of each holding, calculates how much to BUY (and,
    # with --allow-sell, SELL) of each fund to reach a target allocation.
    #
    # Default mode is BUY-ONLY: it keeps every current holding and only buys
    # into the underweight funds, computing the minimum fresh money needed so
    # the spread reaches target without selling anything. Pass --allow-sell to
    # instead rebalance the existing money exactly (which may sell the
    # overweight fund). Pass --invest to add a specific lump sum of fresh money.
    #
    # Default spread (override with --world-pct/--em-pct/--smallcap-pct):
    #   NT World Screened              78%
    #   NT Emerging Market Screened    12%
    #   NT World Small Cap Low Carbon  10%
    #
    # Usage: index_fund_rebalance [OPTIONS] [WORLD EM SMALLCAP]
    #
    # Amounts (current holdings) can be given by name or as 3 positional values:
    #   index_fund_rebalance --world 9000 --em 500 --sc 500
    #   index_fund_rebalance 9000 500 500
    #
    # Arguments:
    #   WORLD       Current value of NT World Screened
    #   EM          Current value of NT Emerging Market Screened
    #   SMALLCAP    Current value of NT World Small Cap Low Carbon
    #
    # Options:
    #       --world AMOUNT        Current value of NT World Screened
    #       --em AMOUNT           Current value of NT Emerging Market Screened
    #       --smallcap, --sc AMOUNT  Current value of NT World Small Cap Low Carbon
    #       --allow-sell          Rebalance exactly, selling overweight funds
    #   -i, --invest AMOUNT       Fresh money to add before rebalancing (default 0)
    #   -c, --currency SYM        Currency symbol for output (default €)
    #       --world-pct PCT       Target % for NT World Screened (default 78)
    #       --em-pct PCT          Target % for NT Emerging Market Screened (default 12)
    #       --smallcap-pct, --sc-pct PCT  Target % for NT World Small Cap (default 10)
    #   -h, --help                Show this help message and exit
    #
    # Examples:
    #   index_fund_rebalance 9000 500 500            # buy-only top-up (default)
    #   index_fund_rebalance --allow-sell 9000 500 500   # exact rebalance, may sell
    #   index_fund_rebalance --invest 1000 7800 1200 1000

    argparse --name=index_fund_rebalance h/help 'i/invest=' 'c/currency=' 'world=' 'em=' 'smallcap=' 'sc=' 'world-pct=' 'em-pct=' 'smallcap-pct=' 'sc-pct=' allow-sell -- $argv
    or return 1

    # --sc / --sc-pct are aliases for --smallcap / --smallcap-pct.
    if set -q _flag_sc
        if set -q _flag_smallcap
            echo "❌ Use either --smallcap or --sc, not both" >&2
            return 1
        end
        set _flag_smallcap $_flag_sc
    end
    if set -q _flag_sc_pct
        if set -q _flag_smallcap_pct
            echo "❌ Use either --smallcap-pct or --sc-pct, not both" >&2
            return 1
        end
        set _flag_smallcap_pct $_flag_sc_pct
    end

    if set -q _flag_help
        echo "Usage: index_fund_rebalance [OPTIONS] [WORLD EM SMALLCAP]"
        echo ""
        echo "Show what to buy/sell to rebalance index funds to a target spread."
        echo ""
        echo "Provide current holdings by name or as 3 positional values:"
        echo "  index_fund_rebalance --world 9000 --em 500 --sc 500"
        echo "  index_fund_rebalance 9000 500 500"
        echo ""
        echo "Arguments:"
        echo "  WORLD       Current value of NT World Screened"
        echo "  EM          Current value of NT Emerging Market Screened"
        echo "  SMALLCAP    Current value of NT World Small Cap Low Carbon"
        echo ""
        echo "Options:"
        echo "      --world AMOUNT        Current value of NT World Screened"
        echo "      --em AMOUNT           Current value of NT Emerging Market Screened"
        echo "      --smallcap, --sc AMOUNT  Current value of NT World Small Cap Low Carbon"
        echo "      --allow-sell          Rebalance exactly, selling overweight funds"
        echo "  -i, --invest AMOUNT       Fresh money to add before rebalancing (default 0)"
        echo "  -c, --currency SYM        Currency symbol for output (default €)"
        echo "      --world-pct PCT       Target % for NT World Screened (default 78)"
        echo "      --em-pct PCT          Target % for NT Emerging Market Screened (default 12)"
        echo "      --smallcap-pct, --sc-pct PCT  Target % for NT World Small Cap (default 10)"
        echo "  -h, --help                Show this help message"
        echo ""
        echo "Modes:"
        echo "  Default is BUY-ONLY: keep every holding and buy into the underweight"
        echo "  funds (the overweight fund holds). Use --allow-sell for an exact"
        echo "  rebalance that may sell down the overweight fund."
        echo ""
        echo "Examples:"
        echo "  index_fund_rebalance 9000 500 500"
        echo "  index_fund_rebalance --allow-sell 9000 500 500"
        echo "  index_fund_rebalance --invest 1000 7800 1200 1000"
        return 0
    end

    set -l names "NT World Screened" "NT Emerging Market Screened" "NT World Small Cap Low Carbon"

    # Resolve current holdings: named flags (--world/--em/--smallcap) take
    # precedence; otherwise fall back to 3 positional values.
    set -l named_count 0
    set -q _flag_world; and set named_count (math "$named_count + 1")
    set -q _flag_em; and set named_count (math "$named_count + 1")
    set -q _flag_smallcap; and set named_count (math "$named_count + 1")

    set -l amounts
    if test $named_count -gt 0
        if test $named_count -ne 3
            echo "❌ When naming amounts, provide all of --world, --em and --smallcap" >&2
            return 1
        end
        if test (count $argv) -ne 0
            echo "❌ Do not mix named amounts with positional amounts" >&2
            return 1
        end
        set amounts $_flag_world $_flag_em $_flag_smallcap
    else
        if test (count $argv) -ne 3
            echo "❌ Expected 3 amounts: either WORLD EM SMALLCAP positionally," >&2
            echo "   or named with --world, --em and --smallcap." >&2
            echo "   Use --help for usage information." >&2
            return 1
        end
        set amounts $argv[1] $argv[2] $argv[3]
    end

    # Validate amounts are non-negative numbers
    for amount in $amounts
        if not string match -qr '^[0-9]+(\.[0-9]+)?$' -- $amount
            echo "❌ Amounts must be non-negative numbers (got '$amount')" >&2
            return 1
        end
    end

    # Target percentages
    set -l pct_world 78
    set -l pct_em 12
    set -l pct_sc 10
    set -q _flag_world_pct; and set pct_world $_flag_world_pct
    set -q _flag_em_pct; and set pct_em $_flag_em_pct
    set -q _flag_smallcap_pct; and set pct_sc $_flag_smallcap_pct

    for pct in $pct_world $pct_em $pct_sc
        if not string match -qr '^[0-9]+(\.[0-9]+)?$' -- $pct
            echo "❌ Target percentages must be non-negative numbers (got '$pct')" >&2
            return 1
        end
    end

    set -l pct_sum (math "$pct_world + $pct_em + $pct_sc")
    if test (math -s2 "abs($pct_sum - 100)") -gt 0.01
        echo "❌ Target percentages must sum to 100 (got $pct_sum)" >&2
        return 1
    end
    set -l percentages $pct_world $pct_em $pct_sc

    # Fresh money to invest
    set -l invest 0
    if set -q _flag_invest
        if not string match -qr '^[0-9]+(\.[0-9]+)?$' -- $_flag_invest
            echo "❌ --invest amount must be a non-negative number (got '$_flag_invest')" >&2
            return 1
        end
        set invest $_flag_invest
    end

    set -l currency €
    set -q _flag_currency; and set currency $_flag_currency

    set -l buy_only true
    set -q _flag_allow_sell; and set buy_only false

    # Totals
    set -l current_total (math "$amounts[1] + $amounts[2] + $amounts[3]")

    # Determine the portfolio total (T) to allocate against.
    set -l total
    if test "$buy_only" = true
        # Buy-only: never sell. The smallest total that keeps every current
        # holding at/below its target is max_i(current_i / target_fraction_i).
        # A larger --invest simply raises that floor.
        set -l t_min 0
        for i in 1 2 3
            set -l c $amounts[$i]
            set -l p $percentages[$i]
            if test $p -le 0
                if test $c -gt 0
                    echo "❌ Buy-only cannot reach a 0% target for $names[$i] while it holds $currency$c." >&2
                    echo "   Use --allow-sell to sell it down." >&2
                    return 1
                end
                continue
            end
            set -l ratio (math "$c * 100 / $p")
            if test $ratio -gt $t_min
                set t_min $ratio
            end
        end
        set total (math "max($t_min, $current_total + $invest)")
    else
        set total (math "$current_total + $invest")
    end

    if test $total -le 0
        echo "❌ Nothing to allocate: provide holdings and/or --invest" >&2
        return 1
    end

    echo "📊 Index fund rebalance"
    echo "-----------------------"
    printf '%-32s %12s %8s %12s %8s   %s\n' "Fund" "Current" "Cur %" "Target" "Tgt %" "Action"

    set -l max_drift 0
    for i in 1 2 3
        set -l current $amounts[$i]
        set -l pct $percentages[$i]
        set -l target (math -s2 "$total * $pct / 100")
        set -l delta (math -s2 "$target - $current")

        set -l cur_pct 0.0
        if test $current_total -gt 0
            set cur_pct (math -s1 "$current / $current_total * 100")
        end

        set -l drift (math -s2 "abs($cur_pct - $pct)")
        if test $drift -gt $max_drift
            set max_drift $drift
        end

        set -l action
        if test $delta -gt 0.005
            set action (printf 'BUY  %s%s' $currency $delta)
        else if test $delta -lt -0.005
            set action (printf 'SELL %s%s' $currency (math -s2 "0 - $delta"))
        else
            set action HOLD
        end

        printf '%-32s %12s %7s%% %12s %7s%%   %s\n' \
            $names[$i] \
            (printf '%s%s' $currency (math -s2 "$current")) \
            $cur_pct \
            (printf '%s%s' $currency $target) \
            $pct \
            $action
    end

    echo "-----------------------"
    set -l added (math -s2 "$total - $current_total")
    if test "$buy_only" = true
        printf 'Buy-only top-up: invest %s%s of fresh money (no selling), new total %s%s\n' \
            $currency $added \
            $currency (math -s2 "$total")
    else if test $invest -gt 0
        printf 'Current total: %s%s  +  invest: %s%s  =  new total: %s%s\n' \
            $currency (math -s2 "$current_total") \
            $currency (math -s2 "$invest") \
            $currency (math -s2 "$total")
    else
        printf 'Total: %s%s (rebalancing existing money; buys and sells net to zero)\n' \
            $currency (math -s2 "$total")
    end

    # Verdict: if every fund is within 1 percentage point of its target, the
    # portfolio is close enough that rebalancing is not worth it.
    if test $max_drift -lt 1
        printf '✅ Verdict: on target (max drift %s%% < 1%%) — no need to rebalance.\n' $max_drift
    else
        printf '⚠️  Verdict: off target (max drift %s%%) — rebalance as shown above.\n' $max_drift
    end

    return 0
end

# Completions for index_fund_rebalance
complete -c index_fund_rebalance -f
complete -c index_fund_rebalance -s h -l help -d "Show help message"
complete -c index_fund_rebalance -l world -d "Current value of NT World Screened"
complete -c index_fund_rebalance -l em -d "Current value of NT Emerging Market Screened"
complete -c index_fund_rebalance -l smallcap -d "Current value of NT World Small Cap Low Carbon"
complete -c index_fund_rebalance -l sc -d "Alias for --smallcap"
complete -c index_fund_rebalance -l allow-sell -d "Rebalance exactly, selling overweight funds"
complete -c index_fund_rebalance -s i -l invest -d "Fresh money to add before rebalancing"
complete -c index_fund_rebalance -s c -l currency -d "Currency symbol for output"
complete -c index_fund_rebalance -l world-pct -d "Target % for NT World Screened"
complete -c index_fund_rebalance -l em-pct -d "Target % for NT Emerging Market Screened"
complete -c index_fund_rebalance -l smallcap-pct -d "Target % for NT World Small Cap"
complete -c index_fund_rebalance -l sc-pct -d "Alias for --smallcap-pct"
