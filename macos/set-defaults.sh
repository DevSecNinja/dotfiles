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

echo "[+] Finder: Always open everything in Finder's list view. This is important."
defaults write com.apple.Finder FXPreferredViewStyle Nlsv

echo "[+] Finder: show all filename extensions"
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

echo "[+] Finder: Disable the warning when changing a file extension"
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

echo "[+] Finder: When performing a search, search the current folder by default"
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

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

echo "[+] Safari: prevent opening 'safe' files automatically after downloading"
defaults write com.apple.Safari.plist AutoOpenSafeDownloads -bool true

echo "[+] Safari: disable autofill"
defaults write com.apple.Safari.plist AutoFillPasswords -bool true

echo "[+] Mac App Store: Enable Automatic Update check"
defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true

echo "[+] Mac App Store: Check for updates daily"
defaults write com.apple.SoftwareUpdate ScheduleFrequency -int 1

echo "[+] Mac App Store: Download updates automatically in the background"
defaults write com.apple.SoftwareUpdate AutomaticDownload -int 1

echo "[+] Mac App Store: Install System data files & security updates"
defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -int 1

echo "[+] Mac App Store: Automatically download apps purchased on other Macs"
defaults write com.apple.SoftwareUpdate ConfigDataInstall -int 1

echo "[+] Mac OS: Enable Auto Update"
defaults write com.apple.commerce AutoUpdate -bool true

current_effect=$(defaults read com.apple.dock mineffect 2>/dev/null)
if [ "$current_effect" != "scale" ]; then
    echo "${COLOR_GREEN}[+] Set Dock to scale effect and restart Dock${COLOR_RESET}"
    defaults write com.apple.dock "mineffect" -string "scale"
    killall Dock # Required to apply changes
else
    echo "${COLOR_BLUE}[~] Dock mineffect is already set to scale${COLOR_RESET}"
fi

# # Improve coding experience
# echo "[+] Disable automatic capitalization"
# defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false

# echo "[+] Disable smart dashes"
# defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

# echo "[+] Disable automatic period substitution"
# defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false

# echo "[+] Disable smart quotes"
# defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false

# echo "[+] Disable auto-correct"
# defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

