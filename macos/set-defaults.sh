# Sets reasonable macOS defaults.
#
# Or, in other words, set shit how I like in macOS.
#
# The original idea (and a couple settings) were grabbed from:
#   https://github.com/mathiasbynens/dotfiles/blob/HEAD/.macos
#
# Run ./set-defaults.sh and you'll be good to go.

echo "[+] Disable press-and-hold for keys in favor of key repeat."
defaults write -g ApplePressAndHoldEnabled -bool false

echo "[+] Use AirDrop over every interface. srsly this should be a default."
defaults write com.apple.NetworkBrowser BrowseAllInterfaces 1

echo "[+] Always open everything in Finder's list view. This is important."
defaults write com.apple.Finder FXPreferredViewStyle Nlsv

echo "[+] Show the ~/Library folder."
chflags nohidden ~/Library

echo "[+] Set a really fast key repeat."
defaults write NSGlobalDomain KeyRepeat -int 1

echo "[+] Set the Finder prefs for showing a few different volumes on the Desktop."
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true

# echo "[+] Run the screensaver if we're in the bottom-left hot corner."
# defaults write com.apple.dock wvous-bl-corner -int 5
# defaults write com.apple.dock wvous-bl-modifier -int 0

echo "[+] Enable Safari's bookmark bar."
defaults write com.apple.Safari.plist ShowFavoritesBar -bool true

echo "[+] Set up Safari for development."
defaults write com.apple.Safari.SandboxBroker ShowDevelopMenu -bool true
defaults write com.apple.Safari.plist IncludeDevelopMenu -bool true
defaults write com.apple.Safari.plist WebKitDeveloperExtrasEnabledPreferenceKey -bool true
defaults write com.apple.Safari.plist "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" -bool true
defaults write NSGlobalDomain WebKitDeveloperExtras -bool true

current_effect=$(defaults read com.apple.dock mineffect 2>/dev/null)
if [ "$current_effect" != "scale" ]; then
    echo "${COLOR_GREEN}[+] Set Dock to scale effect and restart Dock${COLOR_RESET}"
    defaults write com.apple.dock "mineffect" -string "scale"
    killall Dock # Required to apply changes
else
    echo "${COLOR_BLUE}[~] Dock mineffect is already set to scale${COLOR_RESET}"
fi
