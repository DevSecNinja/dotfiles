#!/bin/bash

# Useful function to compare two redemption options and show which gives better value per point/mile
# Usage: calculate-points-value [name1] <points1> <euros1> [name2] <points2> <euros2>
# Output: > calculate-points-value 8000 180 25000 268
#
# Points/miles value analysis:
# -------------------------
# Option 1: €0.0225 per point (8000 points for €180)
# Option 2: €0.0107 per point (25000 points for €268)

# Comparison between options:
# Option 1 offers better value
# It's 110% better value than Option 2

calculate-points-value() {
	if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
		echo "Usage: calculate-points-value [name1] <points1> <euros1> [name2] <points2> <euros2>"
		echo "Example with names: calculate-points-value 'Regency Bali' 8000 180 'Regency Seattle' 25000 268"
		echo "Example without names: calculate-points-value 8000 180 25000 268"
		echo "Will compare two redemption options and show which gives better value per point/mile"
		return 0
	fi

	# Check if we have names provided (6 arguments) or just numbers (4 arguments)
	if [[ $# -eq 6 ]]; then
		name1="$1"
		points1="$2"
		euros1="$3"
		name2="$4"
		points2="$5"
		euros2="$6"
	elif [[ $# -eq 4 ]]; then
		name1="Option 1"
		points1="$1"
		euros1="$2"
		name2="Option 2"
		points2="$3"
		euros2="$4"
	else
		echo "Error: Invalid number of arguments."
		echo "Use -h or --help flag for usage information."
		return 1
	fi

	# Calculate values per point (multiply by 10000 to handle 4 decimal places in pure bash)
	value1=$(((euros1 * 10000) / points1))
	value2=$(((euros2 * 10000) / points2))

	echo "Points/miles value analysis:"
	echo "-------------------------"
	echo "$name1: €0.$(printf "%04d" $value1) per point ($points1 points for €$euros1)"
	echo "$name2: €0.$(printf "%04d" $value2) per point ($points2 points for €$euros2)"

	echo -e "\nComparison between options:"
	if ((value1 > value2)); then
		percent_better=$((((value1 * 100) / value2) - 100))
		echo "$name1 offers better value"
		echo "It's ${percent_better}% better value than $name2"
	else
		percent_better=$((((value2 * 100) / value1) - 100))
		echo "$name2 offers better value"
		echo "It's ${percent_better}% better value than $name1"
	fi
}
