{- |
Copyright   : (c) Runtime Verification, 2018-2021
License     : BSD-3-Clause
-}
module Kore.Simplify.Ceil (
    simplify,
    simplifyEvaluated,
    makeEvaluate,
    makeEvaluateTerm,
    Ceil (..),
    -- TODO: move!
    NormalForm,
    fromPredicates,
    fromPredicate,
) where

import Control.Error (
    MaybeT,
    maybeT,
 )
import Control.Monad.Reader (
    MonadReader,
 )
import Control.Monad.Reader qualified as Reader
import Data.Functor.Foldable qualified as Recursive
import Kore.Attribute.Symbol qualified as Attribute.Symbol (
    isTotal,
 )
import Kore.Attribute.Synthetic (
    synthesize,
 )
import Kore.Builtin.AssocComm.CeilSimplifier qualified as AssocComm
import Kore.Internal.Condition qualified as Condition
import Kore.Internal.Conditional (
    Conditional (..),
 )
import Kore.Internal.From (fromCeil_)
import Kore.Internal.InternalList
import Kore.Internal.InternalMap
import Kore.Internal.InternalSet
import Kore.Internal.MultiAnd (
    MultiAnd,
 )
import Kore.Internal.MultiAnd qualified as MultiAnd
import Kore.Internal.MultiOr (MultiOr)
import Kore.Internal.MultiOr qualified as MultiOr
import Kore.Internal.OrPattern (OrPattern)
import Kore.Internal.OrPattern qualified as OrPattern
import Kore.Internal.Pattern (Pattern)
import Kore.Internal.Pattern qualified as Pattern
import Kore.Internal.Predicate (
    Predicate,
    makeCeilPredicate,
 )
import Kore.Internal.Predicate qualified as Predicate
import Kore.Internal.SideCondition (
    SideCondition,
 )
import Kore.Internal.SideCondition qualified as SideCondition
import Kore.Internal.SideCondition.SideCondition qualified as SideCondition (
    Representation,
 )
import Kore.Internal.TermLike
import Kore.Rewrite.Function.Evaluator qualified as Axiom (
    evaluatePattern,
 )
import Kore.Rewrite.RewritingVariable (
    RewritingVariableName,
 )
import Kore.Simplify.CeilSimplifier
import Kore.Simplify.InjSimplifier
import Kore.Simplify.Simplify as Simplifier
import Kore.TopBottom
import Kore.Unparser (
    unparseToString,
 )
import Prelude.Kore

-- TODO: move common type alias to common module
type NormalForm = MultiOr (MultiAnd (Predicate RewritingVariableName))

fromPredicate :: Predicate RewritingVariableName -> NormalForm
fromPredicate = MultiOr.singleton . MultiAnd.singleton

fromPredicates :: [Predicate RewritingVariableName] -> NormalForm
fromPredicates = MultiOr.singleton . MultiAnd.make

{- | Simplify a 'Ceil' of 'OrPattern'.

A ceil(or) is equal to or(ceil). We also take into account that
* ceil(top) = top
* ceil(bottom) = bottom
* ceil leaves predicates and substitutions unchanged
* ceil transforms terms into predicates
-}
simplify ::
    MonadSimplify simplifier =>
    SideCondition RewritingVariableName ->
    Ceil sort (OrPattern RewritingVariableName) ->
    simplifier NormalForm
simplify
    sideCondition
    Ceil{ceilChild = child} =
        simplifyEvaluated sideCondition child

{- | 'simplifyEvaluated' evaluates a ceil given its child, see 'simplify'
for details.
-}
simplifyEvaluated ::
    MonadSimplify simplifier =>
    SideCondition RewritingVariableName ->
    OrPattern RewritingVariableName ->
    simplifier NormalForm
simplifyEvaluated sideCondition child =
    OrPattern.traverseOr (makeEvaluate sideCondition) child

{- | Evaluates a ceil given its child as an Pattern, see 'simplify'
for details.
-}
makeEvaluate ::
    MonadSimplify simplifier =>
    SideCondition RewritingVariableName ->
    Pattern RewritingVariableName ->
    simplifier NormalForm
makeEvaluate sideCondition child
    | Pattern.isTop child = return (MultiOr.singleton MultiAnd.top)
    | Pattern.isBottom child = return MultiOr.bottom
    | isTop term = return (fromPredicate condition')
    | otherwise = do
        termCeil <- makeEvaluateTerm childSort sideCondition term
        return (MultiOr.map (MultiAnd.singleton condition' <>) termCeil)
  where
    (term, condition) = Pattern.splitTerm child
    condition' = from @_ @(Predicate _) condition
    childSort = Pattern.patternSort child

-- TODO: Ceil(function) should be an and of all the function's conditions, both
-- implicit and explicit.

-- | Evaluates the ceil of a TermLike, see 'simplify' for details.
makeEvaluateTerm ::
    forall simplifier.
    MonadSimplify simplifier =>
    Sort ->
    SideCondition RewritingVariableName ->
    TermLike RewritingVariableName ->
    simplifier NormalForm
makeEvaluateTerm resultSort sideCondition ceilChild =
    runCeilSimplifierWith
        ceilSimplifier
        sideCondition
        Ceil
            { ceilResultSort = resultSort
            , ceilOperandSort = termLikeSort ceilChild
            , ceilChild
            }
        & maybeT (makeSimplifiedCeil sideCondition Nothing ceilChild) return
  where
    ceilSimplifier =
        mconcat
            [ newPredicateCeilSimplifier
            , newDefinedCeilSimplifier sideCondition
            , -- We must apply user-defined \ceil rule before built-in rules
              -- because they may be more specific. In particular, Map and Set
              -- \ceil conditions are reduced to Bool expressions using in_keys.
              newAxiomCeilSimplifier
            , newApplicationCeilSimplifier
            , newBuiltinCeilSimplifier resultSort
            , newInjCeilSimplifier
            ]

newPredicateCeilSimplifier ::
    Monad simplifier =>
    CeilSimplifier
        simplifier
        (TermLike RewritingVariableName)
        NormalForm
newPredicateCeilSimplifier = CeilSimplifier $ \input ->
    case Predicate.makePredicate (ceilChild input) of
        Left _ -> empty
        Right predicate -> return (fromPredicate predicate)

newDefinedCeilSimplifier ::
    Monad simplifier =>
    SideCondition RewritingVariableName ->
    CeilSimplifier
        simplifier
        (TermLike RewritingVariableName)
        NormalForm
newDefinedCeilSimplifier sideCondition = CeilSimplifier $ \input ->
    -- trace ("\ndefinedCeilInput\n" <> unparseToString (ceilChild input)) $
    if SideCondition.isDefined sideCondition (ceilChild input)
        then return (MultiOr.singleton MultiAnd.top)
        else empty

newApplicationCeilSimplifier ::
    MonadSimplify simplifier =>
    CeilSimplifier
        simplifier
        (TermLike RewritingVariableName)
        NormalForm
newApplicationCeilSimplifier = CeilSimplifier $ \input ->
    case ceilChild input of
        App_ patternHead children
            | let headAttributes = symbolAttributes patternHead
              , Attribute.Symbol.isTotal headAttributes -> do
                return (fromPredicates $ fromCeil_ <$> children)
        _ -> empty

newInjCeilSimplifier ::
    MonadSimplify simplifier =>
    CeilSimplifier
        simplifier
        (TermLike RewritingVariableName)
        NormalForm
newInjCeilSimplifier = CeilSimplifier $ \input ->
    case ceilChild input of
        Inj_ inj -> do
            InjSimplifier{evaluateCeilInj} <- askInjSimplifier
            input{ceilChild = inj}
                & evaluateCeilInj
                & ceilChild
                & fromCeil_
                & fromPredicate
                & return
        _ -> empty

newBuiltinCeilSimplifier ::
    MonadReader (SideCondition RewritingVariableName) simplifier =>
    MonadSimplify simplifier =>
    Sort ->
    CeilSimplifier
        simplifier
        (TermLike RewritingVariableName)
        NormalForm
newBuiltinCeilSimplifier ceilSort = CeilSimplifier $ \input ->
    case ceilChild input of
        InternalList_ internal -> do
            sideCondition <- Reader.ask
            makeEvaluateInternalList ceilSort sideCondition internal
        InternalMap_ internalMap -> do
            sideCondition <- Reader.ask
            makeEvaluateInternalMap ceilSort sideCondition internalMap
        InternalSet_ internalSet -> do
            sideCondition <- Reader.ask
            makeEvaluateInternalSet ceilSort sideCondition internalSet
        _ -> empty

newAxiomCeilSimplifier ::
    MonadReader (SideCondition RewritingVariableName) simplifier =>
    MonadSimplify simplifier =>
    CeilSimplifier
        simplifier
        (TermLike RewritingVariableName)
        NormalForm
newAxiomCeilSimplifier = CeilSimplifier $ \input -> do
    sideCondition <- Reader.ask
    evaluation <-
        Axiom.evaluatePattern
            sideCondition
            Condition.top
            (synthesize $ CeilF input)
            (const empty)
    return (OrPattern.map (MultiAnd.singleton . toPredicate) evaluation)
  where
    toPredicate Conditional{term = Top_ _, predicate, substitution} =
        Predicate.makeAndPredicate
            predicate
            (from @_ @(Predicate _) substitution)
    toPredicate patt =
        error
            ( "Ceil simplification is expected to result ai a predicate, but"
                ++ " got ("
                ++ show patt
                ++ ")."
                ++ " The most likely cases are: evaluating predicate symbols, "
                ++ " and predicate symbols are currently unrecognized as such, "
                ++ "and programming errors."
            )

makeEvaluateInternalMap ::
    forall simplifier.
    MonadSimplify simplifier =>
    Sort ->
    SideCondition RewritingVariableName ->
    InternalMap Key (TermLike RewritingVariableName) ->
    MaybeT simplifier NormalForm
makeEvaluateInternalMap resultSort sideCondition internalMap =
    runCeilSimplifierWith
        AssocComm.newMapCeilSimplifier
        sideCondition
        Ceil
            { ceilResultSort = resultSort
            , ceilOperandSort = builtinAcSort
            , ceilChild = internalMap
            }
  where
    InternalAc{builtinAcSort} = internalMap

-- | Evaluates the ceil of a domain value.
makeEvaluateInternalSet ::
    forall simplifier.
    MonadSimplify simplifier =>
    Sort ->
    SideCondition RewritingVariableName ->
    InternalSet Key (TermLike RewritingVariableName) ->
    MaybeT simplifier NormalForm
makeEvaluateInternalSet resultSort sideCondition internalSet =
    runCeilSimplifierWith
        AssocComm.newSetCeilSimplifier
        sideCondition
        Ceil
            { ceilResultSort = resultSort
            , ceilOperandSort = builtinAcSort
            , ceilChild = internalSet
            }
  where
    InternalAc{builtinAcSort} = internalSet

makeEvaluateInternalList ::
    forall simplifier.
    MonadSimplify simplifier =>
    Sort ->
    SideCondition RewritingVariableName ->
    InternalList (TermLike RewritingVariableName) ->
    simplifier NormalForm
makeEvaluateInternalList _ _ internal = do
    return (MultiOr.singleton (MultiAnd.make $ fromCeil_ <$> toList internal))

{- | This handles the case when we can't simplify a term's ceil.

It returns the ceil of that term.

When the term's ceil implies the ceils of its subterms, this also @and@s
the subterms' simplified ceils to the result. This is needed because the
SMT solver can't infer a subterm's ceil from a term's ceil, so we
have to provide that information.

As an example, if we call @makeSimplifiedCeil@ for @f(g(x))@, and we don't
know how to simplify @ceil(g(x))@, the return value will be
@and(ceil(f(g(x))), ceil(g(x)))@.
-}
makeSimplifiedCeil ::
    MonadSimplify simplifier =>
    SideCondition RewritingVariableName ->
    Maybe SideCondition.Representation ->
    TermLike RewritingVariableName ->
    simplifier NormalForm
makeSimplifiedCeil
    _
    maybeCurrentCondition
    termLike@(Recursive.project -> _ :< termLikeF) =
        if needsChildCeils
            then return (MultiOr.singleton (MultiAnd.make $ unsimplified : (fromCeil_ <$> toList termLikeF)))
            else return (MultiOr.singleton (MultiAnd.singleton unsimplified))
      where
        needsChildCeils = case termLikeF of
            ApplyAliasF _ -> False
            EndiannessF _ -> True
            SignednessF _ -> True
            AndF _ -> True
            ApplySymbolF _ -> True
            InjF _ -> True
            CeilF _ -> unexpectedError
            EqualsF _ -> unexpectedError
            ExistsF _ -> False
            IffF _ -> False
            ImpliesF _ -> False
            InF _ -> False
            NotF _ -> False
            BottomF _ -> unexpectedError
            DomainValueF _ -> True
            FloorF _ -> False
            ForallF _ -> False
            InhabitantF _ -> False
            MuF _ -> False
            NuF _ -> False
            NextF _ -> True
            OrF _ -> False
            RewritesF _ -> False
            TopF _ -> unexpectedError
            StringLiteralF _ -> unexpectedError
            InternalBoolF _ -> unexpectedError
            InternalBytesF _ -> unexpectedError
            InternalIntF _ -> unexpectedError
            InternalListF _ -> True
            InternalMapF _ -> True
            InternalSetF _ -> True
            InternalStringF _ -> unexpectedError
            VariableF _ -> False

        unsimplified =
            Predicate.markSimplifiedMaybeConditional maybeCurrentCondition
                . makeCeilPredicate
                $ termLike

        ~unexpectedError =
            error ("Unexpected term type: " ++ unparseToString termLike)
