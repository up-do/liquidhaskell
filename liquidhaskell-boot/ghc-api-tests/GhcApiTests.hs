
import           Control.Monad
import           Data.List (find)
import           Data.Time (getCurrentTime)
import           Liquid.GHC.API
    ( ApiComment(ApiBlockComment)
    , Expr(..)
    , Alt(..)
    , AltCon(..)
    , LitNumType(..)
    , Literal(..)
    , apiCommentsParsedSource
    , occNameString
    , pAT_ERROR_ID
    , showPprQualified
    )
import           Test.Tasty
import           Test.Tasty.HUnit
import           Test.Tasty.Runners.AntXML

import qualified GHC as GHC
import qualified GHC.Builtin.Names as GHC
import qualified GHC.Builtin.Types as GHC
import qualified GHC.Core as GHC
import qualified GHC.Data.EnumSet as EnumSet
import qualified GHC.Data.FastString as GHC
import qualified GHC.Data.StringBuffer as GHC
import qualified GHC.Parser as Parser
import qualified GHC.Parser.Lexer as GHC
import qualified GHC.Types.Id as GHC
import qualified GHC.Types.Name as GHC
import qualified GHC.Types.SrcLoc as GHC
import qualified GHC.Unit.Module.ModGuts as GHC
import qualified GHC.Utils.Error as GHC
import qualified GHC.Utils.Outputable as GHC

import GHC.Paths (libdir)


main :: IO ()
main =
  defaultMainWithIngredients (antXMLRunner:defaultIngredients) testTree

testTree :: TestTree
testTree =
    testGroup "GHC API"
      [ testCase "apiComments" testApiComments
      , testCase "caseDesugaring" testCaseDesugaring
      , testCase "numericLiteralDesugaring" testNumLitDesugaring
      ]

-- Tests that Liquid.GHC.API.Extra.apiComments can retrieve the comments in
-- the right order from an AST
testApiComments :: IO ()
testApiComments = do
    let str = unlines
          [ "{-@ LIQUID \"--ple\" @-}"
          , "module A where"
          , "import B"
          , ""
          , "{-@ i :: { v:Int | v>=0 } @-}"
          , "i :: Int"
          , "i = 4"
          , ""
          , "{-@ infixr ++ @-}"
          , ""
          , "{-@ abs :: Int -> { v:Int | v >= 0 } @-}"
          , "abs :: Int -> Int"
          , "abs x = z"
          , "  where"
          , "    {-@ { v: Int | z >= 0 } @-}"
          , "    z = if x < 0 then -x else x"
          ]
    lhsMod <- parseMod str "A.hs"
    let comments = map GHC.unLoc (apiCommentsParsedSource lhsMod)
        expected = map ApiBlockComment
          [ "{-@ LIQUID \"--ple\" @-}"
          , "{-@ i :: { v:Int | v>=0 } @-}"
          , "{-@ infixr ++ @-}"
          , "{-@ abs :: Int -> { v:Int | v >= 0 } @-}"
          , "{-@ { v: Int | z >= 0 } @-}"
          ]
    when (expected /= comments) $
      fail $ unlines $ "Unexpected comments:" : map show comments
  where
    parseMod str filepath = do
      let location = GHC.mkRealSrcLoc (GHC.mkFastString filepath) 1 1
          buffer = GHC.stringToStringBuffer str
          popts = GHC.mkParserOpts EnumSet.empty diagOpts [] False True True True
          parseState = GHC.initParserState popts buffer location
      case GHC.unP Parser.parseModule parseState of
        GHC.POk _ result -> return result
        _ -> fail "Unexpected parser error"

    diagOpts = GHC.DiagOpts
      { GHC.diag_warning_flags = EnumSet.empty
      , GHC.diag_fatal_warning_flags = EnumSet.empty
      , GHC.diag_warn_is_error = True
      , GHC.diag_reverse_errors = False
      , GHC.diag_max_errors = Nothing
      , GHC.diag_ppr_ctx = GHC.defaultSDocContext
      }


-- | Tests that case expressions desugar as Liquid Haskell expects.
testCaseDesugaring :: IO ()
testCaseDesugaring = do
    let inputSource = unlines
          [ "module CaseDesugaring where"
          , "f :: Bool -> ()"
          , "f x = case x of"
          , "        True -> ()"
          ]

        fBind (GHC.NonRec b _e) =
          occNameString (GHC.occName b) == "f"
        fBind _ = False

        -- Expected desugaring:
        --
        -- CaseDesugaring.f
        --      = \ (x :: GHC.Types.Bool) ->
        --          case x of {
        --            __DEFAULT ->
        --              case Control.Exception.Base.patError ...
        --              of {
        --              };
        --            GHC.Types.True -> GHC.Tuple.()
        --          }
        --
        isExpectedDesugaring p = case find fBind p of
          Just (GHC.NonRec _ e0)
            | Lam x (Case (Var x') _ _ [alt0, _alt1]) <- e0
            , x == x'
            , Alt DEFAULT [] e1 <- alt0
            , Case e2 _ _ [] <- e1
            , (Var e3,_) <- GHC.collectArgs e2
            -> e3 == pAT_ERROR_ID
          _ -> False

    coreProgram <- compileToCore "CaseDesugaring" inputSource
    unless (isExpectedDesugaring coreProgram) $
      fail $ unlines $
        "Unexpected desugaring:" : map showPprQualified coreProgram

-- | Tests that numeric literal expressions desugar as Liquid Haskell expects.
testNumLitDesugaring :: IO ()
testNumLitDesugaring = do
    let inputSource = unlines
          [ "module NumLitDesugaring where"
          , "f :: Num a => a"
          , "f = 1"
          ]

        fBind (GHC.NonRec b _e) =
          occNameString (GHC.occName b) == "f"
        fBind _ = False

        -- Expected desugaring:
        --
        -- NumLitDesugaring.f
        --      = \@a dict -> fromInteger @a dict (GHC.Num.Integer.IS 1#)
        --
        isExpectedDesugaring p = case find fBind p of
          Just (GHC.NonRec _ e0)
            | Lam _a (Lam _dict (App fromIntegerApp (App (Var vIS) lit))) <- e0
            , App (App (Var vFromInteger) _aty) _numDict <- fromIntegerApp
            , GHC.idName vFromInteger  == GHC.fromIntegerName
            , GHC.nameStableString (GHC.idName vIS) == GHC.nameStableString GHC.integerISDataConName
            , Lit (LitNumber LitNumInt 1) <- lit
            -> True
          _ -> False

    coreProgram <- compileToCore "NumLitDesugaring" inputSource
    unless (isExpectedDesugaring coreProgram) $
      fail $ unlines $
        "Unexpected desugaring:" : map showPprQualified coreProgram

compileToCore :: String -> String -> IO [GHC.CoreBind]
compileToCore modName inputSource = do
    now <- getCurrentTime
    GHC.runGhc (Just libdir) $ do
      df1 <- GHC.getSessionDynFlags
      GHC.setSessionDynFlags df1
      let target = GHC.Target {
                   GHC.targetId           = GHC.TargetFile (modName ++ ".hs") Nothing
                 , GHC.targetUnitId       = GHC.homeUnitId_ df1
                 , GHC.targetAllowObjCode = False
                 , GHC.targetContents     = Just (GHC.stringToStringBuffer inputSource, now)
                 }
      GHC.setTargets [target]
      void $ GHC.load GHC.LoadAllTargets

      dsMod <- GHC.getModSummary (GHC.mkModuleName modName)
             >>= GHC.parseModule
             >>= GHC.typecheckModule
             >>= GHC.desugarModule
      return $ GHC.mg_binds $ GHC.dm_core_module dsMod
