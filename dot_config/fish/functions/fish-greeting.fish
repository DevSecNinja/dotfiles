function fish-greeting
    # Custom greeting function
    # Override the default Fish greeting

    if type -q fastfetch
        echo
        fastfetch
        echo
    end

    echo "Welcome to Fish Shell! 🐠"
    echo "Type 'help' for assistance"
end
