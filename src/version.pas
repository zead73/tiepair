unit Version;

{ The version of Tiepair: the one place it is written in the program. Change it
  with tools/set-version.sh; tools/check-version.sh (run by the build script) fails if
  CHANGELOG.md does not start with this version. Numbers are MAJOR.MINOR.PATCH: a patch
  for fixes, a minor for anything that changes how the game plays or what it offers,
  and 1.0 for the full release. }

{$mode objfpc}{$H+}

interface

const
  AppVersion = '0.3.1';

implementation

end.
