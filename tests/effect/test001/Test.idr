module Test

import Data.List
import Data.Vect
import Data.Either
import Data.Maybe
import Data.String
import Data.Ref
import Control.Monad.Reader
import Control.Monad.Writer
import Control.Monad.Either
import Control.Monad.Identity
import Control.Monad.Free

import Control.Algebra
import Control.Effect.Writer
import Control.Effect.Reader
import Control.Effect.Exception
import Control.Cont.Void
import Control.Cont.State
import Control.Cont.Thread
import Control.Cont.Out
import Control.Cont.IO
import Control.Cont.Exception

-------------------------------------
throwSnapshot : (Syntax sig, Sub (EitherC (e, s)) sig, Sub (StateC s) sig) => e -> Free sig a
throwSnapshot err = do
  v <- get {s}
  throw (err, v)

decr : (Syntax sig, Sub (StateC Int) sig, Sub (EitherC ()) sig) => Free sig ()
decr = do
  x <- get {s = Int}
  if x > 0 then put (x - 1)
     else throw ()

incr : (Syntax sig, Sub (StateC Int) sig) => Free sig ()
incr = do
  x <- get {s = Int}
  put (x + 1)

testStateExc : Syntax sig
           => (s : Sub (StateC Int) sig)
           => (e : Sub (EitherC (String, Int)) sig)
           => Free sig (String, Int)
testStateExc = do
  catch {e = (String, Int)} (incr >> throwSnapshot {s = Int} "thrown") \(str, i) => do
    incr >> return (str ++ "-return", i + 22)

testStateExcRun : Either (String, Int) (Int, (String, Int))
testStateExcRun = runVoidC . runEitherC . runStateC 3 $ testStateExc
  {e = T @{L} @{R}}
  {s = L}

-------------------------------------

tripleDecr : Syntax sig => (s : Sub (StateC Int) sig) => (e : Sub (EitherC ()) sig) => Free sig ()
tripleDecr = decr >> catch (decr >> decr) return

tripleDecrInst : Free (StateC Int :+: (EitherC () :+: VoidE)) ()
tripleDecrInst = tripleDecr
  {e = MkSub (Inr . Inl) \case Inr (Inl x) => Just x; _ => Nothing}
  {s = MkSub Inl \case (Inl x) => Just x; _ => Nothing}

tripleDecrInst' : Free (EitherC () :+: (StateC Int :+: VoidE)) ()
tripleDecrInst' = tripleDecr
  {e = MkSub Inl \case (Inl x) => Just x; _ => Nothing}
  {s = MkSub (Inr . Inl) \case (Inr (Inl x)) => Just x; _ => Nothing}

runLocal : Either () (Int, ())
runLocal = runVoidC . runEitherC . runStateC 2 $ tripleDecrInst

runGlobal : (Int, Either () ())
runGlobal = runVoidC . runStateC 2 . runEitherC $ tripleDecrInst'

-----------------------

%hide Control.Monad.Writer.Interface.tell
%hide Control.Monad.Reader.Interface.ask

testFused : (a : Algebra sig m)
      => (r : Sub (ReaderE Nat) sig)
      => (w : Sub (WriterE (List Nat)) sig)
      => m String
testFused = do
  x <- ask {r = Nat}
  tell {w = List Nat} [x + 1]
  tell {w = List Nat} [x + 3, x + 2]
  pure "Done"

%hint
MyWriter : Monoid s => Algebra sig m => Algebra (WriterE s :+: sig) (WriterT s m)
MyWriter = ConcatLeft

handleFused : ReaderT Nat (WriterT (List Nat) Identity) String
handleFused = testFused {sig = ReaderE Nat :+: WriterE (List Nat) :+: VoidE}
               {r = L}
               {w = T @{L} @{R}}

runFused : List Nat
runFused = runIdentity . map snd . runWriterT . runReaderT 20 $ handleFused

-----------------------

testEitherE : (a : Algebra sig m)
       => (r : Sub (ReaderE Nat) sig)
       => (w : Sub (WriterE (List Nat)) sig)
       => (e : Sub (EitherE String) sig)
       => (toThrow : Bool)
       -> m String
testEitherE toThrow = do
  x <- ask {r = Nat}
  tell {w = List Nat} [1, x]
  tell {w = List Nat} [3, 2]
  r <- try {e = String}
        (do tell {w = List Nat} [6, 5, 4]
            if toThrow then fail "fail" else pure "pure")
    (\er => pure "on throw")
  pure r

handleEitherE : Bool -> (WriterT (List Nat) $ ReaderT Nat $ EitherT String Identity) String
handleEitherE x = testEitherE x {sig = WriterE (List Nat) :+: ReaderE Nat :+: EitherE String :+: VoidE}
                  {w = L}
                  {r = T @{L} @{R}}
                  {e = T @{T @{L} @{R}} @{R}}

runEitherE : Bool -> Either String (String, List Nat)
runEitherE x = runIdentity . runEitherT . runReaderT 0 . runWriterT $ handleEitherE x

-----------------------

main : IO ()
main = pure ()