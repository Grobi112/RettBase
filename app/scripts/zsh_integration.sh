# In ~/.zshrc einfügen (einmalig):
# source /Users/mikefullbeck/RettBase/app/scripts/zsh_integration.sh
#
# Danach: cd app && flutter build web erhöht automatisch die Version.
#         cd app && flutter build ipa erhöht automatisch Version + Build-Nr.

rettbase_flutter() {
  if [[ "$1" == "build" && "$2" == "web" ]] && [[ -f "$(pwd)/web/increment_version.js" ]]; then
    node "$(pwd)/web/increment_version.js"
  fi
  if [[ "$1" == "build" && "$2" == "ipa" ]] && [[ -f "$(pwd)/scripts/increment_pubspec_version.js" ]]; then
    node "$(pwd)/scripts/increment_pubspec_version.js"
  fi
  command flutter "$@"
}
alias flutter='rettbase_flutter'
