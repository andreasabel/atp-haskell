{-# LANGUAGE GADTs, MultiParamTypeClasses, OverloadedStrings, ScopedTypeVariables #-}
module Extra where

import Control.Applicative.Error (Failing(Failure, Success))
import Data.List as List (map)
import Data.Map as Map (fromList)
import Data.Set as Set (fromList, map, Set)
import Test.HUnit

import FOL (vt, fApp, (.=.), pApp, for_all, exists, HasPredicate(applyPredicate), Predicate(Equals))
import Formulas
import Lib (failing)
import Meson (meson)
import Pretty (prettyShow)
import Prop hiding (nnf)
import Skolem (HasSkolem(toSkolem), skolemize, runSkolem, MyAtom, MyFormula, MyTerm)
import Tableaux (Depth(Depth))

testExtra :: Test
testExtra = TestList [test05, test06, test07, test00]

test05 :: Test
test05 = TestCase $ assertEqual "Socrates syllogism" expected input
    where input = (runSkolem (resolution1 socrates),
                   runSkolem (resolution2 socrates),
                   runSkolem (resolution3 socrates),
                   runSkolem (presolution socrates),
                   runSkolem (resolution1 notSocrates),
                   runSkolem (resolution2 notSocrates),
                   runSkolem (resolution3 notSocrates),
                   runSkolem (presolution notSocrates))
          expected = (Set.singleton (Success True),
                      Set.singleton (Success True),
                      Set.singleton (Success True),
                      Set.singleton (Success True),
                      Set.singleton (Success {-False-} True),
                      Set.singleton (Success {-False-} True),
                      Set.singleton (Failure ["No proof found"]),
                      Set.singleton (Success {-False-} True))

socrates :: MyFormula
socrates =
    (for_all x (s [vt x] .=>. h [vt x]) .&. for_all x (h [vt x] .=>. m [vt x])) .=>. for_all x (s [vt x] .=>. m [vt x])
    where
      x = fromString "x"
      s = pApp (fromString "S")
      h = pApp (fromString "H")
      m = pApp (fromString "M")

notSocrates :: MyFormula
notSocrates =
    (for_all x (s [vt x] .=>. h [vt x]) .&. for_all x (h [vt x] .=>. m [vt x])) .=>. for_all x (s [vt x] .=>.  ((.~.)(m [vt x])))
    where
      x = fromString "x"
      s = pApp (fromString "S")
      h = pApp (fromString "H")
      m = pApp (fromString "M")

test06 :: Test
test06 =
    let fm :: MyFormula
        fm = for_all "x" (vt "x" .=. vt "x") .=>. for_all "x" (exists "y" (vt "x" .=. vt "y"))
        expected :: PFormula MyAtom
        expected =  (vt "x" .=. vt "x") .&. (.~.) (fApp (toSkolem "x") [] .=. vt "x")
        -- atoms = [applyPredicate equals [(vt ("x" :: V)) (vt "x")] {-, (fApp (toSkolem "x")[]) .=. (vt "x")-}] :: [MyAtom]
        sk = runSkolem (skolemize id ((.~.) fm)) :: PFormula MyAtom
        table = truthTable sk :: TruthTable MyAtom in
    TestCase $ assertEqual "∀x. x = x ⇒ ∀x. ∃y. x = y"
                           (expected,
                            TruthTable
                              [applyPredicate Equals [vt "x", vt "x"], applyPredicate Equals [fApp (toSkolem "x")[], vt "x"]]
                              [([False,False],False),
                               ([False,True],False),
                               ([True,False],True),
                               ([True,True],False)] :: TruthTable MyAtom,
                           Set.fromList [Success ((Map.fromList [("_0",vt "_1"),
                                                                 ("_1",fApp (toSkolem "x")[])],
                                                   0,
                                                   2),
                                                  Depth 1)])
                           (sk, table, runSkolem (meson Nothing fm))

mesonTest :: MyFormula -> Set (Failing Depth) -> Test
mesonTest fm expected =
    let me = Set.map (failing Failure (Success . snd)) (runSkolem (meson (Just (Depth 1000)) fm)) in
    TestCase $ assertEqual ("MESON test: " ++ prettyShow fm) expected me

fms :: [(MyFormula, Set (Failing Depth))]
fms = [ -- if x every x equals itself then there is always some y that equals x
        let [x, y] = [vt "x", vt "y"] :: [MyTerm] in
        (for_all "x" (x .=. x) .=>. for_all "x" (exists "y" (x .=. y)),
         Set.fromList [Success (Depth 1)]),
        -- Socrates is a human, all humans are mortal, therefore socrates is mortal
        let x = vt "x" :: MyTerm
            [s, h, m] = [pApp "S", pApp "H", pApp "M"] :: [[MyTerm] -> MyFormula] in
        ((for_all "x" (s [x] .=>. h [x]) .&. for_all "x" (h [x] .=>. m [x])) .=>. for_all "x" (s [x] .=>. m [x]),
         Set.fromList [Success (Depth 3)]) ]

test07 :: Test
test07 = TestList (List.map (uncurry mesonTest) fms)

test00 :: Test
test00 =
    let [a, y, z] = List.map vt ["a", "y", "z"] :: [MyTerm]
        [p, q, r] = List.map (pApp . fromString) ["P", "Q", "R"] :: [[MyTerm] -> MyFormula]
        fm1 = for_all "a" ((.~.)(p[a] .&. (for_all "y" (for_all "z" (q[y] .|. r[z]) .&. (.~.)(p[a])))))
        fm2 = for_all "a" ((.~.)(p[a] .&. (.~.)(p[a]) .&. (for_all "y" (for_all "z" (q[y] .|. r[z]))))) in
    TestList
    [ TestCase $ assertEqual ("MESON 1")
                   ("∀a. (¬(P[a]∧∀y. (∀z. (Q[y]∨R[z])∧¬P[a])))", Success ((K 2, Map.empty),Depth 2))
                   (prettyShow fm1, tab Nothing fm1),
      TestCase $ assertEqual ("MESON 2")
                   ("∀a. (¬(P[a]∧¬P[a]∧∀y. ∀z. (Q[y]∨R[z])))", Success ((K 0, Map.empty),Depth 0))
                   (prettyShow fm2, tab Nothing fm2) ]

{-
test12 :: Test
test12 =
    let fm = (let (x, y) = (vt "x" :: Term, vt "y" :: Term) in ((for_all "x" ((x .=. x))) .=>. (for_all "x" (exists "y" ((x .=. y))))) :: Formula FOL) in
    TestCase $ assertEqual "∀x. x = x ⇒ ∀x. ∃y. x = y" (holds fm) True
-}
