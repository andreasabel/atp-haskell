{-# LANGUAGE FlexibleContexts, GADTs, MultiParamTypeClasses, OverloadedStrings, ScopedTypeVariables #-}
-- | Prenex and Skolem normal forms.
--
-- Copyright (c) 2003-2007, John Harrison. (See "LICENSE.txt" for details.)
module Skolem where

import Control.Monad.Identity (Identity, runIdentity)
import Control.Monad.State (runStateT, StateT)
import Data.Map as Map (singleton)
import Data.Monoid ((<>))
import Data.Set as Set (member, Set, toAscList)
import Data.String (IsString(fromString))
import FOL
import Formulas
--import Lib
import Prop hiding (nnf)
import Test.HUnit
import Text.PrettyPrint.HughesPJClass (Pretty(pPrint), text)

-- | Routine simplification. Like "psimplify" but with quantifier clauses.
simplify1 :: (atom ~ FOL predicate formula) => Formula atom -> Formula atom
simplify1 fm =
  case fm of
    Forall x p -> if member x (fv p) then fm else p
    Exists x p -> if member x (fv p) then fm else p
    _ -> psimplify1 fm

simplify :: (atom ~ FOL predicate formula) => Formula atom -> Formula atom
simplify fm =
  case fm of
    Not p -> simplify1 (Not (simplify p))
    And p q -> simplify1 (And (simplify p) (simplify q))
    Or p q -> simplify1 (Or (simplify p) (simplify q))
    Imp p q -> simplify1 (Imp (simplify p) (simplify q))
    Iff p q -> simplify1 (Iff (simplify p) (simplify q))
    Forall x p -> simplify1 (Forall x (simplify p))
    Exists x p -> simplify1 (Exists x (simplify p))
    _ -> fm

-- Example.

-- | Use a predicate to combine some terms into a formula.
pApp :: predicate -> [Term function] -> Formula (FOL predicate function)
pApp p args = Atom $ R p args

test01 :: Test
test01 = TestCase $ assertEqual "simplify (p. 140)" expected input
    where input = simplify fm
          expected = (for_all "x" (pApp "P" [vt "x"])) .=>. (pApp "Q" []) :: Formula (FOL Predicate FName)
          fm :: Formula (FOL Predicate function)
          fm = (for_all "x" (for_all "y" (pApp "P" [vt "x"] .|. (pApp "P" [vt "y"] .&. false)))) .=>. exists "z" (pApp "Q" [])

-- | Negation normal form.
nnf :: forall a. Formula a -> Formula a
nnf fm =
  case fm of
    And p q -> And (nnf p) (nnf q)
    Or p q -> Or (nnf p) (nnf q)
    Imp p q -> Or (nnf (Not p)) (nnf q)
    Iff p q -> Or (And (nnf p) (nnf q)) (And (nnf (Not p)) (nnf (Not q)))
    Not (Not p) -> nnf p
    Not (And p q) -> Or (nnf (Not p)) (nnf (Not q))
    Not (Or p q) -> And (nnf (Not p)) (nnf (Not q))
    Not (Imp p q) -> And (nnf p) (nnf (Not q))
    Not (Iff p q) -> Or (And (nnf p) (nnf (Not q))) (And (nnf (Not p)) (nnf q))
    Forall x p -> Forall x (nnf p)
    Exists x p -> Exists x (nnf p)
    Not (Forall x p) -> Exists x (nnf (Not p))
    Not (Exists x p) -> Forall x (nnf (Not p))
    _ -> fm

-- Example of NNF function in action.
test02 :: Test
test02 = TestCase $ assertEqual "nnf (p. 140)" expected input
    where p = "P"
          q = "Q"
          input = nnf fm
          expected = exists "x" ((.~.)(pApp p [vt "x"])) .|.
                     ((exists "y" (pApp q [vt "y"]) .&. exists "z" ((pApp p [vt "z"]) .&. (pApp q [vt "z"]))) .|.
                      (for_all "y" ((.~.)(pApp q [vt "y"])) .&.
                       for_all "z" (((.~.)(pApp p [vt "z"])) .|. ((.~.)(pApp q [vt "z"])))) :: Formula (FOL Predicate FName))
          fm :: Formula (FOL Predicate function)
          fm = (for_all "x" (pApp p [vt "x"])) .=>. ((exists "y" (pApp q [vt "y"])) .<=>. exists "z" (pApp p [vt "z"] .&. pApp q [vt "z"]))

-- | Prenex normal form.
pullquants :: (atom ~ FOL predicate function) => Formula atom -> Formula atom
pullquants fm =
  case fm of
    And (Forall (x) (p)) (Forall (y) (q)) ->
                          pullq (True,True) fm Forall And x y p q
    Or (Exists (x) (p)) (Exists (y) (q)) ->
                          pullq (True,True) fm Exists Or x y p q
    And (Forall (x) (p)) (q) -> pullq (True,False) fm Forall And x x p q
    And (p) (Forall (y) (q)) -> pullq (False,True) fm Forall And y y p q
    Or (Forall (x) (p)) (q) ->  pullq (True,False) fm Forall Or x x p q
    Or (p) (Forall (y) (q)) ->  pullq (False,True) fm Forall Or y y p q
    And (Exists (x) (p)) (q) -> pullq (True,False) fm Exists And x x p q
    And (p) (Exists (y) (q)) -> pullq (False,True) fm Exists And y y p q
    Or (Exists (x) (p)) (q) ->  pullq (True,False) fm Exists Or x x p q
    Or (p) (Exists (y) (q)) ->  pullq (False,True) fm Exists Or y y p q
    _ -> fm

pullq :: (atom ~ FOL predicate function) =>
         (Bool, Bool)
      -> Formula atom
      -> (V -> Formula atom -> Formula atom)
      -> (Formula atom -> Formula atom -> Formula atom)
      -> V
      -> V
      -> Formula atom
      -> Formula atom
      -> Formula atom
pullq (l,r) fm quant op x y p q =
  let z = variant x (fv fm) in
  let p' = if l then subst (Map.singleton x (Var z)) p else p
      q' = if r then subst (Map.singleton y (Var z)) q else q in
  quant z (pullquants (op p' q'))

prenex :: (atom ~ FOL predicate function) => Formula atom -> Formula atom
prenex fm =
  case fm of
    Forall (x) (p) -> Forall (x) (prenex p)
    Exists (x) (p) -> Exists (x) (prenex p)
    And (p) (q) -> pullquants (And (prenex p) (prenex q))
    Or (p) (q) -> pullquants (Or (prenex p) (prenex q))
    _ -> fm

pnf :: (atom ~ FOL predicate function) => Formula atom -> Formula atom
pnf fm = prenex (nnf (simplify fm))

-- Example.

test03 :: Test
test03 = TestCase $ assertEqual "pnf (p. 144)" expected input
    where p = "P"
          q = "Q"
          r = "R"
          input = pnf fm
          expected = exists "x" (for_all "z"
                                 ((((.~.)(pApp p [vt "x"])) .&. ((.~.)(pApp r [vt "y"]))) .|.
                                  ((pApp q [vt "x"]) .|.
                                   (((.~.)(pApp p [vt "z"])) .|.
                                    ((.~.)(pApp q [vt "z"])))))) :: Formula (FOL Predicate FName)
          fm :: Formula (FOL Predicate function)
          fm = (for_all "x" (pApp p [vt "x"]) .|. (pApp r [vt "y"])) .=>.
               exists "y" (exists "z" ((pApp q [vt "y"]) .|. ((.~.)(exists "z" (pApp p [vt "z"] .&. pApp q [vt "z"])))))


-- | Get the functions in a term and formula.
functions :: (f ~ String) => (atom -> Set (f, Int)) -> Formula atom -> Set (f, Int)
functions fa fm =
    case fm of
      Atom a -> fa a
      Not p -> functions fa p
      And p q -> functions fa p <> functions fa q
      Or p q -> functions fa p <> functions fa q
      Imp p q -> functions fa p <> functions fa q
      Iff p q -> functions fa p <> functions fa q
      Forall _ p -> functions fa p
      Exists _ p -> functions fa p
      F -> mempty
      T -> mempty

-- -------------------------------------------------------------------------
-- State monad for generating Skolem functions and constants.
-- -------------------------------------------------------------------------

-- | The original code generates skolem functions by adding a prefix to
-- the variable name they are based on.  Here we have a more general
-- and type safe solution: we require that variables be instances of
-- class Skolem which creates Skolem functions based on an integer.
-- This state value exists in the SkolemT monad during skolemization
-- and tracks the next available number and the current list of
-- universally quantified variables.

data SkolemState
    = SkolemState
      { skolemCount :: Int
        -- ^ The next available Skolem number.
      , univQuant :: [String]
        -- ^ The variables which are universally quantified in the
        -- current scope, in the order they were encountered.  During
        -- Skolemization these are the parameters passed to the Skolem
        -- function.
      }

-- | Skolem functions are created to replace an an existentially
-- quantified variable.  The idea is that if we have a predicate
-- P[x,y,z], and z is existentially quantified, then P is satisfiable
-- if there is at least one z that causes P to be true.  We postulate
-- a skolem function sKz[x,y] whose value is one of the z's that cause
-- P to be satisfied.  The value of sKz will depend on x and y, so we
-- make these parameters.  Thus we have eliminated existential
-- quantifiers and obtained the formula P[x,y,sKz[x,y]].

-- | The state associated with the Skolem monad.
newSkolemState :: SkolemState
newSkolemState
    = SkolemState
      { skolemCount = 1
      , univQuant = []
      }

-- | The Skolem monad transformer
type SkolemT m = StateT SkolemState m

-- | Run a computation in the Skolem monad.
runSkolem :: SkolemT Identity a -> a
runSkolem = runIdentity . runSkolemT

-- | The Skolem monad
type SkolemM v term = StateT SkolemState Identity

-- | Run a computation in a stacked invocation of the Skolem monad.
runSkolemT :: Monad m => SkolemT m a -> m a
runSkolemT action = (runStateT action) newSkolemState >>= return . fst

-- | Class of functions that include embedded Skolem functions
class Skolem function var where
    toSkolem :: var -> function
    fromSkolem :: function -> Maybe var

-- | Core Skolemization function.
--
-- Skolemize the formula by removing the existential quantifiers and
-- replacing the variables they quantify with skolem functions (and
-- constants, which are functions of zero variables.)  The Skolem
-- functions are new functions (obtained from the SkolemT monad) which
-- are applied to the list of variables which are universally
-- quantified in the context where the existential quantifier
-- appeared.
skolem :: (Monad m, Skolem function V, atom ~ FOL predicate function) =>
          Formula atom -> SkolemT m (Formula atom)
skolem fm =
    case fm of
      Atom a -> return $ atomic a
      T -> return true
      F -> return false
      -- foldFirstOrder qu co (return . fromBool) (return . atomic) fm
      -- We encountered an existentially quantified variable y,
      -- allocate a new skolem function fx and do a substitution to
      -- replace occurrences of y with fx.  The value of the Skolem
      -- function is assumed to equal the value of y which satisfies
      -- the formula.
      Exists y p ->
          do let xs = fv fm
             let fx = fApp (toSkolem y) (map vt (Set.toAscList xs))
             skolem (subst (Map.singleton y fx) p)
      Forall x p -> skolem p >>= return . for_all x
      And l r -> skolem2 (.&.) l r
      Or l r -> skolem2 (.|.) l r
      _ -> return fm

skolem2 :: (Monad m, Skolem function V, atom ~ FOL predicate function) =>
           (Formula atom -> Formula atom -> Formula atom) -> Formula atom -> Formula atom -> SkolemT m (Formula atom)
skolem2 cons p q =
    skolem p >>= \ p' ->
    skolem q >>= \ q' ->
    return (cons p' q')

-- | Overall Skolemization function.
askolemize :: (Monad m, Skolem function V, atom ~ FOL predicate function) =>
              Formula atom -> SkolemT m (Formula atom)
askolemize = skolem . nnf . simplify

-- | Remove the leading universal quantifiers.  After a call to pnf
-- this will be all the universal quantifiers, and the skolemization
-- will have already turned all the existential quantifiers into
-- skolem functions.
specialize :: Formula atom -> Formula atom
specialize f =
    case f of
      Forall _x p -> specialize p
      _ -> f

-- | Skolemize and then specialize.  Because we know all quantifiers
-- are gone we can convert to any instance of PropositionalFormula.
skolemize :: (Monad m, Skolem function V, atom ~ FOL predicate function) =>
             (atom -> atom2)
          -> Formula atom
          -> SkolemT m (Formula atom)
skolemize _ca fm = (specialize . pnf) <$> askolemize fm

-- | A function type that is an instance of Skolem
data Function
    = Fn String
    | Skolem V
    deriving (Eq, Ord)

instance IsString Function where
    fromString = Fn

instance Show Function where
    show (Fn s) = show s
    show (Skolem v) = "(toSkolem " ++ show v ++ ")"

instance Pretty Function where
    pPrint (Fn s) = text s
    pPrint (Skolem v) = text "sK" <> pPrint v

instance Skolem Function V where
    toSkolem = Skolem
    fromSkolem (Skolem v) = Just v
    fromSkolem _ = Nothing

-- Example.

test04 :: Test
test04 = TestCase $ assertEqual "skolemize 1 (p. 150)" expected input
    where input = runSkolem (skolemize id fm) :: Formula (FOL Predicate Function)
          fm :: Formula (FOL Predicate Function)
          fm = exists "y" (pApp ("<") [vt "x", vt "y"] .=>.
                           for_all "u" (exists "v" (pApp ("<") [fApp "*" [vt "x", vt "u"],  fApp "*" [vt "y", vt "v"]])))
          expected = ((.~.)(pApp ("<") [vt "x",fApp (Skolem "y") [vt "x"]])) .|.
                     (pApp ("<") [fApp "*" [vt "x",vt "u"],fApp "*" [fApp (Skolem "y") [vt "x"],fApp (Skolem "v") [vt "u",vt "x"]]])

test05 :: Test
test05 = TestCase $ assertEqual "skolemize 2 (p. 150)" expected input
    where p = "P"
          q = "Q"
          input = runSkolem (skolemize id fm) :: Formula (FOL Predicate Function)
          fm :: Formula (FOL Predicate Function)
          fm = for_all "x" ((pApp p [vt "x"]) .=>.
                            (exists "y" (exists "z" ((pApp q [vt "y"]) .|.
                                                     ((.~.)(exists "z" ((pApp p [vt "z"]) .&. (pApp q [vt "z"]))))))))
          expected = ((.~.)(pApp p [vt "x"])) .|.
                     ((pApp q [fApp (Skolem "y") []]) .|.
                      (((.~.)(pApp p [vt "z"])) .|.
                       ((.~.)(pApp q [vt "z"]))))

tests :: Test
tests = TestList [test01, test02, test03, test04, test05]
