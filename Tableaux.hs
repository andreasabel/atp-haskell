-- | Tableaux, seen as an optimized version of a Prawitz-like procedure.
--
-- Copyright (c) 2003-2007, John Harrison. (See "LICENSE.txt" for details.)
{-# LANGUAGE CPP, GADTs, NoMonomorphismRestriction, OverloadedStrings, RankNTypes, ScopedTypeVariables, TupleSections #-}
{-# OPTIONS_GHC -Wall #-}
module Tableaux
    ( unify_literals
    , prawitz
    , deepen
    -- , tab
    , tests
    ) where

import Data.List as List (map)
import Lib hiding (tests)
import Formulas
import Lit
import Pretty (Pretty, prettyShow)
import Prop (simpdnf)
import FOL hiding (tests)
import Skolem (askolemize, HasSkolem, runSkolem, skolemize, MyTerm, MyFormula)
import Unif (unify)
import Data.Map as Map
import Data.Set as Set
import Data.String (IsString(..))
import Debug.Trace (trace)
import Test.HUnit


-- | Unify literals (just pretend the toplevel relation is a function).
unify_literals :: forall lit atom term predicate v f.
                  (IsLiteral lit atom,
                   IsAtom atom predicate term,
                   IsTerm term v f,
                   Eq term, Eq predicate) =>
                  Map v term -> lit -> lit -> Failing (Map v term)
unify_literals env f1 f2 =
    maybe err id (zipLiterals co tf at f1 f2)
    where
      -- co :: lit -> lit -> Maybe (Failing (Map v term))
      co p q = Just $ unify_literals env p q
      tf p q = if p == q then Just $ unify env [] else Nothing
      at :: atom -> atom -> Maybe (Failing (Map v term))
      at a1 a2 = Just $ unify_atoms env a1 a2
      err = Failure ["Can't unify literals"]

unify_atoms :: forall atom term predicate v f.
               (IsAtom atom predicate term,
                IsTerm term v f, Eq term, Eq predicate) =>
               Map v term -> atom -> atom -> Failing (Map v term)
unify_atoms env a1 a2 =
    zipAtoms (\_ tpairs -> unify env tpairs) a1 a2
{-
unifyAtomsEq :: forall v f atom p term.
                (AtomEq atom p term, Term term v f) =>
                Map v term -> atom -> atom -> Failing (Map v term)
unifyAtomsEq env a1 a2 =
    maybe err id (zipAtomsEq ap tf eq a1 a2)
    where
      ap p1 ts1 p2 ts2 =
          if p1 == p2 && length ts1 == length ts2
          then Just $ unify env (zip ts1 ts2)
          else Nothing
      tf p q = if p == q then Just $ unify env [] else Nothing
      eq pl pr ql qr = Just $ unify env [(pl, ql), (pr, qr)]
      err = Failure ["Can't unify atoms"]
-}

-- | Unify complementary literals.
unify_complements :: forall lit atom term predicate v f.
                     (IsLiteral lit atom,
                      IsAtom atom predicate term,
                      IsTerm term v f,
                      Eq term, Eq predicate) =>
                     Map v term -> lit -> lit -> Failing (Map v term)
unify_complements env p q = unify_literals env p ((.~.) q)

-- | Unify and refute a set of disjuncts.
unify_refute :: (IsLiteral lit atom,
                 IsAtom atom predicate term,
                 IsTerm term v f,
                 Ord lit, Eq term, Eq predicate) =>
                Set.Set (Set.Set lit) -> Map v term -> Failing (Map v term)
unify_refute djs env =
    case Set.minView djs of
      Nothing -> Success env
      Just (d, odjs) ->
          settryfind (\ (p, n) -> unify_complements env p n >>= unify_refute odjs) pairs
          where
            pairs = allpairs (,) pos neg
            (pos,neg) = Set.partition positive d

-- | Hence a Prawitz-like procedure (using unification on DNF).
prawitz_loop :: forall atom v term predicate f lit.
                (IsLiteral lit atom,
                 IsAtom atom predicate term,
                 IsTerm term v f,
                 Ord lit, Eq term, Eq predicate) =>
                Set (Set lit) -> [v] -> Set (Set lit) -> Int -> (Map v term, Int)
prawitz_loop djs0 fvs djs n =
    let l = length fvs in
    let newvars = List.map (\ k -> fromString ("_" ++ show (n * l + k))) [1..l] in
    let inst = Map.fromList (zip fvs (List.map vt newvars)) in
    let djs1 = distrib' (Set.map (Set.map (onatoms (atomic . asubst inst))) djs0) djs in
    case unify_refute djs1 Map.empty of
      Failure _ -> prawitz_loop djs0 fvs djs1 (n + 1)
      Success env -> (env, n + 1)

prawitz :: forall formula atom term predicate function v.
           (IsFirstOrder formula atom v,
            IsAtom atom predicate term,
            IsTerm term v function,
            HasSkolem function v,
            Ord formula, Eq term, Eq predicate) =>
           formula -> Int
prawitz fm =
    snd (prawitz_loop dnf (Set.toList fvs) dnf0 0)
    where
      dnf0 = Set.singleton Set.empty
      dnf = simpdnf id pf :: Set (Set formula)
      fvs = overatoms (\ a s -> Set.union (fv (atomic a :: formula)) s) pf (Set.empty :: Set v)
      pf = runSkolem (skolemize id ((.~.)(generalize fm))) :: formula

-- ------------------------------------------------------------------------- 
-- Examples.                                                                 
-- ------------------------------------------------------------------------- 

{-
test01 = TestCase $ assertEqual "p20 - prawitz" expected input
    where input = prawitz fm
          fm = (for_all "x" (for_all "y" (exists "z" (for_all "w" (pApp "P" [vt "x"] .&. pApp "Q" [vt "y"] .=>.
                                                                   pApp "R" [vt "z"] .&. pApp "U" [vt "w"]))))) .=>.
               (exists "x" (exists "y" (pApp "P" [vt "x"] .&. pApp "Q" [vt "y"]))) .=>. (exists "z" (pApp "R" [vt "z"]))
          expected = 1
-}

-- ------------------------------------------------------------------------- 
-- Comparison of number of ground instances.                                 
-- ------------------------------------------------------------------------- 

{-
compare :: forall fof pf lit atom term v f.
           (FirstOrderFormula fof atom v,
            PropositionalFormula pf atom,
            Literal pf atom,
            Term term v f,
            IsAtom atom predicate term,
            IsString f) =>
           (atom -> Set.Set (f, Int)) -> fof -> (Int, Failing Int)
-}
-- compare fa fm = (prawitz fm, davisputnam fa fm)
{-
START_INTERACTIVE;;
test02 = TestCase $ assertEqual "p19" expected input
    where input = compare (exists "x" (forall "y" (for_all "z" ((pApp "P" [vt "y"] .=>. pApp "Q" [vt "z"]) .=>. pApp "P" [vt "x"] .=>. pApp "Q" [vt "x"]))))

let p20 = compare
 <<(forall x y. exists z. forall w. P[vt "x"] .&. Q[vt "y"] .=>. R[vt "z"] .&. U[vt "w"])
   .=>. (exists x y. P[vt "x"] .&. Q[vt "y"]) .=>. (exists z. R[vt "z"])>>;;

let p24 = compare
 <<~(exists x. U[vt "x"] .&. Q[vt "x"]) .&.
   (forall x. P[vt "x"] .=>. Q[vt "x"] .|. R[vt "x"]) .&.
   ~(exists x. P[vt "x"] .=>. (exists x. Q[vt "x"])) .&.
   (forall x. Q[vt "x"] .&. R[vt "x"] .=>. U[vt "x"])
   .=>. (exists x. P[vt "x"] .&. R[vt "x"])>>;;

let p39 = compare
 <<~(exists x. forall y. P(y,x) .<=>. ~P(y,y))>>;;

let p42 = compare
 <<~(exists y. forall x. P(x,y) .<=>. ~(exists z. P(x,z) .&. P(z,x)))>>;;

{- **** Too slow?

let p43 = compare
 <<(forall x y. Q(x,y) .<=>. forall z. P(z,x) .<=>. P(z,y))
   .=>. forall x y. Q(x,y) .<=>. Q(y,x)>>;;

 ***** -}

let p44 = compare
 <<(forall x. P[vt "x"] .=>. (exists y. G[vt "y"] .&. H(x,y)) .&.
   (exists y. G[vt "y"] .&. ~H(x,y))) .&.
   (exists x. J[vt "x"] .&. (forall y. G[vt "y"] .=>. H(x,y)))
   .=>. (exists x. J[vt "x"] .&. ~P[vt "x"])>>;;

let p59 = compare
 <<(forall x. P[vt "x"] .<=>. ~P(f[vt "x"])) .=>. (exists x. P[vt "x"] .&. ~P(f[vt "x"]))>>;;

let p60 = compare
 <<forall x. P(x,f[vt "x"]) .<=>.
             exists y. (forall z. P(z,y) .=>. P(z,f[vt "x"])) .&. P(x,y)>>;;

END_INTERACTIVE;;
-}
-- | More standard tableau procedure, effectively doing DNF incrementally.
{-
let rec tableau (fms,lits,n) cont (env,k) =
  if n < 0 then failwith "no proof at this level" else
  match fms with
    [] -> failwith "tableau: no proof"
  | And(p,q)::unexp ->
      tableau (p::q::unexp,lits,n) cont (env,k)
  | Or(p,q)::unexp ->
      tableau (p::unexp,lits,n) (tableau (q::unexp,lits,n) cont) (env,k)
  | Forall(x,p)::unexp ->
      let y = Var("_" ^ string_of_int k) in
      let p' = subst (x |=> y) p in
      tableau (p'::unexp@[Forall(x,p)],lits,n-1) cont (env,k+1)
  | fm::unexp ->
      try tryfind (fun l -> cont(unify_complements env (fm,l),k)) lits
      with Failure _ -> tableau (unexp,fm::lits,n) cont (env,k);;
-}
tableau :: forall formula atom predicate function v term r.
           (IsFirstOrder formula atom v,
            IsAtom atom predicate term,
            IsTerm term v function,
            Eq term, Eq predicate) =>
           ([formula], [formula], Int)
        -> ((Map v term, Int) -> Failing r)
        -> (Map v term, Int)
        -> Failing r
tableau (fms, lits, n) cont (env, k) =
    case fms of
      _ | n < 0 -> Failure ["no proof at this level"]
      [] -> Failure ["tableau: no proof"]
      (fm : unexp) ->
          foldFirstOrder qu co (\_ -> go fm unexp) (\_ -> go fm unexp) fm
          where
            qu :: Quant -> v -> formula -> Failing r
            qu (:!:) x p =
                -- let y = Var("_" ^ string_of_int k) in
                -- let p' = subst (x |=> y) p in
                -- tableau (p'::unexp@[Forall(x,p)],lits,n-1) cont (env,k+1)
                let y = vt (fromString ("_" ++ show k))
                    p' = subst (x |=> y) p in
                tableau ([p'] ++ unexp ++ [for_all x p],lits,n-1) cont (env,k+1)
            qu _ _ _ = go fm unexp
            co (BinOp p (:&:) q) =
                -- tableau (p::q::unexp,lits,n) cont (env,k)
                tableau (p : q : unexp,lits,n) cont (env,k)
            co (BinOp p (:|:) q) =
                -- tableau (p::unexp,lits,n) (tableau (q::unexp,lits,n) cont) (env,k)
                tableau (p : unexp,lits,n) (tableau (q : unexp,lits,n) cont) (env,k)
            co _ = go fm unexp
    where
      go fm unexp =
          -- try tryfind (fun l -> cont(unify_complements env (fm,l),k)) lits
          -- with Failure _ -> tableau (unexp,fm::lits,n) cont (env,k);;
          case tryfind (\l -> unify_complements env fm l >>= \x -> cont (x, k)) lits of
            Success r -> Success r
            Failure _ -> tableau (unexp, fm : lits, n) cont (env,k)

-- | Try f with higher and higher values of n until it succeeds, or
-- optional maximum depth limit is exceeded.
{-
let rec deepen f n =
  try print_string "Searching with depth limit ";
      print_int n; print_newline(); f n
  with Failure _ -> deepen f (n + 1);;
-}
#if 1
deepen :: (Int -> Failing r) -> Int -> Failing r
deepen f n =
    case trace ("Searching with depth limit " ++ show n) (f n) of
      Success r -> Success r
      Failure _ -> deepen f (n + 1)
#else
deepen :: (Int -> Failing t) -> Int -> Maybe Int -> Failing (t, Int)
deepen _ n (Just m) | n > m = Failure ["Exceeded maximum depth limit"]
deepen f n m =
    -- If no maximum depth limit is given print a trace of the
    -- levels tried.  The assumption is that we are running
    -- interactively.
    let n' = maybe (trace ("Searching with depth limit " ++ show n) n) (const n) m in
    case f n' of
      Failure _ -> deepen f (n + 1) m
      Success x -> Success (x, n)
#endif

tabrefute :: (IsFirstOrder formula atom v,
              IsAtom atom predicate term,
              Eq predicate, Eq term, IsTerm term v function) =>
             [formula] -> Failing ((Map v term, Int), Int)
tabrefute fms =
  -- deepen (fun n -> tableau (fms,[],n) (fun x -> x) (undefined,0); n) 0;;
  deepen (\n -> failing Failure (\r -> Success (r, n)) (tableau (fms,[],n) (\x -> Success x) (Map.empty,0))) 0

tab :: (IsFirstOrder formula atom v,
        IsAtom atom predicate term,
        IsTerm term v function,
        HasSkolem function v,
        Eq formula, Eq term, Eq predicate,
        Pretty formula) =>
       formula -> Failing ((Map v term, Int), Int)
tab fm =
  let sfm = runSkolem (askolemize((.~.)(generalize fm))) in
  if sfm == false then undefined else tabrefute (trace ("tabrefute " ++ prettyShow sfm) [sfm])

test01 :: Test
test01 =
    let [p, r] = [pApp "P", pApp "R"] :: [[MyTerm] -> MyFormula]
        [a, w, x, y, z] = [vt "a", vt "w", vt "x", vt "y", vt "z"] :: [MyTerm]
        fm = (for_all "x"
               (p[a] .&. (p[x] .=>. (exists "y" (p[y] .&. r[x,y]))) .=>.
                (exists "z" (exists "w" (p[z] .&. r[x,w] .&. r[w,z]))))) .<=>.
             (for_all "x"
              (((.~.)(p[a]) .|. p[x] .|. (exists "z" (exists "w" (p[z] .&. r[x,w] .&. r[w,z])))) .&.
               ((.~.)(p[a]) .|. (.~.)(exists "y" (p[y] .&. r[x,y])) .|.
               (exists "z" (exists "w" (p[z] .&. r[x,w] .&. r[w,z])))))) in
    TestCase $ assertEqual "p38" (failing show show (tab fm)) ""
{-
-- ------------------------------------------------------------------------- 
-- Example.                                                                  
-- ------------------------------------------------------------------------- 

START_INTERACTIVE;;
let p38 = tab
 <<(forall x.
     P[vt "a"] .&. (P[vt "x"] .=>. (exists y. P[vt "y"] .&. R(x,y))) .=>.
     (exists z w. P[vt "z"] .&. R(x,w) .&. R(w,z))) .<=>.
   (forall x.
     (~P[vt "a"] .|. P[vt "x"] .|. (exists z w. P[vt "z"] .&. R(x,w) .&. R(w,z))) .&.
     (~P[vt "a"] .|. ~(exists y. P[vt "y"] .&. R(x,y)) .|.
     (exists z w. P[vt "z"] .&. R(x,w) .&. R(w,z))))>>;;
END_INTERACTIVE;;

-- ------------------------------------------------------------------------- 
-- Try to split up the initial formula first; often a big improvement.       
-- ------------------------------------------------------------------------- 
-}
splittab fm =
  List.map tabrefute (simpdnf id (runSkolem (askolemize((.~.)(generalize fm)))))
{-
-- ------------------------------------------------------------------------- 
-- Example: the Andrews challenge.                                           
-- ------------------------------------------------------------------------- 

START_INTERACTIVE;;
let p34 = splittab
 <<((exists x. forall y. P[vt "x"] .<=>. P[vt "y"]) .<=>.
    ((exists x. Q[vt "x"]) .<=>. (forall y. Q[vt "y"]))) .<=>.
   ((exists x. forall y. Q[vt "x"] .<=>. Q[vt "y"]) .<=>.
    ((exists x. P[vt "x"]) .<=>. (forall y. P[vt "y"])))>>;;

-- ------------------------------------------------------------------------- 
-- Another nice example from EWD 1602.                                       
-- ------------------------------------------------------------------------- 

let ewd1062 = splittab
 <<(forall x. x <= x) .&.
   (forall x y z. x <= y .&. y <= z .=>. x <= z) .&.
   (forall x y. f[vt "x"] <= y .<=>. x <= g[vt "y"])
   .=>. (forall x y. x <= y .=>. f[vt "x"] <= f[vt "y"]) .&.
       (forall x y. x <= y .=>. g[vt "x"] <= g[vt "y"])>>;;
END_INTERACTIVE;;

-- ------------------------------------------------------------------------- 
-- Do all the equality-free Pelletier problems, and more, as examples.       
-- ------------------------------------------------------------------------- 

{- **********

let p1 = time splittab
 <<p .=>. q .<=>. ~q .=>. ~p>>;;

let p2 = time splittab
 <<~ ~p .<=>. p>>;;

let p3 = time splittab
 <<~(p .=>. q) .=>. q .=>. p>>;;

let p4 = time splittab
 <<~p .=>. q .<=>. ~q .=>. p>>;;

let p5 = time splittab
 <<(p .|. q .=>. p .|. r) .=>. p .|. (q .=>. r)>>;;

let p6 = time splittab
 <<p .|. ~p>>;;

let p7 = time splittab
 <<p .|. ~ ~ ~p>>;;

let p8 = time splittab
 <<((p .=>. q) .=>. p) .=>. p>>;;

let p9 = time splittab
 <<(p .|. q) .&. (~p .|. q) .&. (p .|. ~q) .=>. ~(~q .|. ~q)>>;;

let p10 = time splittab
 <<(q .=>. r) .&. (r .=>. p .&. q) .&. (p .=>. q .&. r) .=>. (p .<=>. q)>>;;

let p11 = time splittab
 <<p .<=>. p>>;;

let p12 = time splittab
 <<((p .<=>. q) .<=>. r) .<=>. (p .<=>. (q .<=>. r))>>;;

let p13 = time splittab
 <<p .|. q .&. r .<=>. (p .|. q) .&. (p .|. r)>>;;

let p14 = time splittab
 <<(p .<=>. q) .<=>. (q .|. ~p) .&. (~q .|. p)>>;;

let p15 = time splittab
 <<p .=>. q .<=>. ~p .|. q>>;;

let p16 = time splittab
 <<(p .=>. q) .|. (q .=>. p)>>;;

let p17 = time splittab
 <<p .&. (q .=>. r) .=>. s .<=>. (~p .|. q .|. s) .&. (~p .|. ~r .|. s)>>;;

-- ------------------------------------------------------------------------- 
-- Pelletier problems: monadic predicate logic.                              
-- ------------------------------------------------------------------------- 

let p18 = time splittab
 <<exists y. forall x. P[vt "y"] .=>. P[vt "x"]>>;;

let p19 = time splittab
 <<exists x. forall y z. (P[vt "y"] .=>. Q[vt "z"]) .=>. P[vt "x"] .=>. Q[vt "x"]>>;;

let p20 = time splittab
 <<(forall x y. exists z. forall w. P[vt "x"] .&. Q[vt "y"] .=>. R[vt "z"] .&. U[vt "w"])
   .=>. (exists x y. P[vt "x"] .&. Q[vt "y"]) .=>. (exists z. R[vt "z"])>>;;

let p21 = time splittab
 <<(exists x. P .=>. Q[vt "x"]) .&. (exists x. Q[vt "x"] .=>. P)
   .=>. (exists x. P .<=>. Q[vt "x"])>>;;

let p22 = time splittab
 <<(forall x. P .<=>. Q[vt "x"]) .=>. (P .<=>. (forall x. Q[vt "x"]))>>;;

let p23 = time splittab
 <<(forall x. P .|. Q[vt "x"]) .<=>. P .|. (forall x. Q[vt "x"])>>;;

let p24 = time splittab
 <<~(exists x. U[vt "x"] .&. Q[vt "x"]) .&.
   (forall x. P[vt "x"] .=>. Q[vt "x"] .|. R[vt "x"]) .&.
   ~(exists x. P[vt "x"] .=>. (exists x. Q[vt "x"])) .&.
   (forall x. Q[vt "x"] .&. R[vt "x"] .=>. U[vt "x"]) .=>.
   (exists x. P[vt "x"] .&. R[vt "x"])>>;;

let p25 = time splittab
 <<(exists x. P[vt "x"]) .&.
   (forall x. U[vt "x"] .=>. ~G[vt "x"] .&. R[vt "x"]) .&.
   (forall x. P[vt "x"] .=>. G[vt "x"] .&. U[vt "x"]) .&.
   ((forall x. P[vt "x"] .=>. Q[vt "x"]) .|. (exists x. Q[vt "x"] .&. P[vt "x"]))
   .=>. (exists x. Q[vt "x"] .&. P[vt "x"])>>;;

let p26 = time splittab
 <<((exists x. P[vt "x"]) .<=>. (exists x. Q[vt "x"])) .&.
   (forall x y. P[vt "x"] .&. Q[vt "y"] .=>. (R[vt "x"] .<=>. U[vt "y"]))
   .=>. ((forall x. P[vt "x"] .=>. R[vt "x"]) .<=>. (forall x. Q[vt "x"] .=>. U[vt "x"]))>>;;

let p27 = time splittab
 <<(exists x. P[vt "x"] .&. ~Q[vt "x"]) .&.
   (forall x. P[vt "x"] .=>. R[vt "x"]) .&.
   (forall x. U[vt "x"] .&. V[vt "x"] .=>. P[vt "x"]) .&.
   (exists x. R[vt "x"] .&. ~Q[vt "x"])
   .=>. (forall x. U[vt "x"] .=>. ~R[vt "x"])
       .=>. (forall x. U[vt "x"] .=>. ~V[vt "x"])>>;;

let p28 = time splittab
 <<(forall x. P[vt "x"] .=>. (forall x. Q[vt "x"])) .&.
   ((forall x. Q[vt "x"] .|. R[vt "x"]) .=>. (exists x. Q[vt "x"] .&. R[vt "x"])) .&.
   ((exists x. R[vt "x"]) .=>. (forall x. L[vt "x"] .=>. M[vt "x"])) .=>.
   (forall x. P[vt "x"] .&. L[vt "x"] .=>. M[vt "x"])>>;;

let p29 = time splittab
 <<(exists x. P[vt "x"]) .&. (exists x. G[vt "x"]) .=>.
   ((forall x. P[vt "x"] .=>. H[vt "x"]) .&. (forall x. G[vt "x"] .=>. J[vt "x"]) .<=>.
    (forall x y. P[vt "x"] .&. G[vt "y"] .=>. H[vt "x"] .&. J[vt "y"]))>>;;

let p30 = time splittab
 <<(forall x. P[vt "x"] .|. G[vt "x"] .=>. ~H[vt "x"]) .&.
   (forall x. (G[vt "x"] .=>. ~U[vt "x"]) .=>. P[vt "x"] .&. H[vt "x"])
   .=>. (forall x. U[vt "x"])>>;;

let p31 = time splittab
 <<~(exists x. P[vt "x"] .&. (G[vt "x"] .|. H[vt "x"])) .&.
   (exists x. Q[vt "x"] .&. P[vt "x"]) .&.
   (forall x. ~H[vt "x"] .=>. J[vt "x"])
   .=>. (exists x. Q[vt "x"] .&. J[vt "x"])>>;;

let p32 = time splittab
 <<(forall x. P[vt "x"] .&. (G[vt "x"] .|. H[vt "x"]) .=>. Q[vt "x"]) .&.
   (forall x. Q[vt "x"] .&. H[vt "x"] .=>. J[vt "x"]) .&.
   (forall x. R[vt "x"] .=>. H[vt "x"])
   .=>. (forall x. P[vt "x"] .&. R[vt "x"] .=>. J[vt "x"])>>;;

let p33 = time splittab
 <<(forall x. P[vt "a"] .&. (P[vt "x"] .=>. P[vt "b"]) .=>. P[vt "c"]) .<=>.
   (forall x. P[vt "a"] .=>. P[vt "x"] .|. P[vt "c"]) .&. (P[vt "a"] .=>. P[vt "b"] .=>. P[vt "c"])>>;;

let p34 = time splittab
 <<((exists x. forall y. P[vt "x"] .<=>. P[vt "y"]) .<=>.
    ((exists x. Q[vt "x"]) .<=>. (forall y. Q[vt "y"]))) .<=>.
   ((exists x. forall y. Q[vt "x"] .<=>. Q[vt "y"]) .<=>.
    ((exists x. P[vt "x"]) .<=>. (forall y. P[vt "y"])))>>;;

let p35 = time splittab
 <<exists x y. P(x,y) .=>. (forall x y. P(x,y))>>;;

-- ------------------------------------------------------------------------- 
-- Full predicate logic (without identity and functions).                    
-- ------------------------------------------------------------------------- 

let p36 = time splittab
 <<(forall x. exists y. P(x,y)) .&.
   (forall x. exists y. G(x,y)) .&.
   (forall x y. P(x,y) .|. G(x,y)
   .=>. (forall z. P(y,z) .|. G(y,z) .=>. H(x,z)))
       .=>. (forall x. exists y. H(x,y))>>;;

let p37 = time splittab
 <<(forall z.
     exists w. forall x. exists y. (P(x,z) .=>. P(y,w)) .&. P(y,z) .&.
     (P(y,w) .=>. (exists u. Q(u,w)))) .&.
   (forall x z. ~P(x,z) .=>. (exists y. Q(y,z))) .&.
   ((exists x y. Q(x,y)) .=>. (forall x. R(x,x))) .=>.
   (forall x. exists y. R(x,y))>>;;

let p38 = time splittab
 <<(forall x.
     P[vt "a"] .&. (P[vt "x"] .=>. (exists y. P[vt "y"] .&. R(x,y))) .=>.
     (exists z w. P[vt "z"] .&. R(x,w) .&. R(w,z))) .<=>.
   (forall x.
     (~P[vt "a"] .|. P[vt "x"] .|. (exists z w. P[vt "z"] .&. R(x,w) .&. R(w,z))) .&.
     (~P[vt "a"] .|. ~(exists y. P[vt "y"] .&. R(x,y)) .|.
     (exists z w. P[vt "z"] .&. R(x,w) .&. R(w,z))))>>;;

let p39 = time splittab
 <<~(exists x. forall y. P(y,x) .<=>. ~P(y,y))>>;;

let p40 = time splittab
 <<(exists y. forall x. P(x,y) .<=>. P(x,x))
  .=>. ~(forall x. exists y. forall z. P(z,y) .<=>. ~P(z,x))>>;;

let p41 = time splittab
 <<(forall z. exists y. forall x. P(x,y) .<=>. P(x,z) .&. ~P(x,x))
  .=>. ~(exists z. forall x. P(x,z))>>;;

let p42 = time splittab
 <<~(exists y. forall x. P(x,y) .<=>. ~(exists z. P(x,z) .&. P(z,x)))>>;;

let p43 = time splittab
 <<(forall x y. Q(x,y) .<=>. forall z. P(z,x) .<=>. P(z,y))
   .=>. forall x y. Q(x,y) .<=>. Q(y,x)>>;;

let p44 = time splittab
 <<(forall x. P[vt "x"] .=>. (exists y. G[vt "y"] .&. H(x,y)) .&.
   (exists y. G[vt "y"] .&. ~H(x,y))) .&.
   (exists x. J[vt "x"] .&. (forall y. G[vt "y"] .=>. H(x,y))) .=>.
   (exists x. J[vt "x"] .&. ~P[vt "x"])>>;;

let p45 = time splittab
 <<(forall x.
     P[vt "x"] .&. (forall y. G[vt "y"] .&. H(x,y) .=>. J(x,y)) .=>.
       (forall y. G[vt "y"] .&. H(x,y) .=>. R[vt "y"])) .&.
   ~(exists y. L[vt "y"] .&. R[vt "y"]) .&.
   (exists x. P[vt "x"] .&. (forall y. H(x,y) .=>.
     L[vt "y"]) .&. (forall y. G[vt "y"] .&. H(x,y) .=>. J(x,y))) .=>.
   (exists x. P[vt "x"] .&. ~(exists y. G[vt "y"] .&. H(x,y)))>>;;

let p46 = time splittab
 <<(forall x. P[vt "x"] .&. (forall y. P[vt "y"] .&. H(y,x) .=>. G[vt "y"]) .=>. G[vt "x"]) .&.
   ((exists x. P[vt "x"] .&. ~G[vt "x"]) .=>.
    (exists x. P[vt "x"] .&. ~G[vt "x"] .&.
               (forall y. P[vt "y"] .&. ~G[vt "y"] .=>. J(x,y)))) .&.
   (forall x y. P[vt "x"] .&. P[vt "y"] .&. H(x,y) .=>. ~J(y,x)) .=>.
   (forall x. P[vt "x"] .=>. G[vt "x"])>>;;

-- ------------------------------------------------------------------------- 
-- Well-known "Agatha" example; cf. Manthey and Bry, CADE-9.                 
-- ------------------------------------------------------------------------- 

let p55 = time splittab
 <<lives(agatha) .&. lives(butler) .&. lives(charles) .&.
   (killed(agatha,agatha) .|. killed(butler,agatha) .|.
    killed(charles,agatha)) .&.
   (forall x y. killed(x,y) .=>. hates(x,y) .&. ~richer(x,y)) .&.
   (forall x. hates(agatha,x) .=>. ~hates(charles,x)) .&.
   (hates(agatha,agatha) .&. hates(agatha,charles)) .&.
   (forall x. lives[vt "x"] .&. ~richer(x,agatha) .=>. hates(butler,x)) .&.
   (forall x. hates(agatha,x) .=>. hates(butler,x)) .&.
   (forall x. ~hates(x,agatha) .|. ~hates(x,butler) .|. ~hates(x,charles))
   .=>. killed(agatha,agatha) .&.
       ~killed(butler,agatha) .&.
       ~killed(charles,agatha)>>;;

let p57 = time splittab
 <<P(f([vt "a"],b),f(b,c)) .&.
   P(f(b,c),f(a,c)) .&.
   (forall [vt "x"] y z. P(x,y) .&. P(y,z) .=>. P(x,z))
   .=>. P(f(a,b),f(a,c))>>;;

-- ------------------------------------------------------------------------- 
-- See info-hol, circa 1500.                                                 
-- ------------------------------------------------------------------------- 

let p58 = time splittab
 <<forall P Q R. forall x. exists v. exists w. forall y. forall z.
    ((P[vt "x"] .&. Q[vt "y"]) .=>. ((P[vt "v"] .|. R[vt "w"])  .&. (R[vt "z"] .=>. Q[vt "v"])))>>;;

let p59 = time splittab
 <<(forall x. P[vt "x"] .<=>. ~P(f[vt "x"])) .=>. (exists x. P[vt "x"] .&. ~P(f[vt "x"]))>>;;

let p60 = time splittab
 <<forall x. P(x,f[vt "x"]) .<=>.
            exists y. (forall z. P(z,y) .=>. P(z,f[vt "x"])) .&. P(x,y)>>;;

-- ------------------------------------------------------------------------- 
-- From Gilmore's classic paper.                                             
-- ------------------------------------------------------------------------- 

{- **** This is still too hard for us! Amazing...

let gilmore_1 = time splittab
 <<exists x. forall y z.
      ((F[vt "y"] .=>. G[vt "y"]) .<=>. F[vt "x"]) .&.
      ((F[vt "y"] .=>. H[vt "y"]) .<=>. G[vt "x"]) .&.
      (((F[vt "y"] .=>. G[vt "y"]) .=>. H[vt "y"]) .<=>. H[vt "x"])
      .=>. F[vt "z"] .&. G[vt "z"] .&. H[vt "z"]>>;;

 ***** -}

{- ** This is not valid, according to Gilmore

let gilmore_2 = time splittab
 <<exists x y. forall z.
        (F(x,z) .<=>. F(z,y)) .&. (F(z,y) .<=>. F(z,z)) .&. (F(x,y) .<=>. F(y,x))
        .=>. (F(x,y) .<=>. F(x,z))>>;;

 ** -}

let gilmore_3 = time splittab
 <<exists x. forall y z.
        ((F(y,z) .=>. (G[vt "y"] .=>. H[vt "x"])) .=>. F(x,x)) .&.
        ((F(z,x) .=>. G[vt "x"]) .=>. H[vt "z"]) .&.
        F(x,y)
        .=>. F(z,z)>>;;

let gilmore_4 = time splittab
 <<exists x y. forall z.
        (F(x,y) .=>. F(y,z) .&. F(z,z)) .&.
        (F(x,y) .&. G(x,y) .=>. G(x,z) .&. G(z,z))>>;;

let gilmore_5 = time splittab
 <<(forall x. exists y. F(x,y) .|. F(y,x)) .&.
   (forall x y. F(y,x) .=>. F(y,y))
   .=>. exists z. F(z,z)>>;;

let gilmore_6 = time splittab
 <<forall x. exists y.
        (exists u. forall v. F(u,x) .=>. G(v,u) .&. G(u,x))
        .=>. (exists u. forall v. F(u,y) .=>. G(v,u) .&. G(u,y)) .|.
            (forall u v. exists w. G(v,u) .|. H(w,y,u) .=>. G(u,w))>>;;

let gilmore_7 = time splittab
 <<(forall x. K[vt "x"] .=>. exists y. L[vt "y"] .&. (F(x,y) .=>. G(x,y))) .&.
   (exists z. K[vt "z"] .&. forall u. L[vt "u"] .=>. F(z,u))
   .=>. exists v w. K[vt "v"] .&. L[vt "w"] .&. G(v,w)>>;;

let gilmore_8 = time splittab
 <<exists x. forall y z.
        ((F(y,z) .=>. (G[vt "y"] .=>. (forall u. exists v. H(u,v,x)))) .=>. F(x,x)) .&.
        ((F(z,x) .=>. G[vt "x"]) .=>. (forall u. exists v. H(u,v,z))) .&.
        F(x,y)
        .=>. F(z,z)>>;;

let gilmore_9 = time splittab
 <<forall x. exists y. forall z.
        ((forall u. exists v. F(y,u,v) .&. G(y,u) .&. ~H(y,x))
          .=>. (forall u. exists v. F(x,u,v) .&. G(z,u) .&. ~H(x,z))
          .=>. (forall u. exists v. F(x,u,v) .&. G(y,u) .&. ~H(x,y))) .&.
        ((forall u. exists v. F(x,u,v) .&. G(y,u) .&. ~H(x,y))
         .=>. ~(forall u. exists v. F(x,u,v) .&. G(z,u) .&. ~H(x,z))
         .=>. (forall u. exists v. F(y,u,v) .&. G(y,u) .&. ~H(y,x)) .&.
             (forall u. exists v. F(z,u,v) .&. G(y,u) .&. ~H(z,y)))>>;;

-- ------------------------------------------------------------------------- 
-- Example from Davis-Putnam papers where Gilmore procedure is poor.         
-- ------------------------------------------------------------------------- 

let davis_putnam_example = time splittab
 <<exists x. exists y. forall z.
        (F(x,y) .=>. (F(y,z) .&. F(z,z))) .&.
        ((F(x,y) .&. G(x,y)) .=>. (G(x,z) .&. G(z,z)))>>;;

************ -}

-}

tests :: Test
tests = TestList [test01]
