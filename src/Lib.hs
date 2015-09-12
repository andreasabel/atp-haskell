{-# LANGUAGE DeriveDataTypeable, RankNTypes, ScopedTypeVariables, StandaloneDeriving #-}
{-# OPTIONS_GHC -Wall -fno-warn-unused-binds #-}
module Lib
    ( Failing(Success, Failure)
    , failing

    , setAny
    , setAll
    -- , itlist2
    -- , itlist  -- same as foldr with last arguments flipped
    , tryfind
    , settryfind
    -- , end_itlist -- same as foldr1
    , (|=>)
    , (|->)
    , fpf
    , defined
    , undefine
    , apply
    -- , exists
    , tryApplyD
    , allpairs
    , distrib'
    , image
    , optimize
    , minimize
    , maximize
    , optimize'
    , minimize'
    , maximize'
    , can
    , allsets
    , allsubsets
    , allnonemptysubsets
    , mapfilter
    , setmapfilter
    , (∅)
    , tests
    ) where

import Control.Applicative.Error
import Data.Generics
import Data.List as List (foldr, map)
import Data.Map as Map (delete, findMin, fromList, insert, lookup, Map, member)
import Data.Maybe
import Data.Set as Set
import Test.HUnit (Test(TestCase, TestList, TestLabel), assertEqual)

failing :: ([String] -> b) -> (a -> b) -> Failing a -> b
failing f _ (Failure errs) = f errs
failing _ f (Success a)    = f a

instance Monad Failing where
  return = Success
  m >>= f =
      case m of
        (Failure errs) -> (Failure errs)
        (Success a) -> f a
  fail errMsg = Failure [errMsg]

deriving instance Typeable Failing
deriving instance Data a => Data (Failing a)
deriving instance Read a => Read (Failing a)
deriving instance Eq a => Eq (Failing a)
deriving instance Ord a => Ord (Failing a)

(∅) :: Set a
(∅) = Set.empty

setAny :: forall a. Ord a => (a -> Bool) -> Set a -> Bool
setAny f s = Set.member True (Set.map f s)

setAll :: forall a. Ord a => (a -> Bool) -> Set a -> Bool
setAll f s = not (Set.member False (Set.map f s))

{-
(* ========================================================================= *)
(* Misc library functions to set up a nice environment.                      *)
(* ========================================================================= *)

let identity x = x;;

let ( ** ) = fun f g x -> f(g x);;

(* ------------------------------------------------------------------------- *)
(* GCD and LCM on arbitrary-precision numbers.                               *)
(* ------------------------------------------------------------------------- *)

let gcd_num n1 n2 =
  abs_num(num_of_big_int
      (Big_int.gcd_big_int (big_int_of_num n1) (big_int_of_num n2)));;

let lcm_num n1 n2 = abs_num(n1 */ n2) // gcd_num n1 n2;;

(* ------------------------------------------------------------------------- *)
(* A useful idiom for "non contradictory" etc.                               *)
(* ------------------------------------------------------------------------- *)

let non p x = not(p x);;

(* ------------------------------------------------------------------------- *)
(* Kind of assertion checking.                                               *)
(* ------------------------------------------------------------------------- *)

let check p x = if p(x) then x else failwith "check";;

(* ------------------------------------------------------------------------- *)
(* Repetition of a function.                                                 *)
(* ------------------------------------------------------------------------- *)

let rec funpow n f x =
  if n < 1 then x else funpow (n-1) f (f x);;
-}
-- let can f x = try f x; true with Failure _ -> false;;
can :: (t -> Failing a) -> t -> Bool
can f x = failing (const True) (const False) (f x)

{-
let rec repeat f x = try repeat f (f x) with Failure _ -> x;;

(* ------------------------------------------------------------------------- *)
(* Handy list operations.                                                    *)
(* ------------------------------------------------------------------------- *)

let rec (--) = fun m n -> if m > n then [] else m::((m + 1) -- n);;

let rec (---) = fun m n -> if m >/ n then [] else m::((m +/ Int 1) --- n);;

let rec map2 f l1 l2 =
  match (l1,l2) with
    [],[] -> []
  | (h1::t1),(h2::t2) -> let h = f h1 h2 in h::(map2 f t1 t2)
  | _ -> failwith "map2: length mismatch";;

let rev =
  let rec rev_append acc l =
    match l with
      [] -> acc
    | h::t -> rev_append (h::acc) t in
  fun l -> rev_append [] l;;

let hd l =
  match l with
   h::t -> h
  | _ -> failwith "hd";;

let tl l =
  match l with
   h::t -> t
  | _ -> failwith "tl";;
-}

-- (^) = (++)

itlist :: (a -> b -> b) -> [a] -> b -> b
-- itlist f xs z = foldr f z xs
itlist f xs z = List.foldr f z xs

end_itlist :: (t -> t -> t) -> [t] -> t
-- end_itlist = foldr1
end_itlist = foldr1

itlist2 :: (t -> t1 -> Failing t2 -> Failing t2) -> [t] -> [t1] -> Failing t2 -> Failing t2
itlist2 f l1 l2 b =
  case (l1,l2) of
    ([],[]) -> b
    (h1 : t1, h2 : t2) -> f h1 h2 (itlist2 f t1 t2 b)
    _ -> Failure ["itlist2"]

{-
let rec zip l1 l2 =
  match (l1,l2) with
        ([],[]) -> []
      | (h1::t1,h2::t2) -> (h1,h2)::(zip t1 t2)
      | _ -> failwith "zip";;

let rec forall p l =
  match l with
    [] -> true
  | h::t -> p(h) & forall p t;;
-}
exists :: (a -> Bool) -> [a] -> Bool
exists = any
{-
let partition p l =
    itlist (fun a (yes,no) -> if p a then a::yes,no else yes,a::no) l ([],[]);;

let filter p l = fst(partition p l);;

let length =
  let rec len k l =
    if l = [] then k else len (k + 1) (tl l) in
  fun l -> len 0 l;;

let rec last l =
  match l with
    [x] -> x
  | (h::t) -> last t
  | [] -> failwith "last";;

let rec butlast l =
  match l with
    [_] -> []
  | (h::t) -> h::(butlast t)
  | [] -> failwith "butlast";;

let rec find p l =
  match l with
      [] -> failwith "find"
    | (h::t) -> if p(h) then h else find p t;;

let rec el n l =
  if n = 0 then hd l else el (n - 1) (tl l);;

let map f =
  let rec mapf l =
    match l with
      [] -> []
    | (x::t) -> let y = f x in y::(mapf t) in
  mapf;;
-}

allpairs :: forall a b c. (Ord c) => (a -> b -> c) -> Set a -> Set b -> Set c
-- allpairs f xs ys = Set.fromList (concatMap (\ z -> map (f z) (Set.toList ys)) (Set.toList xs))
allpairs f xs ys = Set.fold (\ x zs -> Set.fold (\ y zs' -> Set.insert (f x y) zs') zs ys) Set.empty xs

distrib' :: Ord a => Set (Set a) -> Set (Set a) -> Set (Set a)
distrib' s1 s2 = allpairs (Set.union) s1 s2

test01 :: Test
test01 = TestCase $ assertEqual "itlist2" expected input
    where input = allpairs (,) (Set.fromList [1,2,3]) (Set.fromList [4,5,6])
          expected = Set.fromList [(1,4),(1,5),(1,6),(2,4),(2,5),(2,6),(3,4),(3,5),(3,6)] :: Set (Int, Int)

{-
let rec distinctpairs l =
  match l with
   x::t -> itlist (fun y a -> (x,y) :: a) t (distinctpairs t)
  | [] -> [];;

let rec chop_list n l =
  if n = 0 then [],l else
  try let m,l' = chop_list (n-1) (tl l) in (hd l)::m,l'
  with Failure _ -> failwith "chop_list";;

let replicate n a = map (fun x -> a) (1--n);;

let rec insertat i x l =
  if i = 0 then x::l else
  match l with
    [] -> failwith "insertat: list too short for position to exist"
  | h::t -> h::(insertat (i-1) x t);;

let rec forall2 p l1 l2 =
  match (l1,l2) with
    [],[] -> true
  | (h1::t1,h2::t2) -> p h1 h2 & forall2 p t1 t2
  | _ -> false;;

let index x =
  let rec ind n l =
    match l with
      [] -> failwith "index"
    | (h::t) -> if Pervasives.compare x h = 0 then n else ind (n + 1) t in
  ind 0;;

let rec unzip l =
  match l with
    [] -> [],[]
  | (x,y)::t ->
      let xs,ys = unzip t in x::xs,y::ys;;

(* ------------------------------------------------------------------------- *)
(* Whether the first of two items comes earlier in the list.                 *)
(* ------------------------------------------------------------------------- *)

let rec earlier l x y =
  match l with
    h::t -> (Pervasives.compare h y <> 0) &
            (Pervasives.compare h x = 0 or earlier t x y)
  | [] -> false;;

(* ------------------------------------------------------------------------- *)
(* Application of (presumably imperative) function over a list.              *)
(* ------------------------------------------------------------------------- *)

let rec do_list f l =
  match l with
    [] -> ()
  | h::t -> f(h); do_list f t;;

(* ------------------------------------------------------------------------- *)
(* Association lists.                                                        *)
(* ------------------------------------------------------------------------- *)

let rec assoc a l =
  match l with
    (x,y)::t -> if Pervasives.compare x a = 0 then y else assoc a t
  | [] -> failwith "find";;

let rec rev_assoc a l =
  match l with
    (x,y)::t -> if Pervasives.compare y a = 0 then x else rev_assoc a t
  | [] -> failwith "find";;

(* ------------------------------------------------------------------------- *)
(* Merging of sorted lists (maintaining repetitions).                        *)
(* ------------------------------------------------------------------------- *)

let rec merge ord l1 l2 =
  match l1 with
    [] -> l2
  | h1::t1 -> match l2 with
                [] -> l1
              | h2::t2 -> if ord h1 h2 then h1::(merge ord t1 l2)
                          else h2::(merge ord l1 t2);;

(* ------------------------------------------------------------------------- *)
(* Bottom-up mergesort.                                                      *)
(* ------------------------------------------------------------------------- *)

let sort ord =
  let rec mergepairs l1 l2 =
    match (l1,l2) with
        ([s],[]) -> s
      | (l,[]) -> mergepairs [] l
      | (l,[s1]) -> mergepairs (s1::l) []
      | (l,(s1::s2::ss)) -> mergepairs ((merge ord s1 s2)::l) ss in
  fun l -> if l = [] then [] else mergepairs [] (map (fun x -> [x]) l);;

(* ------------------------------------------------------------------------- *)
(* Common measure predicates to use with "sort".                             *)
(* ------------------------------------------------------------------------- *)

let increasing f x y = Pervasives.compare (f x) (f y) < 0;;

let decreasing f x y = Pervasives.compare (f x) (f y) > 0;;

(* ------------------------------------------------------------------------- *)
(* Eliminate repetitions of adjacent elements, with and without counting.    *)
(* ------------------------------------------------------------------------- *)

let rec uniq l =
  match l with
    x::(y::_ as t) -> let t' = uniq t in
                      if Pervasives.compare x y = 0 then t' else
                      if t'==t then l else x::t'
 | _ -> l;;

let repetitions =
  let rec repcount n l =
    match l with
      x::(y::_ as ys) -> if Pervasives.compare y x = 0 then repcount (n + 1) ys
                  else (x,n)::(repcount 1 ys)
    | [x] -> [x,n]
    | [] -> failwith "repcount" in
  fun l -> if l = [] then [] else repcount 1 l;;
-}

tryfind :: (t -> Failing a) -> [t] -> Failing a
tryfind _ [] = Failure ["tryfind"]
tryfind f l =
    case l of
      [] -> Failure ["tryfind"]
      h : t -> failing (\ _ -> tryfind f t) Success (f h)

settryfind :: (t -> Failing a) -> Set t -> Failing a
settryfind f l =
    case Set.minView l of
      Nothing -> Failure ["settryfind"]
      Just (h, t) -> failing (\ _ -> settryfind f t) Success (f h)

mapfilter :: (a -> Failing b) -> [a] -> [b]
mapfilter f l = catMaybes (List.map (failing (const Nothing) Just . f) l) 
    -- filter (failing (const False) (const True)) (map f l)

setmapfilter :: Ord b => (a -> Failing b) -> Set a -> Set b
setmapfilter f s = Set.fold (\ a r -> failing (const r) (`Set.insert` r) (f a)) Set.empty s

-- -------------------------------------------------------------------------
-- Find list member that maximizes or minimizes a function.                 
-- -------------------------------------------------------------------------

optimize :: forall a b. (b -> b -> Bool) -> (a -> b) -> [a] -> Maybe a
optimize _ _ [] = Nothing
optimize ord f l = Just (fst (foldr1 (\ p@(_,y) p'@(_,y') -> if ord y y' then p else p') (List.map (\ x -> (x,f x)) l)))

maximize :: forall a b. Ord b => (a -> b) -> [a] -> Maybe a
maximize f l = optimize (>) f l

minimize :: forall a b. Ord b => (a -> b) -> [a] -> Maybe a
minimize f l = optimize (<) f l

optimize' :: forall a b. (b -> b -> Bool) -> (a -> b) -> Set a -> Maybe a
optimize' ord f s = optimize ord f (Set.toAscList s)

maximize' :: forall a b. Ord b => (a -> b) -> Set a -> Maybe a
maximize' f s = optimize' (>) f s

minimize' :: forall a b. Ord b => (a -> b) -> Set a -> Maybe a
minimize' f s = optimize' (<) f s

-- -------------------------------------------------------------------------
-- Set operations on ordered lists.                                         
-- -------------------------------------------------------------------------
{-
let setify =
  let rec canonical lis =
     match lis with
       x::(y::_ as rest) -> Pervasives.compare x y < 0 & canonical rest
     | _ -> true in
  fun l -> if canonical l then l
           else uniq (sort (fun x y -> Pervasives.compare x y <= 0) l);;

let union =
  let rec union l1 l2 =
    match (l1,l2) with
        ([],l2) -> l2
      | (l1,[]) -> l1
      | ((h1::t1 as l1),(h2::t2 as l2)) ->
          if h1 = h2 then h1::(union t1 t2)
          else if h1 < h2 then h1::(union t1 l2)
          else h2::(union l1 t2) in
  fun s1 s2 -> union (setify s1) (setify s2);;

let intersect =
  let rec intersect l1 l2 =
    match (l1,l2) with
        ([],l2) -> []
      | (l1,[]) -> []
      | ((h1::t1 as l1),(h2::t2 as l2)) ->
          if h1 = h2 then h1::(intersect t1 t2)
          else if h1 < h2 then intersect t1 l2
          else intersect l1 t2 in
  fun s1 s2 -> intersect (setify s1) (setify s2);;

let subtract =
  let rec subtract l1 l2 =
    match (l1,l2) with
        ([],l2) -> []
      | (l1,[]) -> l1
      | ((h1::t1 as l1),(h2::t2 as l2)) ->
          if h1 = h2 then subtract t1 t2
          else if h1 < h2 then h1::(subtract t1 l2)
          else subtract l1 t2 in
  fun s1 s2 -> subtract (setify s1) (setify s2);;

let subset,psubset =
  let rec subset l1 l2 =
    match (l1,l2) with
        ([],l2) -> true
      | (l1,[]) -> false
      | (h1::t1,h2::t2) ->
          if h1 = h2 then subset t1 t2
          else if h1 < h2 then false
          else subset l1 t2
  and psubset l1 l2 =
    match (l1,l2) with
        (l1,[]) -> false
      | ([],l2) -> true
      | (h1::t1,h2::t2) ->
          if h1 = h2 then psubset t1 t2
          else if h1 < h2 then false
          else subset l1 t2 in
  (fun s1 s2 -> subset (setify s1) (setify s2)),
  (fun s1 s2 -> psubset (setify s1) (setify s2));;

let rec set_eq s1 s2 = (setify s1 = setify s2);;

let insert x s = union [x] s;;
-}

image :: (Ord b, Ord a) => (a -> b) -> Set a -> Set b
image f s = Set.map f s

{-
(* ------------------------------------------------------------------------- *)
(* Union of a family of sets.                                                *)
(* ------------------------------------------------------------------------- *)

let unions s = setify(itlist (@) s []);;

(* ------------------------------------------------------------------------- *)
(* List membership. This does *not* assume the list is a set.                *)
(* ------------------------------------------------------------------------- *)

let rec mem x lis =
  match lis with
    [] -> false
  | (h::t) -> Pervasives.compare x h = 0 or mem x t;;
-}

-- ------------------------------------------------------------------------- 
-- Finding all subsets or all subsets of a given size.                       
-- ------------------------------------------------------------------------- 

-- allsets :: Ord a => Int -> Set a -> Set (Set a)
allsets :: forall a b. (Num a, Eq a, Ord b) => a -> Set b -> Set (Set b)
allsets 0 _ = Set.singleton Set.empty
allsets m l =
    case Set.minView l of
      Nothing -> Set.empty
      Just (h, t) -> Set.union (Set.map (Set.insert h) (allsets (m - 1) t)) (allsets m t)

allsubsets :: forall a. Ord a => Set a -> Set (Set a)
allsubsets s =
    maybe (Set.singleton Set.empty)
          (\ (x, t) -> 
               let res = allsubsets t in
               Set.union res (Set.map (Set.insert x) res))
          (Set.minView s)


allnonemptysubsets :: forall a. Ord a => Set a -> Set (Set a)
allnonemptysubsets s = Set.delete Set.empty (allsubsets s)

{-
(* ------------------------------------------------------------------------- *)
(* Explosion and implosion of strings.                                       *)
(* ------------------------------------------------------------------------- *)

let explode s =
  let rec exap n l =
     if n < 0 then l else
      exap (n - 1) ((String.sub s n 1)::l) in
  exap (String.length s - 1) [];;

let implode l = itlist (^) l "";;

(* ------------------------------------------------------------------------- *)
(* Timing; useful for documentation but not logically necessary.             *)
(* ------------------------------------------------------------------------- *)

let time f x =
  let start_time = Sys.time() in
  let result = f x in
  let finish_time = Sys.time() in
  print_string
    ("CPU time (user): "^(string_of_float(finish_time -. start_time)));
  print_newline();
  result;;
-}

-- -------------------------------------------------------------------------
-- Polymorphic finite partial functions via Patricia trees.                 
--                                                                          
-- The point of this strange representation is that it is canonical (equal  
-- functions have the same encoding) yet reasonably efficient on average.   
--                                                                          
-- Idea due to Diego Olivier Fernandez Pons (OCaml list, 2003/11/10).       
-- -------------------------------------------------------------------------

data Func a b
    = Empty
    | Leaf Int [(a, b)]
    | Branch Int Int (Func a b) (Func a b)

-- -------------------------------------------------------------------------
-- Undefined function.                                                      
-- -------------------------------------------------------------------------

undefinedFunction :: Func a b
undefinedFunction = Empty

-- -------------------------------------------------------------------------
-- In case of equality comparison worries, better use this.                 
-- -------------------------------------------------------------------------

isUndefined :: Func a b -> Bool
isUndefined Empty = True
isUndefined _ = False

-- -------------------------------------------------------------------------
-- Operation analogous to "map" for functions.                                  
-- -------------------------------------------------------------------------

mapf :: (b -> c) -> Func a b -> Func a c
mapf f t =
    case t of
      Empty -> Empty
      Leaf h l -> Leaf h (map_list f l)
      Branch p b l r -> Branch p b (mapf f l) (mapf f r)
    where
      map_list f' l' =
          case l' of
            [] -> []
            (x,y) : t' -> (x, f' y) : map_list f' t'

-- -------------------------------------------------------------------------
-- Operations analogous to "fold" for lists.
-- -------------------------------------------------------------------------

foldlFn :: (r -> a -> b -> r) -> r -> Func a b -> r
foldlFn f a t =
    case t of
      Empty -> a
      Leaf _h l -> foldl_list f a l
      Branch _p _b l r -> foldlFn f (foldlFn f a l) r
    where
      foldl_list _f a' l =
          case l of
            [] -> a'
            (x,y) : t' -> foldl_list f (f a' x y) t'

foldrFn :: (a -> b -> r -> r) -> Func a b -> r -> r
foldrFn f t a =
    case t of
      Empty -> a
      Leaf _h l -> foldr_list f l a
      Branch _p _b l r -> foldrFn f l (foldrFn f r a)
    where
      foldr_list f' l a' =
          case l of
            [] -> a'
            (x, y) : t' -> f' x y (foldr_list f' t' a')

-- -------------------------------------------------------------------------
-- Mapping to sorted-list representation of the graph, domain and range.
-- -------------------------------------------------------------------------

graph :: (Ord a, Ord b) => Func a b -> Set (a, b)
graph f = Set.fromList (foldlFn (\ a x y -> (x,y) : a) [] f)

dom :: Ord a => Func a b -> Set a
dom f = Set.fromList (foldlFn (\ a x _y -> x :a) [] f)

ran :: Ord b => Func a b -> Set b
ran f = Set.fromList (foldlFn (\ a _x y -> y : a) [] f)

-- -------------------------------------------------------------------------
-- Application.                                                             
-- -------------------------------------------------------------------------

applyD :: Ord k => Map.Map k a -> k -> a -> Map.Map k a
applyD m k a = Map.insert k a m

apply :: Ord k => Map.Map k a -> k -> Maybe a
apply m k = Map.lookup k m

tryApplyD :: Ord k => Map.Map k a -> k -> a -> a
tryApplyD m k d = fromMaybe d (Map.lookup k m)

tryApplyL :: Ord k => Map.Map k [a] -> k -> [a]
tryApplyL m k = tryApplyD m k []
{-
applyD :: (t -> Maybe b) -> (t -> b) -> t -> b
applyD f d x = maybe (d x) id (f x)

apply :: (t -> Maybe b) -> t -> b
apply f = applyD f (\ _ -> error "apply")

tryApplyD :: (t -> Maybe b) -> t -> b -> b
tryApplyD f a d = maybe d id (f a)

tryApplyL :: (t -> Maybe [a]) -> t -> [a]
tryApplyL f x = tryApplyD f x []
-}

defined :: Ord t => Map.Map t a -> t -> Bool
defined = flip Map.member

-- | Undefinition.
undefine :: forall k a. Ord k => k -> Map k a -> Map k a
undefine k mp = Map.delete k mp

{-
(* ------------------------------------------------------------------------- *)
(* Redefinition and combination.                                             *)
(* ------------------------------------------------------------------------- *)

let (|->),combine =
  let newbranch p1 t1 p2 t2 =
    let zp = p1 lxor p2 in
    let b = zp land (-zp) in
    let p = p1 land (b - 1) in
    if p1 land b = 0 then Branch(p,b,t1,t2)
    else Branch(p,b,t2,t1) in
  let rec define_list (x,y as xy) l =
    match l with
      (a,b as ab)::t ->
          let c = Pervasives.compare x a in
          if c = 0 then xy::t
          else if c < 0 then xy::l
          else ab::(define_list xy t)
    | [] -> [xy]
  and combine_list op z l1 l2 =
    match (l1,l2) with
      [],_ -> l2
    | _,[] -> l1
    | ((x1,y1 as xy1)::t1,(x2,y2 as xy2)::t2) ->
          let c = Pervasives.compare x1 x2 in
          if c < 0 then xy1::(combine_list op z t1 l2)
          else if c > 0 then xy2::(combine_list op z l1 t2) else
          let y = op y1 y2 and l = combine_list op z t1 t2 in
          if z(y) then l else (x1,y)::l in
  let (|->) x y =
    let k = Hashtbl.hash x in
    let rec upd t =
      match t with
        Empty -> Leaf (k,[x,y])
      | Leaf(h,l) ->
           if h = k then Leaf(h,define_list (x,y) l)
           else newbranch h t k (Leaf(k,[x,y]))
      | Branch(p,b,l,r) ->
          if k land (b - 1) <> p then newbranch p t k (Leaf(k,[x,y]))
          else if k land b = 0 then Branch(p,b,upd l,r)
          else Branch(p,b,l,upd r) in
    upd in
  let rec combine op z t1 t2 =
    match (t1,t2) with
      Empty,_ -> t2
    | _,Empty -> t1
    | Leaf(h1,l1),Leaf(h2,l2) ->
          if h1 = h2 then
            let l = combine_list op z l1 l2 in
            if l = [] then Empty else Leaf(h1,l)
          else newbranch h1 t1 h2 t2
    | (Leaf(k,lis) as lf),(Branch(p,b,l,r) as br) ->
          if k land (b - 1) = p then
            if k land b = 0 then
              (match combine op z lf l with
                 Empty -> r | l' -> Branch(p,b,l',r))
            else
              (match combine op z lf r with
                 Empty -> l | r' -> Branch(p,b,l,r'))
          else
            newbranch k lf p br
    | (Branch(p,b,l,r) as br),(Leaf(k,lis) as lf) ->
          if k land (b - 1) = p then
            if k land b = 0 then
              (match combine op z l lf with
                Empty -> r | l' -> Branch(p,b,l',r))
            else
              (match combine op z r lf with
                 Empty -> l | r' -> Branch(p,b,l,r'))
          else
            newbranch p br k lf
    | Branch(p1,b1,l1,r1),Branch(p2,b2,l2,r2) ->
          if b1 < b2 then
            if p2 land (b1 - 1) <> p1 then newbranch p1 t1 p2 t2
            else if p2 land b1 = 0 then
              (match combine op z l1 t2 with
                 Empty -> r1 | l -> Branch(p1,b1,l,r1))
            else
              (match combine op z r1 t2 with
                 Empty -> l1 | r -> Branch(p1,b1,l1,r))
          else if b2 < b1 then
            if p1 land (b2 - 1) <> p2 then newbranch p1 t1 p2 t2
            else if p1 land b2 = 0 then
              (match combine op z t1 l2 with
                 Empty -> r2 | l -> Branch(p2,b2,l,r2))
            else
              (match combine op z t1 r2 with
                 Empty -> l2 | r -> Branch(p2,b2,l2,r))
          else if p1 = p2 then
           (match (combine op z l1 l2,combine op z r1 r2) with
              (Empty,r) -> r | (l,Empty) -> l | (l,r) -> Branch(p1,b1,l,r))
          else
            newbranch p1 t1 p2 t2 in
  (|->),combine;;
-}

-- -------------------------------------------------------------------------
-- Special case of point function.                                          
-- -------------------------------------------------------------------------

(|=>) :: Ord k => k -> a -> Map.Map k a
x |=> y = Map.fromList [(x, y)]

-- -------------------------------------------------------------------------
-- Idiom for a mapping zipping domain and range lists.                      
-- -------------------------------------------------------------------------

(|->) :: Ord k => k -> a -> Map.Map k a -> Map.Map k a
(|->) a b m = Map.insert a b m

fpf :: Ord a => Map.Map a b -> a -> Maybe b
fpf m a = Map.lookup a m

-- -------------------------------------------------------------------------
-- Grab an arbitrary element.                                               
-- -------------------------------------------------------------------------

choose :: Map.Map k a -> (k, a)
choose = Map.findMin

{-
(* ------------------------------------------------------------------------- *)
(* Install a (trivial) printer for finite partial functions.                 *)
(* ------------------------------------------------------------------------- *)

let print_fpf (f:('a,'b)func) = print_string "<func>";;

#install_printer print_fpf;;

(* ------------------------------------------------------------------------- *)
(* Related stuff for standard functions.                                     *)
(* ------------------------------------------------------------------------- *)

let valmod a y f x = if x = a then y else f(x);;

let undef x = failwith "undefined function";;

(* ------------------------------------------------------------------------- *)
(* Union-find algorithm.                                                     *)
(* ------------------------------------------------------------------------- *)

type ('a)pnode = Nonterminal of 'a | Terminal of 'a * int;;

type ('a)partition = Partition of ('a,('a)pnode)func;;

let rec terminus (Partition f as ptn) a =
  match (apply f a) with
    Nonterminal(b) -> terminus ptn b
  | Terminal(p,q) -> (p,q);;

let tryterminus ptn a =
  try terminus ptn a with Failure _ -> (a,1);;

let canonize ptn a = fst(tryterminus ptn a);;

let equivalent eqv a b = canonize eqv a = canonize eqv b;;

let equate (a,b) (Partition f as ptn) =
  let (a',na) = tryterminus ptn a
  and (b',nb) = tryterminus ptn b in
  Partition
   (if a' = b' then f else
    if na <= nb then
       itlist identity [a' |-> Nonterminal b'; b' |-> Terminal(b',na+nb)] f
    else
       itlist identity [b' |-> Nonterminal a'; a' |-> Terminal(a',na+nb)] f);;

let unequal = Partition undefined;;

let equated (Partition f) = dom f;;

(* ------------------------------------------------------------------------- *)
(* First number starting at n for which p succeeds.                          *)
(* ------------------------------------------------------------------------- *)

let rec first n p = if p(n) then n else first (n +/ Int 1) p;;
-}

tests :: Test
tests = TestLabel "Lib" $ TestList [test01]