function fish-greeting
    # Custom greeting function
    # Override the default Fish greeting

    if command -sq fastfetch
        echo
        fastfetch
        echo
    end

    echo "Welcome to Fish Shell! 🐠"
    echo "Type 'help' for assistance"
end
