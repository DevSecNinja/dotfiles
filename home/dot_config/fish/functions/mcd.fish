function mcd --description 'Create a directory and cd into it'
    if test (count $argv) -ne 1
        echo "Usage: mcd <directory>" >&2
        return 1
    end

    mkdir -p $argv[1] && cd $argv[1]
end
