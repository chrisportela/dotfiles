{ rmlint, fetchpatch }:
let
  zfs-support-patch = fetchpatch {
    url = "https://patch-diff.githubusercontent.com/raw/sahib/rmlint/pull/748.patch";
    sha256 = "sha256-ODHcc3U9/b8WDYPRSSOXV5Ggjr1ZQbyX9NVGVumA8xs=";
  };
in
rmlint.overrideAttrs (
  finalAttrs: previousAttrs: {
    patches = previousAttrs.patches ++ [
      zfs-support-patch
    ];
  }
)
