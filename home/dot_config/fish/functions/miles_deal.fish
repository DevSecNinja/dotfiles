function miles_deal --description "Compare paying an award flight in miles vs cash and show the value per mile"
    # miles_deal - Decide whether redeeming miles beats paying cash
    #
    # Given the price of an award ticket in miles, the cash surcharge that comes
    # with the award, and the cash price of the same ticket, this works out:
    #
    #   1. The per-mile value you get from the redemption, in cents.
    #   2. Whether redeeming miles is a better deal than paying cash, judged
    #      against a benchmark value per mile (--value, default 1.2 cents).
    #
    # Per-mile value formula:   (cash_cost - miles_fee) / miles_cost
    # Redemption is "good" when: miles_cost * benchmark + miles_fee < cash_cost
    # (equivalently, when the per-mile value you get beats the benchmark).
    #
    # Usage: miles_deal [OPTIONS] MILES_COST MILES_FEE CASH_COST
    #
    # Arguments:
    #   MILES_COST   Award price in miles (e.g. 45375)
    #   MILES_FEE    Cash surcharge paid on top of the miles (e.g. 256.66)
    #   CASH_COST    Cash price of the same ticket (e.g. 4927)
    #
    # Options:
    #   -v, --value CENTS     Benchmark value of one mile in cents (default 1.2)
    #   -c, --currency SYM    Currency symbol for output (default €)
    #   -h, --help            Show this help message and exit
    #
    # Examples:
    #   miles_deal 45375 256.66 4927            # benchmark 1.2 cents/mile
    #   miles_deal --value 0.6 45375 256.66 4927
    #   miles_deal -v 1.4 -c '$' 60000 75 950

    argparse --name=miles_deal h/help 'v/value=' 'c/currency=' -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: miles_deal [OPTIONS] MILES_COST MILES_FEE CASH_COST"
        echo ""
        echo "Compare paying an award flight in miles vs cash and show the value per mile."
        echo ""
        echo "Arguments:"
        echo "  MILES_COST   Award price in miles (e.g. 45375)"
        echo "  MILES_FEE    Cash surcharge paid on top of the miles (e.g. 256.66)"
        echo "  CASH_COST    Cash price of the same ticket (e.g. 4927)"
        echo ""
        echo "Options:"
        echo "  -v, --value CENTS     Benchmark value of one mile in cents (default 1.2)"
        echo "  -c, --currency SYM    Currency symbol for output (default €)"
        echo "  -h, --help            Show this help message"
        echo ""
        echo "Examples:"
        echo "  miles_deal 45375 256.66 4927"
        echo "  miles_deal --value 0.6 45375 256.66 4927"
        echo "  miles_deal -v 1.4 -c '\$' 60000 75 950"
        return 0
    end

    if test (count $argv) -ne 3
        echo "❌ Expected 3 arguments: MILES_COST MILES_FEE CASH_COST" >&2
        echo "   Use --help for usage information." >&2
        return 1
    end

    set -l miles_cost $argv[1]
    set -l miles_fee $argv[2]
    set -l cash_cost $argv[3]

    # Validate inputs are non-negative numbers.
    for pair in "MILES_COST:$miles_cost" "MILES_FEE:$miles_fee" "CASH_COST:$cash_cost"
        set -l label (string split -m1 : -- $pair)[1]
        set -l value (string split -m1 : -- $pair)[2]
        if not string match -qr '^[0-9]+(\.[0-9]+)?$' -- $value
            echo "❌ $label must be a non-negative number (got '$value')" >&2
            return 1
        end
    end

    if test (math "$miles_cost") -le 0
        echo "❌ MILES_COST must be greater than zero" >&2
        return 1
    end

    # Benchmark value per mile (cents on input, euros internally).
    set -l benchmark_cents 1.2
    if set -q _flag_value
        if not string match -qr '^[0-9]+(\.[0-9]+)?$' -- $_flag_value
            echo "❌ --value must be a non-negative number of cents (got '$_flag_value')" >&2
            return 1
        end
        set benchmark_cents $_flag_value
    end
    set -l benchmark_eur (math "$benchmark_cents / 100")

    set -l currency €
    set -q _flag_currency; and set currency $_flag_currency

    # Core calculations.
    set -l miles_total (math -s2 "$miles_cost * $benchmark_eur + $miles_fee")
    set -l per_mile_cents (math -s3 "($cash_cost - $miles_fee) / $miles_cost * 100")

    echo "📊 Miles vs cash"
    echo "----------------"
    printf '%-22s %s%s\n' "Miles price:" "" "$miles_cost miles + $currency$miles_fee fee"
    printf '%-22s %s%s\n' "Cash price:" $currency $cash_cost
    printf '%-22s %s c/mile\n' "Benchmark value:" $benchmark_cents
    printf '%-22s %s%s\n' "Miles cost at benchmark:" $currency $miles_total
    printf '%-22s %s c/mile\n' "Value you get:" $per_mile_cents
    echo "----------------"

    # A redemption is worth it when its real per-mile value beats the benchmark,
    # i.e. when the benchmark-priced miles cost is below the cash price. Compare
    # as whole cents so `test` works on integers (fish math has no `<`).
    set -l diff_cents (math -s0 "($cash_cost - $miles_total) * 100")
    if test $diff_cents -gt 0
        printf '✅ Use miles: %s%s (miles) < %s%s (cash). Each mile is worth %s cents.\n' \
            $currency $miles_total $currency $cash_cost $per_mile_cents
    else
        printf '⚠️  Pay cash: %s%s (cash) ≤ %s%s (miles). Each mile is only worth %s cents.\n' \
            $currency $cash_cost $currency $miles_total $per_mile_cents
    end

    return 0
end

# Completions for miles_deal
complete -c miles_deal -f
complete -c miles_deal -s h -l help -d "Show help message"
complete -c miles_deal -s v -l value -d "Benchmark value of one mile in cents (default 1.2)"
complete -c miles_deal -s c -l currency -d "Currency symbol for output (default €)"
