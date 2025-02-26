-- | This program calls ghc using the provided command line arguments.
-- Use it to profile the liquidhaskell plugin.
--
-- Build liquid-platform first with profiling enabled.
--
-- > cabal build --enable-profiling liquid-platform
--
-- Then build this program.
--
-- > cabal build --enable-profiling scripts/profiling-driver
--
-- Then run the liquidhaskell executable pointing it to this driver with
-- the LIQUID_GHC_PATH env var.
--
-- > LIQUID_GHC_PATH=path/to/profiling-driver liquidhaskell_datadir=$PWD/liquidhaskell-boot \
-- >   cabal exec -- liquidhaskell +RTS -p -RTS tests/pos/Bag.hs
--
module Main where

import GHC as G

import Control.Monad
import Control.Monad.IO.Class
import System.Environment
import GHC.Paths (libdir)
import GHC.Utils.Logger as G

main :: IO ()
main = do
    xs <- getArgs
    runGhc (Just libdir) $ do
      df1 <- getSessionDynFlags
      let cmdOpts = ["-fforce-recomp"] ++ filter ("--make" /=) xs
      logger <- liftIO G.initLogger
      (df2, leftovers, _warns) <- G.parseDynamicFlags logger df1 (map G.noLoc cmdOpts)
      setSessionDynFlags df2
      ts <- mapM (\x-> G.guessTarget x Nothing Nothing) $ map unLoc leftovers
      setTargets ts
      void $ G.load LoadAllTargets
