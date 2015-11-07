-- | Basic stuff for first order logic.  'IsQuantified' is a subclass
-- of 'IsPropositional' of formula types that support existential and
-- universal quantification.
--
-- Copyright (c) 2003-2007, John Harrison. (See "LICENSE.txt" for details.)

{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE UndecidableInstances #-}

module FOL
    ( -- * Variables
      IsVariable(variant, prefix)
    , variants
    --, showVariable
    , V(V)
    -- * Functions
    , IsFunction(variantFunction)
    , Arity
    , FName(FName)
    -- * Terms
    , IsTerm(TVarOf, FunOf, vt, fApp, foldTerm)
    , zipTerms
    , convertTerm
    , prettyTerm
    , prettyFunctionApply
    , showTerm
    , showFunctionApply
    , funcs
    , Term(Var, FApply)
    -- * Atoms and Predicates
    , IsPredicate
    , HasApply(TermOf, PredOf, applyPredicate, foldApply', overterms, onterms)
    , atomFuncs
    , functions
    , JustApply
    , foldApply
    , prettyApply
    , overtermsApply
    , ontermsApply
    , zipApplys
    , showApply
    , convertApply
    , onformula
    -- * Atoms supporting Equate
    , HasApplyAndEquate(equate, foldEquate)
    , zipEquates
    , isEquate
    , prettyEquate
    , overtermsEq
    , ontermsEq
    , showApplyAndEquate
    , showEquate
    , convertEquate
    , precedenceEquate
    , associativityEquate
    , Predicate
    , FOLAP(AP)
    , FOL(R, Equals)
    -- * Quantified Formulas
    , pApp
    , (.=.)
    , Quant((:!:), (:?:))
    , IsQuantified(VarOf, quant, foldQuantified)
    , for_all, (∀)
    , exists, (∃)
    , precedenceQuantified
    , associativityQuantified
    , prettyQuantified
    , showQuantified
    , zipQuantified
    , convertQuantified
    , onatomsQuantified
    , overatomsQuantified
    , IsFirstOrder
    , QFormula(F, T, Atom, Not, And, Or, Imp, Iff, Forall, Exists)
    -- * Semantics
    , Interp
    , holds
    , holdsQuantified
    , holdsAtom
    , termval
    -- * Free Variables
    , var
    , fv, fva, fvt
    , generalize
    -- * Substitution
    , subst, substq, asubst, tsubst, lsubst
    , bool_interp
    , mod_interp
    -- * Concrete instances of types for use in unit tests.
    , FTerm, ApAtom, EqAtom, ApFormula, EqFormula
    -- * Tests
    , testFOL
    ) where

import Data.Data (Data)
--import Data.Function (on)
import Data.Map as Map (empty, fromList, insert, lookup, Map)
import Data.Maybe (fromMaybe)
import Data.Set as Set (difference, empty, fold, fromList, insert, member, Set, singleton, union, unions)
import Data.String (IsString(fromString))
import Data.Typeable (Typeable)
import Formulas (false, HasBoolean(..), IsAtom, IsFormula(..), onatoms, prettyBool, true)
import Lib (setAny, tryApplyD, undefine, (|->))
import Lit ((.~.), foldLiteral, IsLiteral(foldLiteral'), IsNegatable(..), JustLiteral)
import Prelude hiding (pred)
import Pretty ((<>), Associativity(InfixN, InfixR, InfixA), Doc, HasFixity(precedence, associativity), Precedence,
               prettyShow, Side(Top, LHS, RHS, Unary), testParen, text,
               andPrec, orPrec, impPrec, iffPrec, notPrec, atomPrec, leafPrec, quantPrec, eqPrec, pAppPrec)
import Prop (BinOp(..), binop, IsCombinable(..), IsPropositional(foldPropositional'))
import Text.PrettyPrint (parens, brackets, punctuate, comma, fcat, fsep, space)
import Text.PrettyPrint.HughesPJClass (maybeParens, Pretty(pPrint, pPrintPrec), PrettyLevel)
import Test.HUnit

---------------
-- VARIABLES --
---------------

class (Ord v, IsString v, Pretty v, Show v) => IsVariable v where
    variant :: v -> Set v -> v
    -- ^ Return a variable based on v but different from any set
    -- element.  The result may be v itself if v is not a member of
    -- the set.
    prefix :: String -> v -> v
    -- ^ Modify a variable by adding a prefix.  This unfortunately
    -- assumes that v is "string-like" but at least one algorithm in
    -- Harrison currently requires this.

-- | Return an infinite list of variations on v
variants :: IsVariable v => v -> [v]
variants v0 =
    loop Set.empty v0
    where loop s v = let v' = variant v s in v' : loop (Set.insert v s) v'

-- | Because IsString is a superclass we can just output a string expression
showVariable :: IsVariable v => v -> String
showVariable v = show (prettyShow v)

newtype V = V String deriving (Eq, Ord, Data, Typeable, Read)

instance IsVariable String where
    variant v vs = if Set.member v vs then variant (v ++ "'") vs else v
    prefix pre s = pre ++ s

instance IsVariable V where
    variant v@(V s) vs = if Set.member v vs then variant (V (s ++ "'")) vs else v
    prefix pre (V s) = V (pre ++ s)

instance IsString V where
    fromString = V

instance Show V where
    show (V s) = show s

instance Pretty V where
    pPrint (V s) = text s

---------------
-- FUNCTIONS --
---------------

class (IsString function, Ord function, Pretty function, Show function) => IsFunction function where
    variantFunction :: function -> Set function -> function
    -- ^ Return a function based on f but different from any set
    -- element.  The result may be f itself if f is not a member of
    -- the set.

type Arity = Int

-- | A simple type to use as the function parameter of Term.  The only
-- reason to use this instead of String is to get nicer pretty
-- printing.
newtype FName = FName String deriving (Eq, Ord)

instance IsFunction FName where
    variantFunction f@(FName s) fns | Set.member f fns = variantFunction (fromString (s ++ "'")) fns
    variantFunction f _ = f

instance IsString FName where fromString = FName

instance Show FName where show (FName s) = s

instance Pretty FName where pPrint (FName s) = text s

-----------
-- TERMS --
-----------

-- | A term is an expression representing a domain element, either as
-- a variable reference or a function applied to a list of terms.
class (Eq term, Ord term, Pretty term, Show term, IsString term,
       IsVariable (TVarOf term), IsFunction (FunOf term)) => IsTerm term where
    type TVarOf term
    -- ^ The associated variable type
    type FunOf term
    -- ^ The associated function type
    vt :: TVarOf term -> term
    -- ^ Build a term which is a variable reference.
    fApp :: FunOf term -> [term] -> term
    -- ^ Build a term by applying terms to an atomic function ('FunOf' @term@).
    foldTerm :: (TVarOf term -> r)          -- ^ Variable references are dispatched here
             -> (FunOf term -> [term] -> r) -- ^ Function applications are dispatched here
             -> term -> r
    -- ^ A fold over instances of 'IsTerm'.

-- | Combine two terms if they are similar (i.e. two variables or
-- two function applications.)
zipTerms :: (IsTerm term1, v1 ~ TVarOf term1, function1 ~ FunOf term1,
             IsTerm term2, v2 ~ TVarOf term2, function2 ~ FunOf term2) =>
            (v1 -> v2 -> Maybe r) -- ^ Combine two variables
         -> (function1 -> [term1] -> function2 -> [term2] -> Maybe r) -- ^ Combine two function applications
         -> term1
         -> term2
         -> Maybe r -- ^ Result for dissimilar terms is 'Nothing'.
zipTerms v ap t1 t2 =
    foldTerm v' ap' t1
    where
      v' v1 =      foldTerm     (v v1)   (\_ _ -> Nothing) t2
      ap' p1 ts1 = foldTerm (\_ -> Nothing) (\p2 ts2 -> if length ts1 == length ts2 then ap p1 ts1 p2 ts2 else Nothing)   t2

-- | Convert between two instances of IsTerm
convertTerm :: (IsTerm term1, v1 ~ TVarOf term1, f1 ~ FunOf term1,
                IsTerm term2, v2 ~ TVarOf term2, f2 ~ FunOf term2) =>
               (v1 -> v2) -- ^ convert a variable
            -> (f1 -> f2) -- ^ convert a function
            -> term1 -> term2
convertTerm cv cf = foldTerm (vt . cv) (\f ts -> fApp (cf f) (map (convertTerm cv cf) ts))

prettyTerm :: (v ~ TVarOf term, function ~ FunOf term, IsTerm term, Pretty v, Pretty function) => term -> Doc
prettyTerm = foldTerm pPrint prettyFunctionApply

-- | Format a function application: F(x,y)
prettyFunctionApply :: (function ~ FunOf term, IsTerm term) => function -> [term] -> Doc
prettyFunctionApply f [] = pPrint f
prettyFunctionApply f ts = pPrint f <> parens (fsep (punctuate comma (map prettyTerm ts)))

showTerm :: (v ~ TVarOf term, function ~ FunOf term, IsTerm term, Pretty v, Pretty function) => term -> String
showTerm = foldTerm showVariable showFunctionApply

showFunctionApply :: (v ~ TVarOf term, function ~ FunOf term, IsTerm term) => function -> [term] -> String
showFunctionApply f ts = "fApp (" <> show f <> ")" <> show (brackets (fsep (punctuate (comma <> space) (map (text . show) ts))))

funcs :: (IsTerm term, function ~ FunOf term) => term -> Set (function, Arity)
funcs = foldTerm (\_ -> Set.empty) (\f ts -> Set.singleton (f, length ts))

data Term function v
    = Var v
    | FApply function [Term function v]
    deriving (Eq, Ord, Data, Typeable, Read)

instance (IsVariable v, IsFunction function) => IsString (Term function v) where
    fromString = Var . fromString

instance (IsVariable v, IsFunction function) => Show (Term function v) where
    show = showTerm

instance (IsFunction function, IsVariable v) => IsTerm (Term function v) where
    type TVarOf (Term function v) = v
    type FunOf (Term function v) = function
    vt = Var
    fApp = FApply
    foldTerm vf fn t =
        case t of
          Var v -> vf v
          FApply f ts -> fn f ts

instance (IsTerm (Term function v)) => Pretty (Term function v) where
    pPrint = prettyTerm

-- Example.
test00 :: Test
test00 = TestCase $ assertEqual "print an expression"
                                "sqrt(-(1, cos(power(+(x, y), 2))))"
                                (prettyShow (fApp "sqrt" [fApp "-" [fApp "1" [],
                                                                     fApp "cos" [fApp "power" [fApp "+" [Var "x", Var "y"],
                                                                                               fApp "2" []]]]] :: Term FName V))

---------------------------
-- ATOMS (Atomic Formula) AND PREDICATES --
---------------------------

-- | A predicate is the thing we apply to a list of 'IsTerm's to make
-- an 'IsAtom'.
class (Eq predicate, Ord predicate, Show predicate, IsString predicate, Pretty predicate) => IsPredicate predicate

class (IsAtom atom, IsPredicate (PredOf atom), IsTerm (TermOf atom)) => HasApply atom where
    type PredOf atom
    type TermOf atom
    applyPredicate :: PredOf atom -> [(TermOf atom)] -> atom
    foldApply' :: (atom -> r) -> (PredOf atom -> [(TermOf atom)] -> r) -> atom -> r
    overterms :: ((TermOf atom) -> r -> r) -> r -> atom -> r
    onterms :: ((TermOf atom) -> (TermOf atom)) -> atom -> atom

-- | The set of functions in an atom.
atomFuncs :: (HasApply atom, function ~ FunOf (TermOf atom)) => atom -> Set (function, Arity)
atomFuncs = overterms (Set.union . funcs) mempty

-- | The set of functions in a formula.
functions :: (IsFormula formula, HasApply atom, Ord function,
              atom ~ AtomOf formula,
              term ~ TermOf atom,
              function ~ FunOf term) =>
             formula -> Set (function, Arity)
functions fm = overatoms (Set.union . atomFuncs) fm mempty

-- | Atoms that have apply but do not support equate
class HasApply atom => JustApply atom

foldApply :: (JustApply atom, term ~ TermOf atom) => (PredOf atom -> [term] -> r) -> atom -> r
foldApply = foldApply' (error "JustApply failure")

-- | Pretty print prefix application of a predicate
prettyApply :: (v ~ TVarOf term, IsPredicate predicate, IsTerm term) => predicate -> [term] -> Doc
prettyApply p ts = pPrint p <> parens (fcat (punctuate comma (map pPrint ts)))

-- | Implementation of 'overterms' for 'HasApply' types.
overtermsApply :: JustApply atom => ((TermOf atom) -> r -> r) -> r -> atom -> r
overtermsApply f r0 = foldApply (\_ ts -> foldr f r0 ts)

-- | Implementation of 'onterms' for 'HasApply' types.
ontermsApply :: JustApply atom => ((TermOf atom) -> (TermOf atom)) -> atom -> atom
ontermsApply f = foldApply (\p ts -> applyPredicate p (map f ts))

-- | Zip two atoms if they are similar
zipApplys :: (JustApply atom, term ~ TermOf atom, predicate ~ PredOf atom) =>
                 (predicate -> [(term, term)] -> Maybe r) -> atom -> atom -> Maybe r
zipApplys f atom1 atom2 =
    foldApply f' atom1
    where
      f' p1 ts1 = foldApply (\p2 ts2 ->
                                     if p1 /= p2 || length ts1 /= length ts2
                                     then Nothing
                                     else f p1 (zip ts1 ts2)) atom2

-- | Implementation of 'Show' for 'JustApply' types
showApply :: (Show predicate, Show term) => predicate -> [term] -> String
showApply p ts = show (text "pApp " <> parens (text (show p)) <> brackets (fcat (punctuate (comma <> space) (map (text . show) ts))))

-- | Convert between two instances of 'HasApply'
convertApply :: (JustApply atom1, HasApply atom2) =>
                (PredOf atom1 -> PredOf atom2) -> (TermOf atom1 -> TermOf atom2) -> atom1 -> atom2
convertApply cp ct = foldApply (\p1 ts1 -> applyPredicate (cp p1) (map ct ts1))

-- | Special case of applying a subfunction to the top *terms*.
onformula :: (IsFormula formula, HasApply atom, atom ~ AtomOf formula, term ~ TermOf atom) =>
             (term -> term) -> formula -> formula
onformula f = onatoms (atomic . onterms f)

---------------------------------
-- ATOM with the Equate predicate
---------------------------------

-- | Atoms that support equality must have HasApplyAndEquate instance
class HasApply atom => HasApplyAndEquate atom where
    equate :: TermOf atom -> TermOf atom -> atom
    foldEquate :: (TermOf atom -> TermOf atom -> r) -> (PredOf atom -> [TermOf atom] -> r) -> atom -> r

-- | Zip two atoms that support equality
zipEquates :: HasApplyAndEquate atom =>
              (TermOf atom -> TermOf atom ->
               TermOf atom -> TermOf atom -> Maybe r)
           -> (PredOf atom -> [(TermOf atom, TermOf atom)] -> Maybe r)
           -> atom -> atom -> Maybe r
zipEquates eq ap atom1 atom2 =
    foldEquate eq' ap' atom1
    where
      eq' l1 r1 = foldEquate (eq l1 r1) (\_ _ -> Nothing) atom2
      ap' p1 ts1 = foldEquate (\_ _ -> Nothing) (ap'' p1 ts1) atom2
      ap'' p1 ts1 p2 ts2 | p1 == p2 && length ts1 == length ts2 = ap p1 (zip ts1 ts2)
      ap'' _ _ _ _ = Nothing

isEquate :: HasApplyAndEquate atom => atom -> Bool
isEquate = foldEquate (\_ _ -> True) (\_ _ -> False)

-- | Format the infix equality predicate applied to two terms.
prettyEquate :: IsTerm term => PrettyLevel -> Rational -> term -> term -> Doc
prettyEquate l p t1 t2 =
    maybeParens (p > atomPrec) $ pPrintPrec l atomPrec t1 <> text "=" <> pPrintPrec l atomPrec t2

-- | Implementation of 'overterms' for 'HasApply' types.
overtermsEq :: HasApplyAndEquate atom => ((TermOf atom) -> r -> r) -> r -> atom -> r
overtermsEq f r0 = foldEquate (\t1 t2 -> f t2 (f t1 r0)) (\_ ts -> foldr f r0 ts)

-- | Implementation of 'onterms' for 'HasApply' types.
ontermsEq :: HasApplyAndEquate atom => ((TermOf atom) -> (TermOf atom)) -> atom -> atom
ontermsEq f = foldEquate (\t1 t2 -> equate (f t1) (f t2)) (\p ts -> applyPredicate p (map f ts))

-- | Implementation of Show for HasApplyAndEquate types
showApplyAndEquate :: (HasApplyAndEquate atom, Show (TermOf atom)) => atom -> String
showApplyAndEquate atom = foldEquate showEquate showApply atom

showEquate :: Show term => term -> term -> String
showEquate t1 t2 = "(" ++ show t1 ++ ") .=. (" ++ show t2 ++ ")"

convertEquate :: (HasApplyAndEquate atom1, HasApplyAndEquate atom2) =>
                 (PredOf atom1 -> PredOf atom2) -> (TermOf atom1 -> TermOf atom2) -> atom1 -> atom2
convertEquate cp ct = foldEquate (\t1 t2 -> equate (ct t1) (ct t2)) (\p1 ts1 -> applyPredicate (cp p1) (map ct ts1))

precedenceEquate :: HasApplyAndEquate atom => atom -> Precedence
precedenceEquate = foldEquate (\_ _ -> eqPrec) (\_ _ -> pAppPrec)

associativityEquate :: HasApplyAndEquate atom => atom -> Associativity
associativityEquate = foldEquate (\_ _ -> Pretty.InfixN) (\_ _ -> Pretty.InfixN)

-- | A predicate type with no distinct equality.
data Predicate = NamedPred String
    deriving (Eq, Ord, Data, Typeable, Read)

instance IsString Predicate where

    -- fromString "True" = error "bad predicate name: True"
    -- fromString "False" = error "bad predicate name: True"
    -- fromString "=" = error "bad predicate name: True"
    fromString s = NamedPred s

instance Show Predicate where
    show (NamedPred s) = "fromString " ++ show s

instance Pretty Predicate where
    pPrint (NamedPred "=") = error "Use of = as a predicate name is prohibited"
    pPrint (NamedPred "True") = error "Use of True as a predicate name is prohibited"
    pPrint (NamedPred "False") = error "Use of False as a predicate name is prohibited"
    pPrint (NamedPred s) = text s

instance IsPredicate Predicate

-- | First order logic formula atom type.
data FOLAP predicate term = AP predicate [term] deriving (Eq, Ord, Data, Typeable, Read)

instance (IsPredicate predicate, IsTerm term) => JustApply (FOLAP predicate term)

instance (IsPredicate predicate, IsTerm term) => IsAtom (FOLAP predicate term)

instance (IsPredicate predicate, IsTerm term) => Pretty (FOLAP predicate term) where
    pPrint = foldApply prettyApply

instance (IsPredicate predicate, IsTerm term) => HasApply (FOLAP predicate term) where
    type PredOf (FOLAP predicate term) = predicate
    type TermOf (FOLAP predicate term) = term
    applyPredicate = AP
    foldApply' _ f (AP p ts) = f p ts
    overterms f r (AP _ ts) = foldr f r ts
    onterms f (AP p ts) = AP p (map f ts)

instance (IsPredicate predicate, IsTerm term, Show predicate, Show term) => Show (FOLAP predicate term) where
    show = foldApply (\p ts -> showApply (p :: predicate) (ts :: [term]))

instance HasFixity (FOLAP predicate term) where
    precedence _ = pAppPrec
    associativity _ = Pretty.InfixN

-- | First order logic formula atom type with a distinct equality
-- predicate.
data FOL predicate term = R predicate [term] | Equals term term deriving (Eq, Ord, Data, Typeable, Read)

instance (IsPredicate predicate, IsTerm term) => HasApplyAndEquate (FOL predicate term) where
    equate lhs rhs = Equals lhs rhs
    foldEquate eq _ (Equals lhs rhs) = eq lhs rhs
    foldEquate _ ap (R p ts) = ap p ts

instance (IsPredicate predicate, IsTerm term) => IsAtom (FOL predicate term)

instance (HasApply (FOL predicate term),
          HasApplyAndEquate (FOL predicate term), IsTerm term) => Pretty (FOL predicate term) where
    pPrintPrec d r = foldEquate (prettyEquate d r) prettyApply

instance (IsPredicate predicate, IsTerm term) => HasApply (FOL predicate term) where
    type PredOf (FOL predicate term) = predicate
    type TermOf (FOL predicate term) = term
    applyPredicate = R
    foldApply' _ f (R p ts) = f p ts
    foldApply' d _ x = d x
    overterms = overtermsEq
    onterms = ontermsEq

instance (IsPredicate predicate, IsTerm term, Show predicate, Show term) => Show (FOL predicate term) where
    show = foldEquate (\t1 t2 -> showEquate (t1 :: term) (t2 :: term))
                      (\p ts -> showApply (p :: predicate) (ts :: [term]))

instance  (IsPredicate predicate, IsTerm term) => HasFixity (FOL predicate term) where
    precedence = precedenceEquate
    associativity = associativityEquate

--------------
-- FORMULAS --
--------------

-- | Build a formula from a predicate and a list of terms.
pApp :: (IsFormula formula, HasApply atom, atom ~ AtomOf formula) => PredOf atom -> [TermOf atom] -> formula
pApp p args = atomic (applyPredicate p args)

-- | Build an equality formula from two terms.
(.=.) :: (IsFormula formula, HasApplyAndEquate atom, atom ~ AtomOf formula) => TermOf atom -> TermOf atom -> formula
a .=. b = atomic (equate a b)
infix 6 .=.

-- | The two types of quantification
data Quant
    = (:!:) -- ^ for_all
    | (:?:) -- ^ exists
    deriving (Eq, Ord, Data, Typeable, Show)

-- | Class of quantified formulas.
class (IsPropositional formula, IsVariable (VarOf formula)) => IsQuantified formula where
    type (VarOf formula) -- A type function mapping formula to the associated variable
    quant :: Quant -> VarOf formula -> formula -> formula
    foldQuantified :: (Quant -> VarOf formula -> formula -> r)
                   -> (formula -> BinOp -> formula-> r)
                   -> (formula -> r)
                   -> (Bool -> r)
                   -> (AtomOf formula -> r)
                   -> formula -> r

for_all :: IsQuantified formula => VarOf formula -> formula -> formula
for_all = quant (:!:)
exists :: IsQuantified formula => VarOf formula -> formula -> formula
exists = quant (:?:)

-- | ∀ can't be a function when -XUnicodeSyntax is enabled.
(∀) :: IsQuantified formula => VarOf formula -> formula -> formula
infixr 1 ∀
(∀) = for_all
(∃) :: IsQuantified formula => VarOf formula -> formula -> formula
infixr 1 ∃
(∃) = exists

precedenceQuantified :: forall formula. IsQuantified formula => formula -> Precedence
precedenceQuantified = foldQuantified qu co ne tf at
    where
      qu _ _ _ = quantPrec
      co _ (:&:) _ = andPrec
      co _ (:|:) _ = orPrec
      co _ (:=>:) _ = impPrec
      co _ (:<=>:) _ = iffPrec
      ne _ = notPrec
      tf _ = leafPrec
      at = precedence

associativityQuantified :: forall formula. IsQuantified formula => formula -> Associativity
associativityQuantified = foldQuantified qu co ne tf at
    where
      qu _ _ _ = Pretty.InfixR
      ne _ = Pretty.InfixA
      co _ (:&:) _ = Pretty.InfixA
      co _ (:|:) _ = Pretty.InfixA
      co _ (:=>:) _ = Pretty.InfixR
      co _ (:<=>:) _ = Pretty.InfixA
      tf _ = Pretty.InfixN
      at = associativity

-- | Implementation of 'Pretty' for 'IsQuantified' types.
prettyQuantified :: forall fof v. (IsQuantified fof, v ~ VarOf fof) =>
                    Side -> PrettyLevel -> Rational -> fof -> Doc
prettyQuantified side l r fm =
    maybeParens (testParen side r (precedence fm) (associativity fm)) $ foldQuantified (\op v p -> qu op [v] p) co ne tf at fm
    -- maybeParens (r > precedence fm) $ foldQuantified (\op v p -> qu op [v] p) co ne tf at fm
    where
      -- Collect similarly quantified variables
      qu :: Quant -> [v] -> fof -> Doc
      qu op vs p' = foldQuantified (qu' op vs p') (\_ _ _ -> qu'' op vs p') (\_ -> qu'' op vs p')
                                                      (\_ -> qu'' op vs p') (\_ -> qu'' op vs p') p'
      qu' :: Quant -> [v] -> fof -> Quant -> v -> fof -> Doc
      qu' op vs _ op' v p' | op == op' = qu op (v : vs) p'
      qu' op vs p _ _ _ = qu'' op vs p
      qu'' :: Quant -> [v] -> fof -> Doc
      qu'' _op [] p = prettyQuantified Unary l r p
      qu'' op vs p = text (case op of (:!:) -> "∀"; (:?:) -> "∃") <>
                     fsep (map pPrint (reverse vs)) <>
                     text ". " <> prettyQuantified Unary l (precedence fm + 1) p
      co :: fof -> BinOp -> fof -> Doc
      co p (:&:) q = prettyQuantified LHS l (precedence fm) p <> text "∧" <>  prettyQuantified RHS l (precedence fm) q
      co p (:|:) q = prettyQuantified LHS l (precedence fm) p <> text "∨" <> prettyQuantified RHS l (precedence fm) q
      co p (:=>:) q = prettyQuantified LHS l (precedence fm) p <> text "⇒" <> prettyQuantified RHS l (precedence fm) q
      co p (:<=>:) q = prettyQuantified LHS l (precedence fm) p <> text "⇔" <> prettyQuantified RHS l (precedence fm) q
      ne p = text "¬" <> prettyQuantified Unary l (precedence fm) p
      tf x = pPrint x
      at x = pPrintPrec l r x -- maybeParens (d > PrettyLevel atomPrec) $ pPrint x

-- | Implementation of 'showsPrec' for 'IsQuantified' types.
showQuantified :: IsQuantified formula => Side -> Int -> formula -> ShowS
showQuantified side r fm =
    showParen (testParen side r (precedence fm) (associativity fm)) $ foldQuantified qu co ne tf at fm
    where
      qu (:!:) x p = showString "for_all " . showString (show x) . showString " " . showQuantified Unary (precedence fm + 1) p
      qu (:?:) x p = showString "exists " . showString (show x) . showString " " . showQuantified Unary (precedence fm + 1) p
      co p (:&:) q = showQuantified LHS (precedence fm) p . showString " .&. " . showQuantified RHS (precedence fm) q
      co p (:|:) q = showQuantified LHS (precedence fm) p . showString " .|. " . showQuantified RHS (precedence fm) q
      co p (:=>:) q = showQuantified LHS (precedence fm) p . showString " .=>. " . showQuantified RHS (precedence fm) q
      co p (:<=>:) q = showQuantified LHS (precedence fm) p . showString " .<=>. " . showQuantified RHS (precedence fm) q
      ne p = showString "(.~.) " . showQuantified Unary (succ (precedence fm)) p
      tf x = showsPrec (precedence fm) x
      at x = showsPrec (precedence fm) x

-- | Combine two formulas if they are similar.
zipQuantified :: IsQuantified formula =>
                 (Quant -> VarOf formula -> formula -> Quant -> VarOf formula -> formula -> Maybe r)
              -> (formula -> BinOp -> formula -> formula -> BinOp -> formula -> Maybe r)
              -> (formula -> formula -> Maybe r)
              -> (Bool -> Bool -> Maybe r)
              -> ((AtomOf formula) -> (AtomOf formula) -> Maybe r)
              -> formula -> formula -> Maybe r
zipQuantified qu co ne tf at fm1 fm2 =
    foldQuantified qu' co' ne' tf' at' fm1
    where
      qu' op1 v1 p1 = foldQuantified (qu op1 v1 p1)       (\ _ _ _ -> Nothing) (\ _ -> Nothing) (\ _ -> Nothing) (\ _ -> Nothing) fm2
      co' l1 op1 r1 = foldQuantified (\ _ _ _ -> Nothing) (co l1 op1 r1)       (\ _ -> Nothing) (\ _ -> Nothing) (\ _ -> Nothing) fm2
      ne' x1 =        foldQuantified (\ _ _ _ -> Nothing) (\ _ _ _ -> Nothing) (ne x1)          (\ _ -> Nothing) (\ _ -> Nothing) fm2
      tf' x1 =        foldQuantified (\ _ _ _ -> Nothing) (\ _ _ _ -> Nothing) (\ _ -> Nothing) (tf x1)          (\ _ -> Nothing) fm2
      at' atom1 =     foldQuantified (\ _ _ _ -> Nothing) (\ _ _ _ -> Nothing) (\ _ -> Nothing) (\ _ -> Nothing) (at atom1)       fm2

-- | Convert any instance of IsQuantified to any other by
-- specifying the result type.
convertQuantified :: forall f1 f2.
                     (IsQuantified f1, IsQuantified f2) =>
                     (AtomOf f1 -> AtomOf f2) -> (VarOf f1 -> VarOf f2) -> f1 -> f2
convertQuantified ca cv f1 =
    foldQuantified qu co ne tf at f1
    where
      qu :: Quant -> VarOf f1 -> f1 -> f2
      qu (:!:) x p = for_all (cv x :: VarOf f2) (convertQuantified ca cv p :: f2)
      qu (:?:) x p = exists (cv x :: VarOf f2) (convertQuantified ca cv p :: f2)
      co p (:&:) q = convertQuantified ca cv p .&. convertQuantified ca cv q
      co p (:|:) q = convertQuantified ca cv p .|. convertQuantified ca cv q
      co p (:=>:) q = convertQuantified ca cv p .=>. convertQuantified ca cv q
      co p (:<=>:) q = convertQuantified ca cv p .<=>. convertQuantified ca cv q
      ne p = (.~.) (convertQuantified ca cv p)
      tf :: Bool -> f2
      tf = fromBool
      at :: AtomOf f1 -> f2
      at = atomic . ca

onatomsQuantified :: IsQuantified formula => (AtomOf formula -> formula) -> formula -> formula
onatomsQuantified f fm =
    foldQuantified qu co ne tf at fm
    where
      qu op v p = quant op v (onatomsQuantified f p)
      ne p = (.~.) (onatomsQuantified f p)
      co p op q = binop (onatomsQuantified f p) op (onatomsQuantified f q)
      tf flag = fromBool flag
      at x = f x

overatomsQuantified :: IsQuantified fof => (AtomOf fof -> r -> r) -> fof -> r -> r
overatomsQuantified f fof r0 =
    foldQuantified qu co ne (const r0) (flip f r0) fof
    where
      qu _ _ fof' = overatomsQuantified f fof' r0
      ne fof' = overatomsQuantified f fof' r0
      co p _ q = overatomsQuantified f p (overatomsQuantified f q r0)

-- | Combine IsQuantified, HasApply, IsTerm, and make sure the term is
-- using the same variable type as the formula.
class (IsQuantified formula,
       HasApply (AtomOf formula),
       IsTerm (TermOf (AtomOf formula)),
       VarOf formula ~ TVarOf (TermOf (AtomOf formula)))
    => IsFirstOrder formula

data QFormula v atom
    = F
    | T
    | Atom atom
    | Not (QFormula v atom)
    | And (QFormula v atom) (QFormula v atom)
    | Or (QFormula v atom) (QFormula v atom)
    | Imp (QFormula v atom) (QFormula v atom)
    | Iff (QFormula v atom) (QFormula v atom)
    | Forall v (QFormula v atom)
    | Exists v (QFormula v atom)
    deriving (Eq, Ord, Data, Typeable, Read)

instance (HasApply atom, IsTerm term, term ~ TermOf atom, v ~ TVarOf term) => Pretty (QFormula v atom) where
    pPrintPrec = prettyQuantified Top

instance HasBoolean (QFormula v atom) where
    asBool T = Just True
    asBool F = Just False
    asBool _ = Nothing
    fromBool True = T
    fromBool False = F

instance IsNegatable (QFormula v atom) where
    naiveNegate = Not
    foldNegation normal inverted (Not x) = foldNegation inverted normal x
    foldNegation normal _ x = normal x

instance IsCombinable (QFormula v atom) where
    (.|.) = Or
    (.&.) = And
    (.=>.) = Imp
    (.<=>.) = Iff
    foldCombination other dj cj imp iff fm =
        case fm of
          Or a b -> a `dj` b
          And a b -> a `cj` b
          Imp a b -> a `imp` b
          Iff a b -> a `iff` b
          _ -> other fm

-- The IsFormula instance for QFormula
instance (HasApply atom, v ~ TVarOf (TermOf atom)) => IsFormula (QFormula v atom) where
    type AtomOf (QFormula v atom) = atom
    atomic = Atom
    overatoms = overatomsQuantified
    onatoms = onatomsQuantified

instance (IsFormula (QFormula v atom), HasApply atom, v ~ TVarOf (TermOf atom)) => IsPropositional (QFormula v atom) where
    foldPropositional' ho co ne tf at fm =
        case fm of
          And p q -> co p (:&:) q
          Or p q -> co p (:|:) q
          Imp p q -> co p (:=>:) q
          Iff p q -> co p (:<=>:) q
          _ -> foldLiteral' ho ne tf at fm

instance (IsPropositional (QFormula v atom), IsVariable v, IsAtom atom) => IsQuantified (QFormula v atom) where
    type VarOf (QFormula v atom) = v
    quant (:!:) = Forall
    quant (:?:) = Exists
    foldQuantified qu _co _ne _tf _at (Forall v fm) = qu (:!:) v fm
    foldQuantified qu _co _ne _tf _at (Exists v fm) = qu (:?:) v fm
    foldQuantified _qu co ne tf at fm =
        foldPropositional' (\_ -> error "IsQuantified QFormula") co ne tf at fm

-- Build a Haskell expression for this formula
instance IsQuantified (QFormula v atom) => Show (QFormula v atom) where
    showsPrec = showQuantified Top

-- Precedence information for QFormula
instance IsQuantified (QFormula v atom) => HasFixity (QFormula v atom) where
    precedence = precedenceQuantified
    associativity = associativityQuantified

instance (HasApply atom, v ~ TVarOf (TermOf atom)) => IsLiteral (QFormula v atom) where
    foldLiteral' ho ne tf at fm =
        case fm of
          T -> tf True
          F -> tf False
          Atom a -> at a
          Not p -> ne p
          _ -> ho fm

-- | A term type with no Skolem functions
type FTerm = Term FName V

-- | An atom type with no equality predicate
type ApAtom = FOLAP Predicate FTerm
instance JustApply ApAtom

-- | An atom type with equality predicate
type EqAtom = FOL Predicate FTerm

-- | A formula type with no equality predicate
type ApFormula = QFormula V ApAtom
instance IsFirstOrder ApFormula

-- | A formula type with equality predicate
type EqFormula = QFormula V EqAtom
instance IsFirstOrder EqFormula

{-
(* Trivial example of "x + y < z".                                           *)
(* ------------------------------------------------------------------------- *)

START_INTERACTIVE;;
Atom(R("<",[Fn("+",[Var "x"; Var "y"]); Var "z"]));;
END_INTERACTIVE;;

(* ------------------------------------------------------------------------- *)
(* Parsing of terms.                                                         *)
(* ------------------------------------------------------------------------- *)

let is_const_name s = forall numeric (explode s) or s = "nil";;

let rec parse_atomic_term vs inp =
  match inp with
    [] -> failwith "term expected"
  | "("::rest -> parse_bracketed (parse_term vs) ")" rest
  | "-"::rest -> papply (fun t -> Fn("-",[t])) (parse_atomic_term vs rest)
  | f::"("::")"::rest -> Fn(f,[]),rest
  | f::"("::rest ->
      papply (fun args -> Fn(f,args))
             (parse_bracketed (parse_list "," (parse_term vs)) ")" rest)
  | a::rest ->
      (if is_const_name a & not(mem a vs) then Fn(a,[]) else Var a),rest

and parse_term vs inp =
  parse_right_infix "::" (fun (e1,e2) -> Fn("::",[e1;e2]))
    (parse_right_infix "+" (fun (e1,e2) -> Fn("+",[e1;e2]))
       (parse_left_infix "-" (fun (e1,e2) -> Fn("-",[e1;e2]))
          (parse_right_infix "*" (fun (e1,e2) -> Fn("*",[e1;e2]))
             (parse_left_infix "/" (fun (e1,e2) -> Fn("/",[e1;e2]))
                (parse_left_infix "^" (fun (e1,e2) -> Fn("^",[e1;e2]))
                   (parse_atomic_term vs)))))) inp;;

let parset = make_parser (parse_term []);;

(* ------------------------------------------------------------------------- *)
(* Parsing of formulas.                                                      *)
(* ------------------------------------------------------------------------- *)

let parse_infix_atom vs inp =
  let tm,rest = parse_term vs inp in
  if exists (nextin rest) ["="; "<"; "<="; ">"; ">="] then
        papply (fun tm' -> Atom(R(hd rest,[tm;tm'])))
               (parse_term vs (tl rest))
  else failwith "";;

let parse_atom vs inp =
  try parse_infix_atom vs inp with Failure _ ->
  match inp with
  | p::"("::")"::rest -> Atom(R(p,[])),rest
  | p::"("::rest ->
      papply (fun args -> Atom(R(p,args)))
             (parse_bracketed (parse_list "," (parse_term vs)) ")" rest)
  | p::rest when p <> "(" -> Atom(R(p,[])),rest
  | _ -> failwith "parse_atom";;

let parse = make_parser
  (parse_formula (parse_infix_atom,parse_atom) []);;

(* ------------------------------------------------------------------------- *)
(* Set up parsing of quotations.                                             *)
(* ------------------------------------------------------------------------- *)

let default_parser = parse;;

let secondary_parser = parset;;

{-
(* ------------------------------------------------------------------------- *)
(* Example.                                                                  *)
(* ------------------------------------------------------------------------- *)

START_INTERACTIVE;;
<<(forall x. x < 2 ==> 2 * x <= 3) \/ false>>;;

<<|2 * x|>>;;
END_INTERACTIVE;;
-}

(* ------------------------------------------------------------------------- *)
(* Printing of terms.                                                        *)
(* ------------------------------------------------------------------------- *)

let rec print_term prec fm =
  match fm with
    Var x -> print_string x
  | Fn("^",[tm1;tm2]) -> print_infix_term true prec 24 "^" tm1 tm2
  | Fn("/",[tm1;tm2]) -> print_infix_term true prec 22 " /" tm1 tm2
  | Fn("*",[tm1;tm2]) -> print_infix_term false prec 20 " *" tm1 tm2
  | Fn("-",[tm1;tm2]) -> print_infix_term true prec 18 " -" tm1 tm2
  | Fn("+",[tm1;tm2]) -> print_infix_term false prec 16 " +" tm1 tm2
  | Fn("::",[tm1;tm2]) -> print_infix_term false prec 14 "::" tm1 tm2
  | Fn(f,args) -> print_fargs f args

and print_fargs f args =
  print_string f;
  if args = [] then () else
   (print_string "(";
    open_box 0;
    print_term 0 (hd args); print_break 0 0;
    do_list (fun t -> print_string ","; print_break 0 0; print_term 0 t)
            (tl args);
    close_box();
    print_string ")")

and print_infix_term isleft oldprec newprec sym p q =
  if oldprec > newprec then (print_string "("; open_box 0) else ();
  print_term (if isleft then newprec else newprec+1) p;
  print_string sym;
  print_break (if String.sub sym 0 1 = " " then 1 else 0) 0;
  print_term (if isleft then newprec+1 else newprec) q;
  if oldprec > newprec then (close_box(); print_string ")") else ();;

let printert tm =
  open_box 0; print_string "<<|";
  open_box 0; print_term 0 tm; close_box();
  print_string "|>>"; close_box();;

#install_printer printert;;

(* ------------------------------------------------------------------------- *)
(* Printing of formulas.                                                     *)
(* ------------------------------------------------------------------------- *)

let print_atom prec (R(p,args)) =
  if mem p ["="; "<"; "<="; ">"; ">="] & length args = 2
  then print_infix_term false 12 12 (" "^p) (el 0 args) (el 1 args)
  else print_fargs p args;;

let print_fol_formula = print_qformula print_atom;;

#install_printer print_fol_formula;;

(* ------------------------------------------------------------------------- *)
(* Examples in the main text.                                                *)
(* ------------------------------------------------------------------------- *)

START_INTERACTIVE;;
<<forall x y. exists z. x < z /\ y < z>>;;

<<~(forall x. P(x)) <=> exists y. ~P(y)>>;;
END_INTERACTIVE;;
-}

-- | Specify the domain of a formula interpretation, and how to
-- interpret its functions and predicates.
data Interp function predicate d
    = Interp { domain :: [d]
             , funcApply :: function -> [d] -> d
             , predApply :: predicate -> [d] -> Bool
             , eqApply :: d -> d -> Bool }

-- | The holds function computes the value of a formula for a finite domain.
class FiniteInterpretation a function predicate v dom where
    holds :: Interp function predicate dom -> Map v dom -> a -> Bool

-- | Implementation of holds for IsQuantified formulas.
holdsQuantified :: forall formula function predicate dom.
                   (IsQuantified formula,
                    FiniteInterpretation (AtomOf formula) function predicate (VarOf formula) dom,
                    FiniteInterpretation formula function predicate (VarOf formula) dom) =>
                   Interp function predicate dom -> Map (VarOf formula) dom -> formula -> Bool
holdsQuantified m v fm =
    foldQuantified qu co ne tf at fm
    where
      qu (:!:) x p = and (map (\a -> holds m (Map.insert x a v) p) (domain m)) -- >>= return . any (== True)
      qu (:?:) x p = or (map (\a -> holds m (Map.insert x a v) p) (domain m)) -- return . all (== True)?
      ne p = not (holds m v p)
      co p (:&:) q = (holds m v p) && (holds m v q)
      co p (:|:) q = (holds m v p) || (holds m v q)
      co p (:=>:) q = not (holds m v p) || (holds m v q)
      co p (:<=>:) q = (holds m v p) == (holds m v q)
      tf x = x
      at = (holds m v :: AtomOf formula -> Bool)

-- | Implementation of holds for atoms with equate predicates.
holdsAtom :: (HasApplyAndEquate atom, IsTerm term, Eq dom,
              term ~ TermOf atom, v ~ TVarOf term, function ~ FunOf term, predicate ~ PredOf atom) =>
             Interp function predicate dom -> Map v dom -> atom -> Bool
holdsAtom m v at = foldEquate (\t1 t2 -> eqApply m (termval m v t1) (termval m v t2))
                                (\r args -> predApply m r (map (termval m v) args)) at

termval :: (IsTerm term, v ~ TVarOf term, function ~ FunOf term) => Interp function predicate r -> Map v r -> term -> r
termval m v tm =
    foldTerm (\x -> fromMaybe (error ("Undefined variable: " ++ show x)) (Map.lookup x v))
             (\f args -> funcApply m f (map (termval m v) args)) tm

{-
START_INTERACTIVE;;
holds bool_interp undefined <<forall x. (x = 0) \/ (x = 1)>>;;

holds (mod_interp 2) undefined <<forall x. (x = 0) \/ (x = 1)>>;;

holds (mod_interp 3) undefined <<forall x. (x = 0) \/ (x = 1)>>;;

let fm = <<forall x. ~(x = 0) ==> exists y. x * y = 1>>;;

filter (fun n -> holds (mod_interp n) undefined fm) (1--45);;

holds (mod_interp 3) undefined <<(forall x. x = 0) ==> 1 = 0>>;;
holds (mod_interp 3) undefined <<forall x. x = 0 ==> 1 = 0>>;;
END_INTERACTIVE;;
-}

-- | Examples of particular interpretations.
bool_interp :: Interp FName Predicate Bool
bool_interp =
    Interp [False, True] func pred (==)
    where
      func f [] | f == fromString "False" = False
      func f [] | f == fromString "True" = True
      func f [x,y] | f == fromString "+" = x /= y
      func f [x,y] | f == fromString "*" = x && y
      func f _ = error ("bool_interp - uninterpreted function: " ++ show f)
      pred p _ = error ("bool_interp - uninterpreted predicate: " ++ show p)

mod_interp :: Int -> Interp FName Predicate Int
mod_interp n =
    Interp [0..(n-1)] func pred (==)
    where
      func f [] | f == fromString "0" = 0
      func f [] | f == fromString "1" = 1 `mod` n
      func f [x,y] | f == fromString "+" = (x + y) `mod` n
      func f [x,y] | f == fromString "*" = (x * y) `mod` n
      func f _ = error ("mod_interp - uninterpreted function: " ++ show f)
      pred p _ = error ("mod_interp - uninterpreted predicate: " ++ show p)

instance Eq dom => FiniteInterpretation EqFormula FName Predicate V dom where holds = holdsQuantified
instance Eq dom => FiniteInterpretation EqAtom FName Predicate V dom where holds = holdsAtom

test01 :: Test
test01 = TestCase $ assertEqual "holds bool test (p. 126)" expected input
    where input = holds bool_interp (Map.empty :: Map V Bool) (for_all "x" ((vt "x") .=. (fApp "False" []) .|. (vt "x") .=. (fApp "True" [])) :: EqFormula)
          expected = True
test02 :: Test
test02 = TestCase $ assertEqual "holds mod test 1 (p. 126)" expected input
    where input =  holds (mod_interp 2) (Map.empty :: Map V Int) (for_all "x" (vt "x" .=. (fApp "0" []) .|. vt "x" .=. (fApp "1" [])) :: EqFormula)
          expected = True
test03 :: Test
test03 = TestCase $ assertEqual "holds mod test 2 (p. 126)" expected input
    where input =  holds (mod_interp 3) (Map.empty :: Map V Int) (for_all "x" (vt "x" .=. fApp "0" [] .|. vt "x" .=. fApp "1" []) :: EqFormula)
          expected = False

test04 :: Test
test04 = TestCase $ assertEqual "holds mod test 3 (p. 126)" expected input
    where input = filter (\ n -> holds (mod_interp n) (Map.empty :: Map V Int) fm) [1..45]
                  where fm = for_all "x" ((.~.) (vt "x" .=. fApp "0" []) .=>. exists "y" (fApp "*" [vt "x", vt "y"] .=. fApp "1" [])) :: EqFormula
          expected = [1,2,3,5,7,11,13,17,19,23,29,31,37,41,43]

test05 :: Test
test05 = TestCase $ assertEqual "holds mod test 4 (p. 129)" expected input
    where input = holds (mod_interp 3) (Map.empty :: Map V Int) ((for_all "x" (vt "x" .=. fApp "0" [])) .=>. fApp "1" [] .=. fApp "0" [] :: EqFormula)
          expected = True
test06 :: Test
test06 = TestCase $ assertEqual "holds mod test 5 (p. 129)" expected input
    where input = holds (mod_interp 3) (Map.empty :: Map V Int) (for_all "x" (vt "x" .=. fApp "0" [] .=>. fApp "1" [] .=. fApp "0" []) :: EqFormula)
          expected = False

-- Free variables in terms and formulas.

-- | Find the free variables in a formula.
fv :: (IsFirstOrder formula, v ~ VarOf formula) => formula -> Set v
fv fm =
    foldQuantified qu co ne tf at fm
    where
      qu _ x p = difference (fv p) (singleton x)
      ne p = fv p
      co p _ q = union (fv p) (fv q)
      tf _ = Set.empty
      at = fva

-- | Find all the variables in a formula.
-- var :: (IsFirstOrder formula, v ~ VarOf formula) => formula -> Set v
var :: (IsFormula formula, HasApply atom,
        atom ~ AtomOf formula, term ~ TermOf atom, v ~ TVarOf term) =>
       formula -> Set v
var fm = overatoms (\a s -> Set.union (fva a) s) fm mempty

-- | Find the variables in an atom
fva :: (HasApply atom, IsTerm term, term ~ TermOf atom, v ~ TVarOf term) => atom -> Set v
fva = overterms (\t s -> Set.union (fvt t) s) mempty

-- | Find the variables in a term
fvt :: (IsTerm term, v ~ TVarOf term) => term -> Set v
fvt tm = foldTerm singleton (\_ args -> unions (map fvt args)) tm

-- | Universal closure of a formula.
generalize :: IsFirstOrder formula => formula -> formula
generalize fm = Set.fold for_all fm (fv fm)

test07 :: Test
test07 = TestCase $ assertEqual "variant 1 (p. 133)" expected input
    where input = variant "x" (Set.fromList ["y", "z"]) :: V
          expected = "x"
test08 :: Test
test08 = TestCase $ assertEqual "variant 2 (p. 133)" expected input
    where input = variant "x" (Set.fromList ["x", "y"]) :: V
          expected = "x'"
test09 :: Test
test09 = TestCase $ assertEqual "variant 3 (p. 133)" expected input
    where input = variant "x" (Set.fromList ["x", "x'"]) :: V
          expected = "x''"

-- | Substitution in formulas, with variable renaming.
subst :: (IsFirstOrder formula, term ~ TermOf (AtomOf formula), v ~ VarOf formula) => Map v term -> formula -> formula
subst subfn fm =
    foldQuantified qu co ne tf at fm
    where
      qu (:!:) x p = substq subfn for_all x p
      qu (:?:) x p = substq subfn exists x p
      ne p = (.~.) (subst subfn p)
      co p (:&:) q = (subst subfn p) .&. (subst subfn q)
      co p (:|:) q = (subst subfn p) .|. (subst subfn q)
      co p (:=>:) q = (subst subfn p) .=>. (subst subfn q)
      co p (:<=>:) q = (subst subfn p) .<=>. (subst subfn q)
      tf False = false
      tf True = true
      at = atomic . asubst subfn

-- | Substitution within terms.
tsubst :: (IsTerm term, v ~ TVarOf term) => Map v term -> term -> term
tsubst sfn tm =
    foldTerm (\x -> fromMaybe tm (Map.lookup x sfn))
             (\f args -> fApp f (map (tsubst sfn) args))
             tm

-- | Substitution within a Literal
lsubst :: (JustLiteral lit, HasApply atom, IsTerm term,
           atom ~ AtomOf lit,
           term ~ TermOf atom,
           v ~ TVarOf term) =>
          Map v term -> lit -> lit
lsubst subfn fm =
    foldLiteral ne fromBool at fm
    where
      ne p = (.~.) (lsubst subfn p)
      at = atomic . asubst subfn

-- | Substitution within atoms.
asubst :: (HasApply atom, IsTerm term, term ~ TermOf atom, v ~ TVarOf term) => Map v term -> atom -> atom
asubst sfn a = onterms (tsubst sfn) a

-- | Substitution within quantifiers
substq :: (IsFirstOrder formula, v ~ VarOf formula, term ~ TermOf (AtomOf formula)) =>
          Map v term -> (v -> formula -> formula) -> v -> formula -> formula
substq subfn qu x p =
  let x' = if setAny (\y -> Set.member x (fvt(tryApplyD subfn y (vt y))))
                     (difference (fv p) (singleton x))
           then variant x (fv (subst (undefine x subfn) p)) else x in
  qu x' (subst ((x |-> vt x') subfn) p)

-- Examples.

test10 :: Test
test10 =
    let [x, x', y] = [vt "x", vt "x'", vt "y"]
        fm = for_all "x" ((x .=. y)) :: EqFormula
        expected = for_all "x'" (x' .=. x) :: EqFormula in
    TestCase $ assertEqual ("subst (\"y\" |=> Var \"x\") " ++ prettyShow fm ++ " (p. 134)")
                           expected
                           (subst (Map.fromList [("y", x)]) fm)

test11 :: Test
test11 =
    let [x, x', x'', y] = [vt "x", vt "x'", vt "x''", vt "y"]
        fm = (for_all "x" (for_all "x'" ((x .=. y) .=>. (x .=. x')))) :: EqFormula
        expected = for_all "x'" (for_all "x''" ((x' .=. x) .=>. ((x' .=. x'')))) :: EqFormula in
    TestCase $ assertEqual ("subst (\"y\" |=> Var \"x\") " ++ prettyShow fm ++ " (p. 134)")
                           expected
                           (subst (Map.fromList [("y", x)]) fm)

testFOL :: Test
testFOL = TestLabel "FOL" (TestList [test00, test01, test02, test03, test04,
                                     test05, test06, test07, test08, test09,
                                     test10, test11])
