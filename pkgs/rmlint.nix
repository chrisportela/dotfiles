{ rmlint, fetchpatch }:
let
  zfs-support-patch = fetchpatch {
    #url = "https://patch-diff.githubusercontent.com/raw/sahib/rmlint/pull/748.patch";
    url = "https://github.com/sahib/rmlint/compare/master...99b61cadb1105ae9b9e9360326f581e0c9a4a4c4.patch?full_index=1";
    sha256 = "sha256-NngZQvLcQSd6FYDlyFnhAfJ8k29SKUa+Uf7IsDfQItI=";
  };
in
rmlint.overrideAttrs (
  finalAttrs: previousAttrs: {
    patches = previousAttrs.patches ++ [ zfs-support-patch ];
  }
)
