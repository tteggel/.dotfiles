# open-browser-shim
#
# Some tools exec `xdg-open` directly and ignore $BROWSER — the entire.io CLI
# is one, which is why `entire login` could not open a browser. WSL ships no
# xdg-open at all, so provide one that routes to open-browser, which knows how
# to reach Windows Chrome.
#
# The marker on the first line above is how open-browser.sh recognises this
# script and avoids bouncing back into it; keep the two in sync.
exec open-browser "$@"
