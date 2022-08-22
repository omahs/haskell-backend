{- |
Copyright   : (c) Runtime Verification, 2019-2021
License     : BSD-3-Clause
-}
module Kore.Internal.OrCondition (
    OrCondition,
    isSimplified,
    toConditions,
    fromConditions,
    fromCondition,
    fromPredicate,
    fromPredicates,
    MultiOr.gather,
    MultiOr.observeAllT,
    bottom,
    top,
    isFalse,
    isTrue,
    toPredicate,
    toOrCondition,
) where

import Kore.Internal.Condition (
    Condition,
 )
import Kore.Internal.Condition qualified as Condition
import Kore.Internal.MultiOr (
    MultiOr,
 )
import Kore.Internal.MultiAnd (
    MultiAnd,
 )
import Kore.Internal.MultiOr qualified as MultiOr
import Kore.Internal.Predicate (
    Predicate,
 )
import Kore.Internal.Predicate qualified as Predicate
import Kore.Internal.SideCondition.SideCondition qualified as SideCondition (
    Representation,
 )
import Kore.Internal.TermLike hiding (
    isSimplified,
 )
import Kore.TopBottom (
    TopBottom (..),
 )
import Prelude.Kore

-- | The disjunction of 'Condition'.
type OrCondition variable = MultiOr (Condition variable)

isSimplified :: SideCondition.Representation -> OrCondition variable -> Bool
isSimplified sideCondition = all (Condition.isSimplified sideCondition)

-- | A "disjunction" of one 'Condition'.
fromCondition :: Condition variable -> OrCondition variable
fromCondition = from

-- | Disjoin a collection of predicates.
fromConditions ::
    (Foldable f, InternalVariable variable) =>
    f (Condition variable) ->
    OrCondition variable
fromConditions = from . toList

fromPredicate ::
    InternalVariable variable =>
    Predicate variable ->
    OrCondition variable
fromPredicate = fromCondition . Condition.fromPredicate

fromPredicates ::
    InternalVariable variable =>
    [Predicate variable] ->
    OrCondition variable
fromPredicates = fromConditions . map Condition.fromPredicate

{- | @\\bottom@

@
'isFalse' bottom == True
@
-}
bottom :: InternalVariable variable => OrCondition variable
bottom = fromConditions []

{- | @\\top@

@
'isTrue' top == True
@
-}
top :: InternalVariable variable => OrCondition variable
top = fromCondition Condition.top

-- | 'isFalse' checks if the 'OrCondition' is composed only of bottom items.
isFalse :: OrCondition variable -> Bool
isFalse = isBottom

-- | 'isTrue' checks if the 'OrCondition' has a single top pattern.
isTrue :: OrCondition variable -> Bool
isTrue = isTop

toConditions :: OrCondition variable -> [Condition variable]
toConditions = toList

-- | Transforms an 'Predicate' into a 'Predicate.Predicate'.
toPredicate ::
    InternalVariable variable =>
    MultiOr (Predicate variable) ->
    Predicate variable
toPredicate = Predicate.makeMultipleOrPredicate . toList

toOrCondition ::
    InternalVariable variable =>
    MultiOr (MultiAnd (Predicate variable)) ->
    OrCondition variable
toOrCondition =
    MultiOr.map (from @_ @(Condition _) . Predicate.fromMultiAnd)
