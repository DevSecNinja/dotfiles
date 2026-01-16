function fish_greeting
    # Custom greeting function
    # Override the default Fish greeting
    
    if command -v fastfetch >/dev/null 2>&1; then
        echo
        fastfetch
        echo
    fi

    echo "Welcome to Fish Shell! 🐠"
    echo "Type 'help' for assistance"
end
