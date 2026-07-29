# Resolves which Apple Development identity and Team ID to build the iOS
# targets with. Sourced, not executed.
#
# Taking the first identity out of the keychain is wrong on any Mac signed into
# more than one Apple ID. This project's bundle IDs are registered to exactly
# one team, and signing with another produces
#
#   error: No Account for Team "..."
#   error: No profiles for 'app.vibevoice.oss.ios' were found
#
# which reads like a missing profile but is really the wrong team. So the team
# is taken from a provisioning profile that already covers our bundle ID, and
# the identity is then chosen to match that team rather than the other way
# round. No identity or team is hard-coded anywhere.
#
# Usage:
#   source "$ROOT/scripts/ios-signing.zsh"
#   vibevoice_resolve_signing app.vibevoice.oss.ios
#   # sets VIBEVOICE_SIGN_IDENTITY and VIBEVOICE_SIGN_TEAM
#
# Honours VIBEVOICE_TEAM as an override, for the first build on a machine that
# has no profile yet.

# Prints the Team ID of the codesigning certificate with the given common name.
vibevoice_team_of_identity() {
    security find-certificate -c "$1" -p 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null \
        | sed -n 's/.*OU=\([^,]*\).*/\1/p'
}

# Prints the Team ID from any installed profile whose application-identifier
# ends with the given bundle ID.
vibevoice_team_from_profiles() {
    local app_id="$1"
    setopt local_options null_glob
    local -a directories profiles
    directories=(
        "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
        "$HOME/Library/MobileDevice/Provisioning Profiles"
    )
    local directory profile identifier
    for directory in "${directories[@]}"; do
        profiles=("$directory"/*.mobileprovision)
        for profile in "${profiles[@]}"; do
            identifier=$(security cms -D -i "$profile" 2>/dev/null \
                | plutil -extract Entitlements.application-identifier raw - 2>/dev/null)
            if [[ "$identifier" == *".$app_id" ]]; then
                print "${identifier%%.$app_id}"
                return 0
            fi
        done
    done
    return 1
}

vibevoice_resolve_signing() {
    local app_id="$1"
    local -a identities
    identities=("${(@f)$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p')}")
    identities=("${(@)identities:#}")
    if (( ${#identities} == 0 )); then
        print "error: no Apple Development signing identity was found." >&2
        print "Sign in under Xcode → Settings → Accounts." >&2
        return 6
    fi

    local team=""
    local source=""
    if [[ -n "${VIBEVOICE_TEAM:-}" ]]; then
        team="$VIBEVOICE_TEAM"
        source="VIBEVOICE_TEAM"
    elif team=$(vibevoice_team_from_profiles "$app_id"); then
        source="profile for $app_id"
    else
        team=$(vibevoice_team_of_identity "${identities[1]}")
        source="only available identity"
    fi
    if [[ -z "$team" ]]; then
        print "error: could not determine a Team ID to build with." >&2
        return 7
    fi

    local identity candidate
    for candidate in "${identities[@]}"; do
        if [[ "$(vibevoice_team_of_identity "$candidate")" == "$team" ]]; then
            identity="$candidate"
            break
        fi
    done
    if [[ -z "${identity:-}" ]]; then
        print "error: no signing identity belongs to Team $team (from $source)." >&2
        print "Available:" >&2
        for candidate in "${identities[@]}"; do
            print "  $(vibevoice_team_of_identity "$candidate")  $candidate" >&2
        done
        print "Set VIBEVOICE_TEAM to one of those, or add the account in Xcode." >&2
        return 6
    fi

    VIBEVOICE_SIGN_IDENTITY="$identity"
    VIBEVOICE_SIGN_TEAM="$team"
    print "SIGNING $identity — Team $team (resolved from $source)"
}
