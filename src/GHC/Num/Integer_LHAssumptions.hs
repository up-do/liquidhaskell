{-# LANGUAGE MagicHash #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}
module GHC.Num.Integer_LHAssumptions() where

import GHC.Types
import GHC.Num.Integer
import GHC.Types_LHAssumptions()


{-@
assume GHC.Num.Integer.IS :: x:GHC.Prim.Int# -> {v: GHC.Num.Integer | v = (x :: int) }
@-}
