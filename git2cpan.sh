#!/bin/bash

HELP=`cat <<EOT
Usage: $0 <cmd> <package-dir>

 <cmd>          - test      - check for required files, build, clean
                - build     - build the package
                - clean     - clean the package
                - checkin   - commit and push to git
 <package-dir>  - directory containing the package

EOT
`

if [ $# -lt 2 ] ; then echo "$HELP"; exit 1; fi

hint() {
    local hint="| $* |"
    local stripped="${hint//${bold}}"
    stripped="${stripped//${normal}}"
    local edge=$(echo "$stripped" | sed -e 's/./-/g' -e 's/^./+/' -e 's/.$/+/')
    echo "$edge"
    echo "$hint"
    echo "$edge"
}

_cmd=$1
_dir=$2

function assert_file() {
    if [ ! -s "$1" ]; then
        hint "$1 file missing"
        echo "$2"
        exit 1;
    fi
}

MANIFEST_HELP=`cat<<EOT
MANIFEST        - this file contain the list of the following:
                - see https://perlmaven.com/minimal-requirement-to-build-a-sane-cpan-package

Changes         - history of changes
Makefile.PL     - ExtUtils::MakeMaker
README          - text version of the README
README.pod      - POD version of the README (soft-link to module)
ignore.txt      - files/dirs to igore checking into git
META.json       - meta information about the package
t/pod.t         - test POD
t/boilerplate.t - test module
<Module.pm>     - finally the module itself
EOT
`

function replace_meta_json() {
    if [[ -s "META.json" ]] && [[ -s "MYMETA.json" ]]; then
        hint "META.json Exists"
        diff MYMETA.json META.json
        while true; do
            read -p "Replace META.json? " yn
            case $yn in
                [Yy]*) mv MYMETA.json META.json; rm MYMETA*; break ;;
                [Nn]*) rm MYMETA.*; break ;;
            esac
        done
    else
        mv MYMETA.json META.json
        rm MYMETA*
    fi
}

function clean_up() {
    assert_file 'Makefile' 'Did you run build?'
    rm Makefile pm_to_blib

    if [ -d "blib" ]; then
        rm -rf blib
    fi

    rm *.gz

    hint "All cleaned"
}

function build() {
    perl Makefile.PL
    hint "Make TEST"
    make test
    replace_meta_json
    make dist
}
        
function validate_files() {
    assert_file 'MANIFEST' "$MANIFEST_HELP"
    assert_file 'Changes' 'Text file contain list of changes'
    assert_file 'Makefile.PL' 'MakeMaker input file (see https://perlmaven.com/minimal-requirement-to-build-a-sane-cpan-package)'
    assert_file 'README.pod' 'Need a soft-link to <Module.pm>'
    assert_file 't/pod.t' 'Unit test for POD'
    assert_file 't/boilerplate.t' 'Unit test for module'
    assert_file 'ignore.txt' 'Files for git to ignore from cheking in'

    hint "All files OK"

    build

    clean_up
}

function ask() {
    while true; do
        read -p "$1 " yn
        case $yn in
            [Yy]*) break ;;
            [Nn]*) exit 1 ;;
        esac
    done
}

function assert() {
    if [ "$?" = 1 ]; then exit 1; fi
}

cd $_dir

case "${_cmd}" in
    test) validate_files
        ;;

    build) 
        build
        ;;

    clean)
        clean_up
        ;;

    checkin)
        assert_file 'META.json' 'Need to have META.json for version'

        _json=$(cat META.json)
        _version=$(echo $_json | perl -MJSON=from_json -ne 'print from_json($_)->{version}')
        _repo=$(echo $_json | perl -MJSON=from_json -ne 'print from_json($_)->{resources}{repository}{url}')

        if [ ! "$_version" ]; then
            hint "No version"
        fi


        hint "Version $_version"
        ask "Version $_version looks right?"

        ask 'Did you edit Makefile.PL?'
        ask 'Did you edit Changes?'
        ask 'Did you edit your module (<Module.pl>)?'
        read -p "Commit statement: " _commit
        if [ ! "$_commit" ]; then
            hint "Empty message!"
            exit 1;
        fi
        git commit -am "$_commit"

        assert

        hint "Tagging v$_version"
        git tag "v$_version"
        assert

        git push --tags -u origin master
        assert

        hint "$_repo/archive/${_version}.tar.gz"
        echo "Login to pause.perl.org upload the tarball"
        ;;

    *) echo "ERROR: Command '${_cmd}' not recognized"
        ;;
esac

