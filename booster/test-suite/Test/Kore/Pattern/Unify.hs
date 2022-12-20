{- |
Copyright   : (c) Runtime Verification, 2022
License     : BSD-3-Clause
-}
module Test.Kore.Pattern.Unify (
    test_unification,
) where

import Data.List.NonEmpty qualified as NE
import Data.Map qualified as Map
import Test.Tasty
import Test.Tasty.HUnit

import Kore.Definition.Attributes.Base
import Kore.Pattern.Base
import Kore.Pattern.Unify
import Test.Kore.Fixture

test_unification :: TestTree
test_unification =
    testGroup
        "Unification"
        [ constructors
        , functions
        , varsAndValues
        , andTerms
        , sorts
        , injections
        ]

injections :: TestTree
injections =
    testGroup
        "sort injections"
        [ test
            "same sort injection"
            (inject aSubsort someSort varSub)
            (inject aSubsort someSort dSub)
            $ success [("X", aSubsort, dSub)]
        , test
            "subsort injection"
            (inject someSort kItemSort varSome)
            (inject aSubsort kItemSort dSub)
            $ success [("Y", someSort, inject aSubsort someSort dSub)]
        , let t1 = inject someSort kItemSort varSome
              t2 = inject differentSort kItemSort dOther
           in test "sort injection mismatch" t1 t2 $ failed (DifferentSymbols t1 t2)
        ]
  where
    varSub = var "X" aSubsort
    varSome = var "Y" someSort
    dSub = dv aSubsort "a subsort"
    dOther = dv differentSort "different sort"

inject :: Sort -> Sort -> Term -> Term
inject from to t = SymbolApplication inj [from, to] [t]

-- TODO move to Fixture!
inj :: Symbol
inj =
    Symbol
        { name = "inj"
        , sortVars = ["Source", "Target"]
        , resultSort = SortVar "Target"
        , argSorts = [SortVar "Source"]
        , attributes = SymbolAttributes SortInjection False False
        }

sorts :: TestTree
sorts =
    testGroup
        "sort variables"
        [ test "one sort variable in argument" (app con1 [varX]) (app con1 [dSome]) $
            success [("X", sVar, dSome)]
        , test "sort inconsistency in arguments" (app con3 [varX, varY]) (app con3 [dSome, dSub]) $
            sortErr $
                InconsistentSortVariable "sort me!" [someSort, aSubsort]
        , test "sort variable used twice" (app con3 [varX, varY]) (app con3 [dSome, dSome]) $
            success [("X", sVar, dSome), ("Y", sVar, dSome)]
        , test "several sort variables" (app con3 [varX, varZ]) (app con3 [dSome, dSub]) $
            success [("X", sVar, dSome), ("Z", sVar2, dSub)]
        , test "sort variable in subject" (app con3 [varX, dSub]) (app con3 [dSome, varZ]) $
            success [("X", sVar, dSome), ("Z", sVar2, dSub)]
        , test "same sort variable in both" (app con1 [varX]) (app con1 [varY]) $
            success [("X", sVar, varY)]
        ]
  where
    sVar = SortVar "sort me!"
    sVar2 = SortVar "me, too!"
    varX = var "X" sVar
    varY = var "Y" sVar
    varZ = var "Z" sVar2
    dSome = dv someSort "some sort"
    dSub = dv aSubsort "a subsort"

constructors :: TestTree
constructors =
    testGroup
        "Unifying constructors"
        [ test
            "same constructors, one variable argument"
            (app con1 [var "X" someSort])
            (app con1 [var "Y" someSort])
            (success [("X", someSort, var "Y" someSort)])
        , let x = var "X" someSort
              cX = app con1 [x]
           in test "same constructors, same variable (shared var)" cX cX $
                remainder [(x, x)]
        , let x = var "X" someSort
              y = var "Y" someSort
              cxx = app con3 [x, x]
              cxy = app con3 [x, y]
           in test "same constructors, one shared variable" cxx cxy $
                remainder [(x, x)]
        , let v = var "X" someSort
              d = dv differentSort ""
           in test
                "same constructors, arguments differ in sorts"
                (app con1 [v])
                (app con1 [d])
                (sortErr $ IncompatibleSorts [someSort, differentSort])
        , test
            "same constructor, var./term argument"
            (app con1 [var "X" someSort])
            (app con1 [app f1 [var "Y" someSort]])
            (success [("X", someSort, app f1 [var "Y" someSort])])
        , let t1 = app con1 [var "X" someSort]
              t2 = app con2 [var "Y" someSort]
           in test "different constructors" t1 t2 $ failed (DifferentSymbols t1 t2)
        , let t1 = app con1 [var "X" someSort]
              t2 = app f1 [var "Y" someSort]
           in test "Constructor and function" t1 t2 $ remainder [(t1, t2)]
        ]

functions :: TestTree
functions =
    testGroup
        "Functions (should not unify)"
        [ let f = app f1 [dv someSort ""]
           in test "exact same function (but not unifying)" f f $ remainder [(f, f)]
        , let f1T = app f1 [dv someSort ""]
              f2T = app f2 [dv someSort ""]
           in test "different functions" f1T f2T $ remainder [(f1T, f2T)]
        ]

varsAndValues :: TestTree
varsAndValues =
    testGroup
        "Variables and Domain Values"
        [ let v = var "X" someSort
           in test "identical variables" v v (remainder [(v, v)])
        , let v1 = var "X" someSort
              v2 = var "Y" someSort
           in test "two variables (same sort)" v1 v2 $
                success [("X", someSort, v2)]
        , let v1 = var "X" someSort
              v2 = var "Y" aSubsort
           in test "two variables (v2 subsort v1)" v1 v2 $
                -- TODO could be allowed once subsorts are considered while checking
                sortErr $
                    IncompatibleSorts [someSort, aSubsort]
        , let v1 = var "X" aSubsort
              v2 = var "Y" someSort
           in test "two variables (v1 subsort v2)" v1 v2 $
                sortErr $
                    IncompatibleSorts [aSubsort, someSort]
        , let v1 = var "X" someSort
              v2 = var "X" differentSort
           in test "same variable name, different sort" v1 v2 $
                failed (VariableConflict (Variable someSort "X") v1 v2)
        , let d1 = dv someSort "1"
              d2 = dv someSort "1"
           in test "same domain values (same sort)" d1 d2 $
                success []
        , let d1 = dv someSort "1"
              d2 = dv someSort "2"
           in test "different domain values (same sort)" d1 d2 $
                failed (DifferentValues d1 d2)
        , let d1 = dv someSort "1"
              d2 = dv differentSort "2"
           in test "different domain values (different sort)" d1 d2 $
                failed (DifferentValues d1 d2)
        , let d1 = dv someSort "1"
              d2 = dv differentSort "1"
           in test "same domain values, different sort" d1 d2 $
                remainder [(d1, d2)]
        , let v = var "X" someSort
              d = dv someSort ""
           in test "var and domain value (same sort)" v d $
                success [("X", someSort, d)]
        , let v = var "X" someSort
              d = dv differentSort ""
           in test "var and domain value (different sort)" v d $
                sortErr $
                    IncompatibleSorts [someSort, differentSort]
        ]

andTerms :: TestTree
andTerms =
    testGroup
        "And-terms on either side"
        [ let d = dv someSort "a"
              fa = app f1 [d]
              fb = app f1 [dv someSort "b"]
           in test
                "And-term on the left, remainder returns both pairs"
                (AndTerm fa fb)
                d
                (remainder [(fa, d), (fb, d)])
        , let d = dv someSort "a"
              fa = app f1 [d]
              fb = app f1 [dv someSort "b"]
           in test
                "And-term on the right, remainder returns both pairs"
                d
                (AndTerm fa fb)
                (remainder [(d, fa), (d, fb)])
        , let da = dv someSort "a"
              db = dv someSort "b"
              ca = app con1 [da]
              cb = app con1 [db]
           in test
                "And-term on the left, one pair resolves"
                (AndTerm ca da)
                cb
                (remainder [(da, cb), (da, db)])
        , let da = dv someSort "a"
              db = dv someSort "b"
              ca = app con1 [da]
              cb = app con1 [db]
           in test
                "And-term on the right, one pair resolves"
                ca
                (AndTerm cb da)
                (remainder [(ca, da), (da, db)])
        ]

----------------------------------------

success :: [(VarName, Sort, Term)] -> UnificationResult
success assocs =
    UnificationSuccess $
        Map.fromList
            [ (Variable{variableSort, variableName}, term)
            | (variableName, variableSort, term) <- assocs
            ]

failed :: FailReason -> UnificationResult
failed = UnificationFailed

remainder :: [(Term, Term)] -> UnificationResult
remainder = UnificationRemainder . NE.fromList

sortErr :: SortError -> UnificationResult
sortErr = UnificationSortError

test :: String -> Term -> Term -> UnificationResult -> TestTree
test name term1 term2 expected =
    testCase name $ unifyTerms testDefinition term1 term2 @?= expected
