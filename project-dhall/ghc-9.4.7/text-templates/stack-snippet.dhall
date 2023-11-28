\(_stackage-resolver : Optional Text) ->
  ''
  user-message: "WARNING: This stack project is generated."

  allow-newer: true
  allow-newer-deps:
    - ghc-timings

  flags:
    liquid-fixpoint:
      devel: true 
    liquid-platform:
      devel: true 
    tests:
      stack: true

  ghc-options:
    "$locals": -fhide-source-paths
    hscolor: -w
    liquidhaskell-boot: -j
    liquidhaskell: -j

  nix:
    packages: [cacert, git, hostname, z3]
    path: [nixpkgs=./nixpkgs.nix]
  ''
