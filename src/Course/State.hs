{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE RebindableSyntax #-}

module Course.State where

import Course.Core
import qualified Prelude as P
import Course.Optional
import Course.List
import Course.Functor
import Course.Applicative
import Course.Monad
import qualified Data.Set as S

-- $setup
-- >>> import Test.QuickCheck.Function
-- >>> import Data.List(nub)
-- >>> import Test.QuickCheck
-- >>> import qualified Prelude as P(fmap)
-- >>> import Course.Core
-- >>> import Course.List
-- >>> instance Arbitrary a => Arbitrary (List a) where arbitrary = P.fmap listh arbitrary

-- A `State` is a function from a state value `s` to (a produced value `a`, and a resulting state `s`).
newtype State s a =
  State {
    runState ::
      s
      -> (a, s)
  }

-- | Implement the `Functor` instance for `State s`.
-- >>> runState ((+1) <$> pure 0) 0
-- (1,0)
instance Functor (State s) where
  (<$>) ::
    (a -> b)
    -> State s a
    -> State s b
  f <$> (State g) = State $ (first f) . g

-- | Implement the `Applicative` instance for `State s`.
--
-- >>> runState (pure 2) 0
-- (2,0)
--
-- >>> runState (pure (+1) <*> pure 0) 0
-- (1,0)
--
-- >>> import qualified Prelude as P
-- >>> runState (State (\s -> ((+3), s P.++ ["apple"])) <*> State (\s -> (7, s P.++ ["banana"]))) []
-- (10,["apple","banana"])
instance Applicative (State s) where
  pure ::
    a
    -> State s a
  pure a = State $ \s -> (a, s)
  (<*>) ::
    State s (a -> b)
    -> State s a
    -> State s b
-- the State we return is a function that takes a state (s). it runs f
-- on s to get another function (f' :: a->b ) and a new state (s'). it
-- then runs g on s' to get an a, and another new state (s'') we then
-- call f' on a to get a b, and return the tuple
  (<*>) (State f) (State g) = State $ \s ->
    let (f', s') = (f s)
        (a, s'') = (g s')
    in (f' a, s'')



-- | Implement the `Bind` instance for `State s`.
--
-- >>> runState ((const $ put 2) =<< put 1) 0
-- ((),2)
--
-- >>> let modify f = State (\s -> ((), f s)) in runState (modify (+1) >>= \() -> modify (*2)) 7
-- ((),16)
instance Monad (State s) where
  (=<<) ::
    (a -> State s b)
    -> State s a
    -> State s b
-- the return State takes a state (s), calls g on it to get an a and a
-- new state (s'). we then call f on a to get a (State s b), and run
-- this state, passing it s'
  f =<< (State g) = State $ \s ->
    let (a, s') = (g s)
    in runState (f a) s'


-- | Run the `State` seeded with `s` and retrieve the resulting state.
--
-- prop> \(Fun _ f) -> exec (State f) s == snd (runState (State f) s)
exec ::
  State s a
  -> s
  -> s
exec s = snd . (runState s)

-- | Run the `State` seeded with `s` and retrieve the resulting value.
--
-- prop> \(Fun _ f) -> eval (State f) s == fst (runState (State f) s)
eval ::
  State s a
  -> s
  -> a
eval s = fst . (runState s)

-- | A `State` where the state also distributes into the produced value.
--
-- >>> runState get 0
-- (0,0)
get ::
  State s s
get = State $ \s -> (s,s)

-- | A `State` where the resulting state is seeded with the given value.
--
-- >>> runState (put 1) 0
-- ((),1)
put ::
  s
  -> State s ()
put s = State $ const ((), s)

-- | Find the first element in a `List` that satisfies a given predicate.
-- It is possible that no element is found, hence an `Optional` result.
-- However, while performing the search, we sequence some `Monad` effect through.
--
-- Note the similarity of the type signature to List#find
-- where the effect appears in every return position:
--   find ::  (a ->   Bool) -> List a ->    Optional a
--   findM :: (a -> f Bool) -> List a -> f (Optional a)
--
-- >>> let p x = (\s -> (const $ pure (x == 'c')) =<< put (1+s)) =<< get in runState (findM p $ listh ['a'..'h']) 0
-- (Full 'c',3)
--
-- >>> let p x = (\s -> (const $ pure (x == 'i')) =<< put (1+s)) =<< get in runState (findM p $ listh ['a'..'h']) 0
-- (Empty,8)
--
-- writing the above examples with do notation makes it clearer:
-- let p x = do {s <- get; put (s+1); pure (x == 'c')} in runState (findM p $ listh ['a'..'h']) 0
-- let p x = do {s <- get; put (s+1); pure (x == 'i')} in runState (findM p $ listh ['a'..'h']) 0
-- both of these work the same as above
findM ::
  Monad f =>
  (a -> f Bool)
  -> List a
  -> f (Optional a)
findM _ Nil = pure Empty
findM p (a :. as) =
  p a >>=
  \b -> if b then pure (Full a) else findM p as

seen :: Ord a => a -> State (S.Set a) Bool
seen a = do
  s <- get
  put (S.insert a s)
  pure (S.member a s)


-- | Find the first element in a `List` that repeats.
-- It is possible that no element repeats, hence an `Optional` result.
--
-- /Tip:/ Use `findM` and `State` with a @Data.Set#Set@.
--
-- prop> case firstRepeat xs of Empty -> let xs' = hlist xs in nub xs' == xs'; Full x -> length (filter (== x) xs) > 1
-- prop> case firstRepeat xs of Empty -> True; Full x -> let (l, (rx :. rs)) = span (/= x) xs in let (l2, r2) = span (/= x) rs in let l3 = hlist (l ++ (rx :. Nil) ++ l2) in nub l3 == l3
firstRepeat ::
  Ord a =>
  List a
  -> Optional a
firstRepeat as = eval (findM seen as) S.empty

-- | Remove all duplicate elements in a `List`.
-- /Tip:/ Use `filtering` and `State` with a @Data.Set#Set@.
--
-- prop> firstRepeat (distinct xs) == Empty
--
-- prop> distinct xs == distinct (flatMap (\x -> x :. x :. Nil) xs)
distinct ::
  Ord a =>
  List a
  -> List a
distinct as = eval (filtering (((<$>) not) . seen) as) S.empty

square :: Num a => a -> a
square = join (*)
-- whaaaaaaaat

-- | A happy number is a positive integer, where the sum of the square of its digits eventually reaches 1 after repetition.
-- In contrast, a sad number (not a happy number) is where the sum of the square of its digits never reaches 1
-- because it results in a recurring sequence.
--
-- /Tip:/ Use `firstRepeat` with `produce`.
--
-- /Tip:/ Use `join` to write a @square@ function.
--
-- /Tip:/ Use library functions: @Optional#contains@, @Data.Char#digitToInt@.
--
-- >>> isHappy 4
-- False
--
-- >>> isHappy 7
-- True
--
-- >>> isHappy 42
-- False
--
-- >>> isHappy 44
-- True
isHappy ::
  Integer
  -> Bool
isHappy = (contains 1) . firstRepeat . (produce sumAndSquareDigits)
  where sumAndSquareDigits = toInteger . sum . (map square) . digits
        digits = (map digitToInt) . show'
